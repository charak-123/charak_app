import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/api_client.dart';

/// A push that arrived, flattened to what the apps actually route on.
@immutable
class CharakPushMessage {
  /// The backend's event name, e.g. `booking.requested`, `payment.confirmed`,
  /// `senior_review.decided`. Mirrors `services/notifications.py`.
  final String event;
  final String? title;
  final String? body;
  final String? bookingId;
  final Map<String, String> data;

  /// True when the person tapped the notification (from the tray, or the
  /// banner shown while the app was open); false when it simply arrived
  /// while they were using the app. Only a tap should move them to another
  /// screen: a push that arrives mid-task used to yank them off whatever
  /// they were doing.
  final bool opened;

  const CharakPushMessage({
    required this.event,
    this.title,
    this.body,
    this.bookingId,
    this.data = const {},
    this.opened = false,
  });

  factory CharakPushMessage.fromRemote(RemoteMessage m, {bool opened = false}) =>
      CharakPushMessage.fromData(
        m.data.map((k, v) => MapEntry(k, '$v')),
        title: m.notification?.title,
        body: m.notification?.body,
        opened: opened,
      );

  factory CharakPushMessage.fromData(Map<String, String> data,
          {String? title, String? body, bool opened = false}) =>
      CharakPushMessage(
        event: data['event'] ?? 'unknown',
        title: title ?? data['title'],
        body: body ?? data['body'],
        bookingId: data['booking_id'],
        data: data,
        opened: opened,
      );
}

/// Registers this device for push and surfaces what arrives.
///
/// The backend half is already complete — `services/notifications.py` persists
/// and sends every event, and `POST /push/register` stores the token. This is
/// the device end of that contract.
///
/// Firebase is optional at runtime: without `google-services.json` the
/// initialize call throws, and [start] records that and returns quietly rather
/// than taking the app down. [available] says whether push is actually live.
class CharakPush {
  CharakPush._();
  static final CharakPush instance = CharakPush._();

  // Channel ids match backend services/notifications.py, which names one on
  // every push. Android shows a heads-up banner only on a high-importance
  // channel, and a push that names none lands on FCM's own quiet fallback.
  static const _androidChannel = AndroidNotificationChannel(
    'charak_default',
    'Bookings and payments',
    description: 'Booking requests and answers, payments and visit updates.',
    importance: Importance.high,
  );

  /// Separate so someone can keep calls ringing and quiet everything else.
  static const _callsChannel = AndroidNotificationChannel(
    'charak_calls',
    'Calls',
    description: 'A doctor calling you about a booking.',
    importance: Importance.max,
  );

  final _controller = StreamController<CharakPushMessage>.broadcast();
  final _local = FlutterLocalNotificationsPlugin();

  bool _started = false;
  bool _available = false;

  /// Firebase stream subscriptions opened by [start], cancelled by [stop].
  /// Without this a logout→login on the same launch registered a second set,
  /// so every push was delivered twice: duplicate local notifications and a
  /// double router.go() from the app-level listeners.
  final _subs = <StreamSubscription<dynamic>>[];
  String? _token;
  String? _unavailableReason;

  /// Messages received while the app is in the foreground, plus the message
  /// that opened the app from a notification tap.
  Stream<CharakPushMessage> get messages => _controller.stream;

  bool get available => _available;
  String? get token => _token;

  /// Why push is not running, for the profile screen's diagnostics.
  String? get unavailableReason => _unavailableReason;

  /// Brings up Firebase, asks for permission, registers the token with the
  /// backend and starts forwarding messages. Safe to call more than once.
  ///
  /// Call after the user is authenticated — registration is an authenticated
  /// request, and a token stored against the wrong user sends one person's
  /// medical notifications to another.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      _unavailableReason = 'Firebase is not configured for this build';
      debugPrint('[push] Firebase unavailable: $e');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    try {
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _unavailableReason = 'Notifications are turned off for Charak';
        return;
      }

      await _initLocalNotifications();

      _token = await messaging.getToken();
      if (_token != null) await _register(_token!);

      // A rotated token is useless to the backend until it is re-registered.
      _subs.add(messaging.onTokenRefresh.listen((t) {
        _token = t;
        _register(t);
      }));

      _subs.add(FirebaseMessaging.onMessage.listen(_onForeground));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _controller.add(CharakPushMessage.fromRemote(m, opened: true)),
      ));
      // The notification that cold-started the app: from the tray (FCM), or
      // a banner this class raised before the app was closed.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _controller.add(CharakPushMessage.fromRemote(initial, opened: true));
      } else {
        final launch = await _local.getNotificationAppLaunchDetails();
        final payload = launch?.notificationResponse?.payload;
        if (launch?.didNotificationLaunchApp == true && payload != null) _onLocalTap(payload);
      }

      _available = true;
      _unavailableReason = null;
    } catch (e) {
      _unavailableReason = 'Could not register for notifications';
      debugPrint('[push] registration failed: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    // Android suppresses foreground notifications, so they are re-raised here.
    // A tap on one of these banners used to do nothing: there was no
    // handler, so "Request accepted" opened nothing while the app was open.
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        final payload = r.payload;
        if (payload != null) _onLocalTap(payload);
      },
    );
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_androidChannel);
    await android?.createNotificationChannel(_callsChannel);
  }

  void _onLocalTap(String payload) {
    try {
      final data = (jsonDecode(payload) as Map).map((k, v) => MapEntry('$k', '$v'));
      _controller.add(CharakPushMessage.fromData(data, opened: true));
    } catch (e) {
      debugPrint('[push] unreadable notification payload: $e');
    }
  }

  void _onForeground(RemoteMessage m) {
    final message = CharakPushMessage.fromRemote(m);
    _controller.add(message);

    // Android doesn't show a push that arrives while the app is open, so it
    // is raised here. A ringing call isn't: the app shows its own incoming
    // call screen for that.
    final notification = m.notification;
    if (notification == null || message.event == 'call.incoming') return;
    final channel = _androidChannel;
    _local.show(
      // One banner per booking and event, as the backend tags them: a repeat
      // replaces the last rather than stacking.
      '${message.event}:${message.bookingId}'.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _register(String fcmToken) async {
    try {
      await ApiClient.instance.post('/push/register', {
        'fcm_token': fcmToken,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      // Delivery is a convenience; a failed registration must never block
      // the screen that triggered it.
      debugPrint('[push] could not register token with backend: $e');
    }
  }

  /// Clears the token server-side and locally. Call on logout — otherwise the
  /// next user of the device receives the previous doctor's requests.
  Future<void> stop() async {
    // Name this device's token, so only this device is forgotten. A doctor
    // signed in on a phone and a tablet who signs out of one keeps pushes on
    // the other. Without a token the server forgets every device (safe, broader).
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      // Firebase never came up on this device; nothing to name.
    }
    try {
      final query = token == null ? '' : '?${Uri(queryParameters: {'token': token}).query}';
      await ApiClient.instance.delete('/push/register$query');
    } catch (e) {
      debugPrint('[push] could not unregister token: $e');
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Nothing to delete when Firebase never came up.
    }
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();

    _token = null;
    _available = false;
    _started = false;
  }
}

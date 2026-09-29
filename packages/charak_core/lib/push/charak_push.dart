import 'dart:async';
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

  const CharakPushMessage({
    required this.event,
    this.title,
    this.body,
    this.bookingId,
    this.data = const {},
  });

  factory CharakPushMessage.fromRemote(RemoteMessage m) {
    final data = m.data.map((k, v) => MapEntry(k, '$v'));
    return CharakPushMessage(
      event: data['event'] ?? 'unknown',
      title: m.notification?.title ?? data['title'],
      body: m.notification?.body ?? data['body'],
      bookingId: data['booking_id'],
      data: data,
    );
  }
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

  static const _androidChannel = AndroidNotificationChannel(
    'charak_default',
    'Charak',
    description: 'Booking requests, payments and review decisions.',
    importance: Importance.high,
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
        (m) => _controller.add(CharakPushMessage.fromRemote(m)),
      ));
      // The notification that cold-started the app.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _controller.add(CharakPushMessage.fromRemote(initial));
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
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  void _onForeground(RemoteMessage m) {
    _controller.add(CharakPushMessage.fromRemote(m));

    final notification = m.notification;
    if (notification == null) return;
    _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
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
    try {
      await ApiClient.instance.delete('/push/register');
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

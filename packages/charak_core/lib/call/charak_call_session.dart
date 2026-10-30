import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../crash/charak_crash.dart';

/// What the backend hands back from `/bookings/{id}/clarification-call` and
/// `/bookings/{id}/call`. The backend mints a clearly-labelled stub token
/// until AGORA_APP_ID and AGORA_APP_CERTIFICATE are set, so [live] tells the
/// app whether there is a real channel to join at all.
@immutable
class CharakCallCredentials {
  final String? appId;
  final String channel;
  final String token;
  final int uid;
  final bool live;

  const CharakCallCredentials({
    required this.appId,
    required this.channel,
    required this.token,
    required this.uid,
    required this.live,
  });

  /// Reads the shape both call endpoints return. [channelFallback] covers the
  /// patient endpoint, which names the channel after the booking.
  factory CharakCallCredentials.fromJson(
    Map<String, dynamic> json, {
    required int uid,
    String? channelFallback,
  }) {
    final token = (json['agora_token'] ?? json['token'] ?? '') as String;
    final appId = json['agora_app_id'] as String?;
    final channel =
        (json['agora_channel'] as String?) ?? channelFallback ?? '';
    // `live` is authoritative when present; otherwise infer from the stub
    // token prefix the backend uses when credentials are missing.
    final live = (json['live'] as bool?) ??
        (token.isNotEmpty &&
            !token.startsWith('stub_') &&
            (appId ?? '').isNotEmpty);
    return CharakCallCredentials(
      appId: appId,
      channel: channel,
      token: token,
      uid: (json['uid'] as int?) ?? uid,
      live: live,
    );
  }

  /// True when there is nothing real to join — the UI still runs so the flow
  /// is testable without Agora credentials.
  bool get isStub =>
      !live || token.isEmpty || channel.isEmpty || (appId ?? '').isEmpty;
}

enum CharakCallStage { idle, connecting, waitingForPeer, connected, failed, ended }

/// Owns the Agora engine for one call: permissions, join, the mute/camera
/// toggles, the elapsed clock, and the two video views.
///
/// In stub mode no engine is created — the session reports
/// [CharakCallStage.waitingForPeer] and [isStub], and the screens fall back to
/// the avatar field of `CharakCallScaffold`.
class CharakCallSession extends ChangeNotifier {
  /// How long joining may take before the call is reported as failed. Agora
  /// keeps retrying a join it cannot complete (no network, a firewall) and
  /// says nothing, so without this the screen sat on "Ringing…" for ever.
  static const joinTimeout = Duration(seconds: 20);

  CharakCallStage _stage = CharakCallStage.idle;
  CharakCallCredentials? _creds;
  RtcEngine? _engine;
  int? _remoteUid;
  bool _micOn = true;
  bool _cameraOn = true;
  bool _localReady = false;
  bool _reconnecting = false;
  String? _error;
  Timer? _tick;
  Timer? _joinTimer;
  Duration _elapsed = Duration.zero;
  bool _disposed = false;

  CharakCallStage get stage => _stage;
  bool get isStub => _creds?.isStub ?? true;
  bool get micOn => _micOn;
  bool get cameraOn => _cameraOn;
  bool get hasPeer => _remoteUid != null;
  String? get error => _error;
  Duration get elapsed => _elapsed;

  /// The network dropped mid-call and Agora is reconnecting on its own.
  bool get reconnecting => _reconnecting;

  /// `mm:ss`, for the `.call-top` status strip.
  /// mm:ss, rolling over to h:mm:ss past the hour — a long consult used to
  /// read "61:05" rather than "1:01:05".
  String get clock {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    final sec = _elapsed.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Joins the channel.
  ///
  /// A call already up (or on its way up) is left alone, but a session that
  /// *failed* may be retried — both call screens build the session once in
  /// initState, so refusing to re-join after a failure left the user with a
  /// dead screen and no way back short of leaving the booking.
  Future<void> join(CharakCallCredentials creds) async {
    if (_stage != CharakCallStage.idle && _stage != CharakCallStage.failed) {
      return;
    }
    _error = null;
    _creds = creds;
    _remoteUid = null;
    _localReady = false;
    _reconnecting = false;
    _set(CharakCallStage.connecting);

    if (creds.isStub) {
      // Nothing to join. Run the clock so the screen behaves like a call.
      _startClock();
      _set(CharakCallStage.waitingForPeer);
      return;
    }

    final granted = await _requestMedia();
    if (!granted) {
      _fail('Camera and microphone access are needed for a video call');
      return;
    }

    try {
      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(
        appId: creds.appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ));
      // Publish the engine before joining, not after. onJoinChannelSuccess
      // fires *during* the joinChannel await and notifies listeners; if
      // _engine were still null then, localView() would return null for that
      // rebuild and nothing would notify again — leaving the self-view blank
      // for the whole call and making an early toggleMic a silent no-op.
      _engine = engine;
      _joinTimer = Timer(joinTimeout, () {
        if (_stage == CharakCallStage.connecting) {
          _fail("Couldn't connect to the call. Check your internet and try again.",
              diagnostic: 'join timed out after ${joinTimeout.inSeconds}s');
        }
      });
      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          _joinTimer?.cancel();
          _localReady = true;
          _startClock();
          _set(_remoteUid == null
              ? CharakCallStage.waitingForPeer
              : CharakCallStage.connected);
        },
        // Agora 6.x reports a bad token, app id or channel here, not through
        // onError: the codes the old handler waited for are deprecated and
        // never arrive, so a call with a bad token hung on "Ringing…" with
        // nothing said. Each reason is turned into words a person can act
        // on, and recorded so a failure on a phone can be looked up later.
        onConnectionStateChanged: (connection, state, reason) {
          debugPrint('[call] connection $state ($reason)');
          if (state == ConnectionStateType.connectionStateReconnecting) {
            _reconnecting = true;
            _notify();
            return;
          }
          if (state == ConnectionStateType.connectionStateConnected && _reconnecting) {
            _reconnecting = false;
            _notify();
          }
          final message = _reasonMessage(reason);
          if (message != null || state == ConnectionStateType.connectionStateFailed) {
            _fail(message ?? "The call couldn't connect. Try again.",
                diagnostic: 'connection $state, $reason');
          }
        },
        onUserJoined: (connection, uid, elapsed) {
          _remoteUid = uid;
          _set(CharakCallStage.connected);
        },
        onUserOffline: (connection, uid, reason) {
          if (_remoteUid != uid) return;
          _remoteUid = null;
          _set(CharakCallStage.waitingForPeer);
        },
        onError: (code, message) {
          // Logged only. Most codes are transient warnings, and the fatal
          // ones also arrive through onConnectionStateChanged above.
          debugPrint('[call] error $code $message');
        },
      ));
      await engine.enableVideo();
      await engine.startPreview();
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await engine.joinChannel(
        token: creds.token,
        channelId: creds.channel,
        uid: creds.uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );
    } catch (e, stack) {
      _fail('Could not start the video call', diagnostic: '$e', stack: stack);
    }
  }

  /// What to tell the person for a connection change that ends the call, or
  /// null for one that doesn't.
  static String? _reasonMessage(ConnectionChangedReasonType reason) {
    switch (reason) {
      case ConnectionChangedReasonType.connectionChangedInvalidToken:
      case ConnectionChangedReasonType.connectionChangedTokenExpired:
        return 'This call link has expired. Start the call again.';
      case ConnectionChangedReasonType.connectionChangedInvalidAppId:
      case ConnectionChangedReasonType.connectionChangedInconsistentAppid:
      case ConnectionChangedReasonType.connectionChangedCertificationVeryfyFailure:
        return "Video calls aren't set up correctly on our side. Please tell Charak support.";
      case ConnectionChangedReasonType.connectionChangedInvalidChannelName:
      case ConnectionChangedReasonType.connectionChangedRejectedByServer:
      case ConnectionChangedReasonType.connectionChangedBannedByServer:
      case ConnectionChangedReasonType.connectionChangedJoinFailed:
        return "The call couldn't connect. Try again.";
      default:
        return null;
    }
  }

  Future<bool> _requestMedia() async {
    final result = await [Permission.camera, Permission.microphone].request();
    return result.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> toggleMic() async {
    _micOn = !_micOn;
    await _engine?.muteLocalAudioStream(!_micOn);
    _notify();
  }

  Future<void> toggleCamera() async {
    _cameraOn = !_cameraOn;
    await _engine?.muteLocalVideoStream(!_cameraOn);
    if (_cameraOn) {
      await _engine?.startPreview();
    } else {
      await _engine?.stopPreview();
    }
    _notify();
  }

  Future<void> switchCamera() => _engine?.switchCamera() ?? Future.value();

  /// Leaves the channel and releases the engine. Idempotent.
  Future<void> leave() async {
    _tick?.cancel();
    _tick = null;
    _joinTimer?.cancel();
    final engine = _engine;
    _engine = null;
    _remoteUid = null;
    if (_stage != CharakCallStage.failed) _stage = CharakCallStage.ended;
    _notify();
    if (engine != null) {
      try {
        await engine.leaveChannel();
        await engine.release();
      } catch (_) {
        // The call is over either way; a failed teardown must not block the
        // screen from popping.
      }
    }
  }

  /// The local camera tile, or null in stub mode / before the engine is up.
  Widget? localView() {
    final engine = _engine;
    if (engine == null || !_localReady || !_cameraOn) return null;
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  /// The peer's stream, or null until they join.
  Widget? remoteView() {
    final engine = _engine;
    final uid = _remoteUid;
    if (engine == null || uid == null) return null;
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: _creds!.channel),
      ),
    );
  }

  void _startClock() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      _notify();
    });
  }

  /// Ends the attempt: the engine is released (Agora's engine is a single
  /// instance, so a retry cannot start while this one lives), the clock
  /// stops, and the reason is recorded for later diagnosis.
  void _fail(String message, {String? diagnostic, StackTrace? stack}) {
    if (_stage == CharakCallStage.failed || _stage == CharakCallStage.ended) return;
    debugPrint('[call] failed: $message${diagnostic == null ? '' : ' ($diagnostic)'}');
    CharakCrash.recordError(
      Exception('Video call failed: ${diagnostic ?? message}'),
      stack,
      reason: 'call on ${_creds?.channel ?? 'unknown channel'}',
    );
    _joinTimer?.cancel();
    _tick?.cancel();
    _tick = null;
    _remoteUid = null;
    _localReady = false;
    _reconnecting = false;
    _error = message;
    _set(CharakCallStage.failed);
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      engine.leaveChannel().catchError((_) {}).then((_) => engine.release()).catchError((_) {});
    }
  }

  void _set(CharakCallStage stage) {
    _stage = stage;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _joinTimer?.cancel();
    // Fire-and-forget: dispose cannot await, but the engine must still go.
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      engine.leaveChannel().then((_) => engine.release()).catchError((_) {});
    }
    super.dispose();
  }
}

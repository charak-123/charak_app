import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class VideoCallScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const VideoCallScreen({super.key, required this.bookingId});
  @override
  ConsumerState<VideoCallScreen> createState() => _State();
}

class _State extends ConsumerState<VideoCallScreen> {
  bool _loading = true;
  bool _joined = false;
  String? _peerName;
  String? _joinError;

  // The patient is always uid 1001 — the doctor holds uid 0 on the channel.
  static const _patientUid = 1001;

  final _call = CharakCallSession();

  @override
  void initState() {
    super.initState();
    _call.addListener(_onCallChanged);
    _initCall();
  }

  @override
  void dispose() {
    _call.removeListener(_onCallChanged);
    _call.dispose();
    super.dispose();
  }

  void _onCallChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initCall() async {
    try {
      final res = await ApiClient.instance.post(
        '/bookings/${widget.bookingId}/call',
        {'uid': _patientUid},
      ) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _peerName = res['doctor_name'] as String?;
        _loading = false;
        _joined = true;
      });
      await _call.join(
        CharakCallCredentials.fromJson(res, uid: _patientUid),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _joinError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _joinError = 'Could not join the call';
        });
      }
    }
  }

  Future<void> _endCall() async {
    await _call.leave();
    if (mounted) context.pop();
  }

  /// True once the call is really up. `_joined` only means the token request
  /// came back, which is not the same thing.
  bool get _connected =>
      _joined &&
      _joinError == null &&
      (_call.stage == CharakCallStage.waitingForPeer ||
          _call.stage == CharakCallStage.connected);

  /// Says what is actually happening — including when Agora has no
  /// credentials in this environment, rather than sitting on "Connecting…".
  String get _subtitle {
    if (_joinError != null) return _joinError!;
    if (_call.stage == CharakCallStage.failed) {
      return _call.error ?? 'Call could not be started';
    }
    if (!_joined) return 'Connecting…';
    if (_call.isStub) return 'Dev stub · Agora not configured';
    switch (_call.stage) {
      case CharakCallStage.connected:
        return 'Video consult · connected';
      case CharakCallStage.waitingForPeer:
        return 'Waiting for the doctor to join…';
      case CharakCallStage.ended:
        return 'Call ended';
      default:
        return 'Connecting…';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: CharakCallColors.field,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return CharakCallScaffold(
      peerName: _peerName ?? 'Doctor',
      peerSubtitle: _subtitle,
      statusText: _connected ? _call.clock : 'Connecting…',
      // join() reports failure by moving to CharakCallStage.failed rather than
      // throwing, so _joinError stays null on an Agora failure. Gating on the
      // session's own stage is what keeps the recording dot and the running
      // clock off a call that never connected.
      recording: _connected,
      showSelfView: _call.cameraOn,
      peerVideo: _call.remoteView(),
      selfVideo: _call.localView(),
      controls: [
        CharakCallButton(
          icon: _call.micOn ? Icons.mic : Icons.mic_off,
          active: !_call.micOn,
          semanticLabel: _call.micOn ? 'Mute microphone' : 'Unmute microphone',
          onPressed: _call.toggleMic,
        ),
        CharakCallButton(
          icon: _call.cameraOn ? Icons.videocam : Icons.videocam_off,
          active: !_call.cameraOn,
          semanticLabel:
              _call.cameraOn ? 'Turn camera off' : 'Turn camera on',
          onPressed: _call.toggleCamera,
        ),
        CharakCallButton(
          icon: Icons.call_end,
          end: true,
          semanticLabel: 'End call',
          onPressed: _endCall,
        ),
      ],
    );
  }
}

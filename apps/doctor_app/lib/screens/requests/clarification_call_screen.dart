import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class ClarificationCallScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const ClarificationCallScreen({super.key, required this.bookingId});
  @override
  ConsumerState<ClarificationCallScreen> createState() => _State();
}

class _State extends ConsumerState<ClarificationCallScreen> {
  String? _callId;
  String _peerName = 'Patient';
  bool _callActive = false;
  bool _loading = false;
  final _notesController = TextEditingController();
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
    _notesController.dispose();
    super.dispose();
  }

  void _onCallChanged() {
    if (!mounted) return;
    setState(() {});
    final error = _call.error;
    if (_call.stage == CharakCallStage.failed && error != null) {
      showCharakToast(context, message: error, isError: true);
    }
  }

  Future<void> _initCall() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.post(
        '/bookings/${widget.bookingId}/clarification-call', {},
      ) as Map<String, dynamic>;
      setState(() {
        _callId     = res['id'] as String?;
        _peerName   = res['patient_name'] as String? ?? _peerName;
        _callActive = true;
      });
      // The doctor is uid 0 — the patient joins the same channel as 1001.
      await _call.join(CharakCallCredentials.fromJson(res, uid: 0));
    } on ApiException catch (e) {
      if (mounted) {
        showCharakToast(context, message: e.message, isError: true);
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _endCall({bool missed = false}) async {
    if (_callId == null) return;
    setState(() => _loading = true);
    await _call.leave();
    try {
      final endpoint = missed
          ? '/bookings/${widget.bookingId}/clarification-call/$_callId/missed'
          : '/bookings/${widget.bookingId}/clarification-call/$_callId/complete';
      final notes = _notesController.text.trim();
      await ApiClient.instance.patch(endpoint, missed ? {} : {'notes': notes});
      if (mounted) {
        showCharakToast(context,
            message: missed
                ? 'Marked as missed'
                : (notes.isNotEmpty ? 'Call note saved' : 'Clarification call ended'));
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        showCharakToast(context, message: e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Tells the doctor plainly whether the patient is actually on the line —
  /// and says so out loud when Agora has no credentials in this environment.
  String get _subtitle {
    if (_call.stage == CharakCallStage.failed) {
      return _call.error ?? 'Call could not be started';
    }
    if (_call.isStub && _callActive) {
      return 'Dev stub · Agora not configured';
    }
    switch (_call.stage) {
      case CharakCallStage.connected:
        return 'Clarification call · connected';
      case CharakCallStage.waitingForPeer:
        return 'Ringing the patient…';
      case CharakCallStage.ended:
        return 'Call ended';
      default:
        return 'Clarification call · before you decide';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_callActive) {
      return const Scaffold(
        backgroundColor: CharakCallColors.field,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Stack(
      children: [
        CharakCallScaffold(
          peerName: _peerName,
          peerSubtitle: _subtitle,
          // `.call-top` — recording dot beside the call's label.
          statusText: _callActive ? _call.clock : 'Connecting…',
          recording: _callActive && _call.stage != CharakCallStage.failed,
          showSelfView: _call.cameraOn,
          peerVideo: _call.remoteView(),
          selfVideo: _call.localView(),
          // `.call-notes` — translucent blurred field kept for this booking.
          notes: TextField(
            controller: _notesController,
            style: CharakText.caption.copyWith(fontSize: 13, color: Colors.white),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'Equipment needed, prep notes… (kept for this booking)',
              hintStyle: CharakText.caption.copyWith(
                fontSize: 13,
                color: CharakCallColors.notesHint,
              ),
            ),
          ),
          controls: [
            CharakCallButton(
              icon: _call.micOn ? Icons.mic : Icons.mic_off,
              active: !_call.micOn,
              semanticLabel: _call.micOn ? 'Mute' : 'Unmute',
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
              onPressed: _loading ? null : () => _endCall(),
            ),
          ],
        ),
        // Ops escape hatch: close the call out as unanswered. Sits clear of
        // the centred `.call-top` strip.
        Positioned(
          right: 6,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: TextButton(
              onPressed: _loading ? null : () => _endCall(missed: true),
              child: Text(
                'Mark missed',
                style: CharakText.caption.copyWith(
                  color: CharakCallColors.peerSub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

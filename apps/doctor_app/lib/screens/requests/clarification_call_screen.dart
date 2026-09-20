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
  // Retained for the pending Agora SDK wiring below.
  // ignore: unused_field
  String? _agoraChannel;
  String _peerName = 'Patient';
  bool _callActive = false;
  bool _loading = false;
  bool _muted = false;
  bool _cameraOff = false;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _initCall() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.post(
        '/bookings/${widget.bookingId}/clarification-call', {},
      ) as Map<String, dynamic>;
      setState(() {
        _callId       = res['id'] as String?;
        _agoraChannel = res['agora_channel'] as String?;
        _peerName     = res['patient_name'] as String? ?? _peerName;
        _callActive   = true;
      });
      // TODO: initialize Agora SDK with the returned token + _agoraChannel
      // AgoraRtcEngine.joinChannel(token, _agoraChannel, null, 0);
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
          peerSubtitle: 'Clarification call · before you decide',
          // `.call-top` — recording dot beside the call's label.
          statusText: _callActive ? 'Clarification call' : 'Connecting…',
          recording: _callActive,
          showSelfView: !_cameraOff,
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
                color: const Color(0x80FFFFFF),
              ),
            ),
          ),
          controls: [
            CharakCallButton(
              icon: _muted ? Icons.mic_off : Icons.mic,
              active: _muted,
              semanticLabel: _muted ? 'Unmute' : 'Mute',
              onPressed: () => setState(() => _muted = !_muted),
            ),
            CharakCallButton(
              icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
              active: _cameraOff,
              semanticLabel: _cameraOff ? 'Turn camera on' : 'Turn camera off',
              onPressed: () => setState(() => _cameraOff = !_cameraOff),
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

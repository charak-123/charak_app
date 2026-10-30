import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

/// The doctor's side of a call. Two kinds: a clarification call before the
/// doctor decides on a request (it rings the patient), and, with
/// [consultation], the scheduled video consultation itself, which both sides
/// simply join (POST /bookings/{id}/call). The doctor joining a paid consult
/// starts the consultation on the server.
class ClarificationCallScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final bool consultation;
  const ClarificationCallScreen({super.key, required this.bookingId, this.consultation = false});
  @override
  ConsumerState<ClarificationCallScreen> createState() => _State();
}

class _State extends ConsumerState<ClarificationCallScreen> {
  /// How long the patient's phone rings (backend calls.RING_SECONDS). Past
  /// it the doctor is offered "Ring again" rather than waiting on nothing.
  static const _ringFor = Duration(seconds: 60);

  String? _callId;
  String _peerName = 'Patient';
  bool _callActive = false;
  bool _loading = false;
  bool _ringedOut = false;
  bool _declined = false;
  final _notesController = TextEditingController();
  final _call = CharakCallSession();
  CharakCallStage? _lastStage;
  Timer? _ringTimer;
  CharakPoller? _statusPoll;
  StreamSubscription<CharakPushMessage>? _pushSub;

  @override
  void initState() {
    super.initState();
    _call.addListener(_onCallChanged);
    // The patient declining arrives as a push; the status poll below is the
    // fallback when push is off.
    _pushSub = CharakPush.instance.messages.listen((m) {
      if (m.event == 'call.declined' && m.bookingId == widget.bookingId) _onDeclined();
    });
    _initCall();
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    _statusPoll?.dispose();
    _pushSub?.cancel();
    _call.removeListener(_onCallChanged);
    _call.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onCallChanged() {
    if (!mounted) return;
    setState(() {});
    final stage = _call.stage;
    final error = _call.error;
    if (stage == CharakCallStage.failed && _lastStage != stage && error != null) {
      showCharakToast(context, message: error, isError: true);
    }
    if (stage == CharakCallStage.connected) {
      _ringTimer?.cancel();
      _statusPoll?.stop();
      _ringedOut = false;
    }
    _lastStage = stage;
  }

  /// Rings for [_ringFor], watching for the patient to decline meanwhile.
  void _startRinging() {
    if (widget.consultation) return;
    _ringedOut = false;
    _ringTimer?.cancel();
    _ringTimer = Timer(_ringFor, () {
      if (mounted && !_call.hasPeer) setState(() => _ringedOut = true);
    });
    _statusPoll?.dispose();
    final callId = _callId;
    if (callId == null) return;
    _statusPoll = CharakPoller(
      interval: const Duration(seconds: 4),
      maxInterval: const Duration(seconds: 8),
      onPoll: () async {
        if (!mounted || _call.hasPeer) return true;
        final row = await ApiClient.instance
            .get('/bookings/${widget.bookingId}/clarification-call/$callId') as Map<String, dynamic>;
        if (row['call_status'] != 'initiated') {
          _onDeclined();
          return true;
        }
        return false;
      },
    )..start();
  }

  void _onDeclined() {
    if (!mounted || _declined || _call.hasPeer) return;
    _ringTimer?.cancel();
    _statusPoll?.stop();
    setState(() {
      _declined = true;
      _ringedOut = true;
    });
    showCharakToast(context, message: "The patient can't talk right now. Try again in a little while.");
  }

  Future<void> _initCall() async {
    setState(() {
      _loading = true;
      _declined = false;
    });
    try {
      final res = await ApiClient.instance.post(
        widget.consultation
            ? '/bookings/${widget.bookingId}/call'
            : '/bookings/${widget.bookingId}/clarification-call',
        {},
      ) as Map<String, dynamic>;
      // Left while the request was out: don't open a camera nobody sees.
      if (!mounted) return;
      setState(() {
        _callId     = widget.consultation ? null : res['id'] as String?;
        _peerName   = res['patient_name'] as String? ?? _peerName;
        _callActive = true;
      });
      // The doctor is uid 0 — the patient joins the same channel as 1001.
      if (!_call.hasPeer) await _call.join(CharakCallCredentials.fromJson(res, uid: 0));
      _startRinging();
    } on ApiException catch (e) {
      if (mounted) {
        showCharakToast(context, message: e.message, isError: true);
        if (!_callActive) context.pop();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _endCall({bool missed = false}) async {
    _ringTimer?.cancel();
    _statusPoll?.stop();
    if (widget.consultation) {
      // Leaving the consultation call ends nothing on the server: the doctor
      // can rejoin, and the consultation ends when the prescription is sent.
      await _call.leave();
      if (mounted) context.pop();
      return;
    }
    if (_callId == null) {
      // Nothing was opened on the server: just leave.
      await _call.leave();
      if (mounted) context.pop();
      return;
    }
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
    if (_call.reconnecting) return 'Reconnecting…';
    if (_declined) return "Declined · the patient can't talk right now";
    switch (_call.stage) {
      case CharakCallStage.connected:
        return widget.consultation ? 'Consultation · connected' : 'Clarification call · connected';
      case CharakCallStage.waitingForPeer:
        if (widget.consultation) return 'Waiting for the patient to join…';
        return _ringedOut ? 'No answer yet' : 'Ringing the patient…';
      case CharakCallStage.ended:
        return 'Call ended';
      default:
        return widget.consultation ? 'Video consultation' : 'Clarification call · before you decide';
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

    final failed = _call.stage == CharakCallStage.failed;
    // Back ends the call properly. Leaving with the gesture used to keep the
    // call open on the server, and every later "Call patient" was refused.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_callActive) {
          context.pop();
        } else if (!_loading) {
          _endCall();
        }
      },
      child: Stack(
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
              icon: _call.micOn ? LucideIcons.mic : LucideIcons.micOff,
              active: !_call.micOn,
              semanticLabel: _call.micOn ? 'Mute' : 'Unmute',
              onPressed: _call.toggleMic,
            ),
            CharakCallButton(
              icon: _call.cameraOn ? LucideIcons.video : LucideIcons.videoOff,
              active: !_call.cameraOn,
              semanticLabel:
                  _call.cameraOn ? 'Turn camera off' : 'Turn camera on',
              onPressed: _call.toggleCamera,
            ),
            CharakCallButton(
              icon: LucideIcons.phoneOff,
              end: true,
              semanticLabel: 'End call',
              onPressed: _loading ? null : () => _endCall(),
            ),
          ],
        ),
        // Nobody picked up, the patient declined, or the line failed: one
        // clear next step above the controls instead of a dead screen.
        if (_callActive && (failed || (_ringedOut && !_call.hasPeer)))
          Positioned(
            left: 40,
            right: 40,
            bottom: 150,
            child: SafeArea(
              top: false,
              child: CharakButton(
                label: failed ? 'Try again' : (widget.consultation ? 'Rejoin' : 'Ring again'),
                icon: failed ? LucideIcons.rotateCcw : LucideIcons.phoneCall,
                isLoading: _loading,
                onPressed: _loading ? null : _initCall,
              ),
            ),
          ),
        // Ops escape hatch: close the call out as unanswered. Sits clear of
        // the centred `.call-top` strip. Not for the consultation, which
        // nobody rings.
        if (!widget.consultation) Positioned(
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
      ),
    );
  }
}

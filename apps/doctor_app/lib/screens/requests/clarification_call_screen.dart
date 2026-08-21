import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

class ClarificationCallScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const ClarificationCallScreen({super.key, required this.bookingId});
  @override
  ConsumerState<ClarificationCallScreen> createState() => _State();
}

class _State extends ConsumerState<ClarificationCallScreen> {
  String? _callId;
  String? _agoraToken;
  String? _agoraChannel;
  bool _callActive = false;
  bool _loading = false;
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
        _agoraToken   = res['agora_token'] as String?;
        _agoraChannel = res['agora_channel'] as String?;
        _callActive   = true;
      });
      // TODO: initialize Agora SDK with _agoraToken + _agoraChannel
      // AgoraRtcEngine.joinChannel(_agoraToken, _agoraChannel, null, 0);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
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
      await ApiClient.instance.patch(
        endpoint,
        missed ? {} : {'notes': _notesController.text.trim()},
      );
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_callActive) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Clarification Call'),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => _endCall(missed: true),
            child: const Text('Mark Missed', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: Column(children: [
        // Video placeholder (Agora SDK renders here when integrated)
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(CharakSpacing.base),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.all(CharakRadius.card),
            ),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.video_call, size: 64, color: Colors.white38),
                const SizedBox(height: 12),
                Text(
                  _callActive
                      ? 'Call in progress\n(Agora SDK — wire in Day 49)'
                      : 'Connecting...',
                  style: const TextStyle(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
                if (_agoraChannel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Channel: $_agoraChannel',
                      style: const TextStyle(color: Colors.white24, fontSize: 11),
                    ),
                  ),
              ]),
            ),
          ),
        ),

        // Notes + end call
        Container(
          color: const Color(0xFF1A1A2E),
          padding: const EdgeInsets.fromLTRB(
              CharakSpacing.base, 0, CharakSpacing.base, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _notesController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Notes from the call...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0D0D1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(CharakRadius.button),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : () => _endCall(),
              style: ElevatedButton.styleFrom(
                backgroundColor: CharakColors.danger,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(CharakRadius.button)),
              ),
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('End Call & Save Notes'),
            ),
          ]),
        ),
      ]),
    );
  }
}

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
  bool _micOn = true;
  bool _camOn = true;
  bool _loading = true;
  String? _token;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    try {
      final res = await ApiClient.instance.post(
        '/bookings/${widget.bookingId}/call',
        {'uid': 1001},
      );
      setState(() {
        _token = res['token'] as String?;
        _loading = false;
      });
      // In production: initialize Agora engine with _token and join channel
      // await _agoraEngine.joinChannel(token: _token!, channelId: widget.bookingId, uid: 1001)
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _endCall() async {
    // In production: leave Agora channel before navigating
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF1A1A2E),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(children: [
              // Remote video placeholder
              Container(
                width: double.infinity,
                height: double.infinity,
                color: const Color(0xFF16213E),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const CircleAvatar(
                    radius: 48,
                    backgroundColor: Color(0xFF2F6FED),
                    child: Icon(Icons.person, size: 48, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _token != null && _token!.startsWith('stub')
                        ? 'Dev stub — Agora not configured'
                        : 'Connecting…',
                    style: CharakText.body.copyWith(color: Colors.white70),
                  ),
                ]),
              ),

              // Local video thumbnail (top-right)
              Positioned(
                top: 16, right: 16,
                child: Container(
                  width: 90, height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F3460),
                    borderRadius: const BorderRadius.all(CharakRadius.card),
                  ),
                  child: _camOn
                      ? const Icon(Icons.videocam, color: Colors.white54, size: 32)
                      : const Icon(Icons.videocam_off, color: Colors.white38, size: 32),
                ),
              ),

              // Controls bar
              Positioned(
                bottom: 32, left: 0, right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _ControlBtn(
                    icon: _micOn ? Icons.mic : Icons.mic_off,
                    active: _micOn,
                    onTap: () => setState(() => _micOn = !_micOn),
                  ),
                  const SizedBox(width: 16),
                  // End call
                  GestureDetector(
                    onTap: _endCall,
                    child: Container(
                      width: 64, height: 64,
                      decoration: const BoxDecoration(
                        color: CharakColors.danger, shape: BoxShape.circle),
                      child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _ControlBtn(
                    icon: _camOn ? Icons.videocam : Icons.videocam_off,
                    active: _camOn,
                    onTap: () => setState(() => _camOn = !_camOn),
                  ),
                ]),
              ),
            ]),
    ),
  );
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ControlBtn({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF2F2F4E) : Colors.white24,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    ),
  );
}

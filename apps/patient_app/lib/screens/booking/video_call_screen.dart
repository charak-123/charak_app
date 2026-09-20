import 'dart:async';
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
  String? _peerName;

  // `.call-top` timer — counts from the moment the channel is joined.
  Timer? _tick;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _initCall() async {
    try {
      final res = await ApiClient.instance.post(
        '/bookings/${widget.bookingId}/call',
        {'uid': 1001},
      );
      if (!mounted) return;
      setState(() {
        _token = res['token'] as String?;
        _peerName = res['doctor_name'] as String?;
        _loading = false;
      });
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed++);
      });
      // In production: initialize Agora engine with _token and join channel
      // await _agoraEngine.joinChannel(token: _token!, channelId: widget.bookingId, uid: 1001)
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _endCall() async {
    // In production: leave Agora channel before navigating
    _tick?.cancel();
    if (mounted) context.pop();
  }

  String get _clock =>
      '${(_elapsed ~/ 60).toString().padLeft(2, '0')}:'
      '${(_elapsed % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: CharakCallColors.field,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final connected = _token != null;
    return CharakCallScaffold(
      peerName: _peerName ?? 'Doctor',
      peerSubtitle: connected
          ? (_token!.startsWith('stub')
              ? 'Dev stub · Agora not configured'
              : 'Video consult · connected')
          : 'Connecting…',
      statusText: _clock,
      recording: connected,
      showSelfView: _camOn,
      controls: [
        CharakCallButton(
          icon: _micOn ? Icons.mic : Icons.mic_off,
          active: !_micOn,
          semanticLabel: _micOn ? 'Mute microphone' : 'Unmute microphone',
          onPressed: () => setState(() => _micOn = !_micOn),
        ),
        CharakCallButton(
          icon: _camOn ? Icons.videocam : Icons.videocam_off,
          active: !_camOn,
          semanticLabel: _camOn ? 'Turn camera off' : 'Turn camera on',
          onPressed: () => setState(() => _camOn = !_camOn),
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

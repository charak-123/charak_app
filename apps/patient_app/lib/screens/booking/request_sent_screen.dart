import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:charak_core/charak_core.dart';

class RequestSentScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const RequestSentScreen({super.key, required this.bookingId});
  @override
  ConsumerState<RequestSentScreen> createState() => _State();
}

class _State extends ConsumerState<RequestSentScreen> {
  StreamSubscription? _sub;
  String _status = 'requested';

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _sub = Supabase.instance.client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', widget.bookingId)
        .listen((rows) {
      if (rows.isEmpty || !mounted) return;
      final newStatus = rows.first['status'] as String? ?? 'requested';
      if (newStatus != _status) {
        setState(() => _status = newStatus);
        if (newStatus == 'accepted') {
          context.go('/booking/${widget.bookingId}/pay');
        } else if (newStatus == 'declined') {
          context.go('/booking/${widget.bookingId}/status');
        }
      }
    });
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.bg,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(CharakSpacing.lg),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Spacer(),
          _PulsingIcon(),
          const SizedBox(height: 24),
          Text('Request Sent!', style: CharakText.display),
          const SizedBox(height: 8),
          Text(
            'Waiting for the doctor to accept.\nYou\'ll be notified as soon as they respond.',
            style: CharakText.body.copyWith(color: CharakColors.inkMuted),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Go to Home'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.push('/booking/${widget.bookingId}/status'),
            child: const Text('View Booking'),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    ),
  );
}

class _PulsingIcon extends StatefulWidget {
  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: const Duration(seconds: 1),
  )..repeat(reverse: true);
  late final Animation<double> _scale = Tween(begin: 0.95, end: 1.05)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: Container(
      width: 88, height: 88,
      decoration: BoxDecoration(color: CharakColors.primarySoft, shape: BoxShape.circle),
      child: const Icon(Icons.hourglass_top, color: CharakColors.primary, size: 40),
    ),
  );
}

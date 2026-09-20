import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
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
  Map<String, dynamic>? _booking;

  @override
  void initState() {
    super.initState();
    _loadBooking();
    _subscribeRealtime();
  }

  Future<void> _loadBooking() async {
    try {
      final rows = await Supabase.instance.client
          .from('bookings')
          .select('*, doctors(name, categories(name), doctor_pricing(channel, price))')
          .eq('id', widget.bookingId)
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        setState(() => _booking = rows.first);
      }
    } catch (_) {}
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
  Widget build(BuildContext context) {
    final booking = _booking;
    final docName = (booking?['doctors'] as Map?)?['name'] as String? ?? 'the doctor';
    final channel = booking?['channel'] as String? ?? '';
    final channelLabel = channel == 'home_visit' ? 'Home Visit' : 'Online Consult';
    final start = booking?['scheduled_start'] as String?;
    String formattedTime = '';
    if (start != null) {
      final dt = DateTime.tryParse(start);
      if (dt != null) formattedTime = DateFormat('d MMM yyyy, h:mm a').format(dt.toLocal());
    }
    final pricing = List<Map<String,dynamic>>.from(
        (booking?['doctors'] as Map?)?['doctor_pricing'] as List? ?? []);
    final priceRow = pricing.where((p) => p['channel'] == channel).firstOrNull;
    final priceStr = priceRow != null
        ? '₹${(priceRow['price'] as num).toStringAsFixed(0)}'
        : null;

    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Padding(
                // `.wait-state` — 48px of air above the badge.
                padding: const EdgeInsets.fromLTRB(4, 48, 4, 0),
                child: Column(children: [
                  // `.wait-state .wait-ic` — 88px amber circle, 40px glyph.
                  const _PulsingIcon(),
                  const SizedBox(height: 22),

                  const CharakStatusPill(
                    label: 'Pending doctor review',
                    tone: CharakStatusTone.warning,
                    pulsingDot: true,
                  ),
                  const SizedBox(height: 18),

                  const Text('Request sent',
                      style: charakScreenTitleStyle, textAlign: TextAlign.center),
                  const SizedBox(height: 5),
                  Text(
                    'Dr. $docName will review your request. You\'ll be notified '
                    'the moment they decide — usually within minutes.',
                    style: charakScreenSubStyle,
                    textAlign: TextAlign.center,
                  ),

                  // `.bsum` — the summary block sits 26px below the copy.
                  if (booking != null) ...[
                    const SizedBox(height: 26),
                    CharakSummaryCard(rows: [
                      if (formattedTime.isNotEmpty)
                        CharakSummaryRow(label: 'When', value: formattedTime),
                      CharakSummaryRow(label: 'Channel', value: channelLabel),
                      const CharakSummaryDivider(),
                      if (priceStr != null)
                        CharakSummaryRow(label: 'Price', value: priceStr, tabular: true),
                    ]),
                  ],

                  const SizedBox(height: 10),
                  const Text(
                    'This is not a confirmed appointment yet — you can close '
                    'the app and we\'ll notify you.',
                    style: charakHintStyle,
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ),
          ),

          CharakCtaBar(children: [
            Expanded(
              child: CharakButton(
                label: 'Go to Home',
                outlined: true,
                onPressed: () => context.go('/home'),
              ),
            ),
            Expanded(
              child: CharakButton(
                label: 'Booking details',
                onPressed: () => context.push('/booking/${widget.bookingId}/status'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// `.wait-state .wait-ic` — the amber badge breathes so a long wait still
/// reads as "in progress" rather than stuck.
class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon();
  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  late final Animation<double> _scale = Tween(begin: 0.95, end: 1.05)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final (bg, _) = charakToneColors(CharakStatusTone.warning);
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 88, height: 88,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(Icons.send_rounded, color: CharakColors.warning, size: 40),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:charak_core/charak_core.dart';

class RequestSentScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const RequestSentScreen({super.key, required this.bookingId});
  @override
  ConsumerState<RequestSentScreen> createState() => _State();
}

class _State extends ConsumerState<RequestSentScreen> {
  CharakPoller? _poll;
  Map<String, dynamic>? _booking;

  @override
  void initState() {
    super.initState();
    _loadBooking();
    // A doctor may take minutes or hours to accept, and the `booking.accepted`
    // push is the real signal — so this starts at 5s and eases off to two
    // minutes rather than asking 720 times an hour, and sleeps entirely while
    // the app is backgrounded.
    _poll = CharakPoller(onPoll: _loadBooking)..start();
  }

  /// Polls the backend rather than reading Supabase directly.
  ///
  /// These apps carry only the anon key and authenticate with a FastAPI JWT,
  /// so `auth.uid()` is NULL and the bookings RLS policies in migration 0004
  /// (`patient_id = auth.uid()`) match nothing. The direct select returned no
  /// rows and the realtime stream never fired, so this screen sat on its
  /// placeholder copy and never advanced when the doctor accepted.
  /// Returns true once the booking has left `requested`, which stops the poll.
  /// A thrown request is caught by the poller and simply backs off — a dropped
  /// poll is not a decision.
  Future<bool> _loadBooking() async {
    final b = await ApiClient.instance.get('/bookings/${widget.bookingId}')
        as Map<String, dynamic>;
    if (!mounted) return true;

    setState(() => _booking = b);

    switch (b['status'] as String? ?? 'requested') {
      case 'accepted':
        context.go('/booking/${widget.bookingId}/pay');
        return true;
      case 'declined':
        context.go('/booking/${widget.bookingId}/status');
        return true;
      default:
        return false;
    }
  }

  @override
  void dispose() { _poll?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    final docName = CharakFormat.doctor((booking?['doctors'] as Map?)?['name'] as String?, fallback: 'the doctor');
    final channel = booking?['channel'] as String? ?? '';
    final channelLabel = CharakFormat.channel(channel);
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
        ? CharakFormat.rupees(priceRow['price'] as num)
        : null;

    return Scaffold(
      backgroundColor: CharakColors.ground,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 44, 20, 24),
              // Same outcome layout and Chandan "Requested" moment as the
              // booking status screen's awaiting-response state.
              child: CharakOutcomeState(
                tone: CharakOutcomeTone.waiting,
                icon: LucideIcons.send,
                title: 'Request sent',
                message: '$docName will review your request. You\'ll be notified '
                    'the moment they decide — usually within minutes.',
                child: Column(children: [
                  CharakStatusPill.forStatus('requested'),
                  if (booking != null) ...[
                    const SizedBox(height: 20),
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
                  Text(
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

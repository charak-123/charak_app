import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

final _activeBookingProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/bookings/$id');
  return res as Map<String, dynamic>;
});

class ActiveBookingScreen extends ConsumerWidget {
  final String bookingId;
  const ActiveBookingScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_activeBookingProvider(bookingId));
    final docName = async.maybeWhen(
      data: (b) => (b['doctors'] as Map?)?['name'] as String?,
      orElse: () => null,
    );
    return Scaffold(
      backgroundColor: CharakColors.bg,
      appBar: CharakTopBar(
          title: docName != null ? 'Dr. $docName' : 'Booking'),
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (booking) => _Body(booking: booking, bookingId: bookingId),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String bookingId;
  const _Body({required this.booking, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    final status  = booking['status'] as String? ?? '';
    final channel = booking['channel'] as String? ?? '';
    final doc     = booking['doctors'] as Map<String, dynamic>? ?? {};
    final docName = doc['name'] as String? ?? 'Doctor';
    final start   = booking['scheduled_start'] as String?;
    final address = booking['address'] as String?;
    final price   = (booking['price_confirmed'] as num?)?.toDouble();

    final isOnline = channel != 'home_visit';
    final channelLabel = isOnline ? 'Online Consult' : 'Home Visit';

    final startDt = start != null ? DateTime.tryParse(start)?.toLocal() : null;
    final when = startDt != null
        ? DateFormat('EEE d MMM, h:mm a').format(startDt)
        : '';

    // `.act-timer` — a live countdown before the slot, the slot time after.
    final remaining = startDt?.difference(DateTime.now());
    final countdown = (remaining != null && !remaining.isNegative)
        ? '${remaining.inHours > 0 ? '${remaining.inHours}:' : ''}'
            '${(remaining.inMinutes % 60).toString().padLeft(2, '0')}:'
            '${(remaining.inSeconds % 60).toString().padLeft(2, '0')}'
        : null;

    final canJoin = status == 'paid' && isOnline;

    return Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          // ── `.act-card` — doctor + timer ─────────────────────────────
          _ActCard(child: Column(children: [
            Row(children: [
              CharakAvatar(name: docName, radius: 24),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dr. $docName', style: CharakText.h2.copyWith(fontSize: 16)),
                const SizedBox(height: 1),
                Text(when.isNotEmpty ? '$channelLabel · $when' : channelLabel,
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ])),
              const SizedBox(width: 8),
              CharakStatusPill.forStatus(status),
            ]),
            const SizedBox(height: 14),
            if (isOnline)
              CharakInfoStrip(
                label: countdown != null ? 'Consult starts in' : 'Consult time',
                value: countdown ??
                    (startDt != null ? DateFormat('h:mm a').format(startDt) : '—'),
                tabularValue: countdown != null,
              )
            else
              CharakInfoStrip(
                label: "Doctor's ETA",
                value: startDt != null
                    ? '~ ${DateFormat('h:mm a').format(startDt)}'
                    : '—',
              ),
          ])),
          const SizedBox(height: 12),

          // ── `.act-card` — detail rows ────────────────────────────────
          _ActCard(child: Column(children: [
            if (isOnline) ...[
              const _ActRow(
                  icon: Icons.videocam_outlined,
                  label: 'Video call',
                  value: 'Join from this screen',
                  muted: true),
              const _ActRow(
                  icon: Icons.chat_bubble_outline,
                  label: 'Contact through app',
                  value: 'Tap to chat',
                  muted: true),
              _ActRow(
                icon: Icons.receipt_long_outlined,
                label: 'Paid via UPI',
                value: price != null ? '₹${price.toStringAsFixed(0)}' : '—',
                tabular: true,
                last: true,
              ),
            ] else ...[
              _ActRow(
                  icon: Icons.location_on_outlined,
                  label: 'Address',
                  value: (address != null && address.isNotEmpty) ? address : '—'),
              const _ActRow(
                  icon: Icons.navigation_outlined,
                  label: 'Doctor en route',
                  value: 'Tracking on the day',
                  muted: true),
              const _ActRow(
                  icon: Icons.chat_bubble_outline,
                  label: 'Contact through app',
                  value: 'Tap to chat',
                  muted: true),
              _ActRow(
                icon: Icons.receipt_long_outlined,
                label: 'Paid via UPI',
                value: price != null ? '₹${price.toStringAsFixed(0)}' : '—',
                tabular: true,
                last: true,
              ),
            ],
          ])),

          if (canJoin) ...[
            const SizedBox(height: 6),
            CharakButton(
              label: 'Join call',
              icon: Icons.videocam_rounded,
              onPressed: () => context.push('/booking/$bookingId/call'),
            ),
            const SizedBox(height: 10),
            const Text('Join opens 5 minutes before the slot.',
                style: charakHintStyle, textAlign: TextAlign.center),
          ],

          if (status == 'completed') ...[
            const SizedBox(height: 12),
            const CharakNoteBanner(
              icon: Icons.check_circle_outline,
              tone: CharakStatusTone.success,
              message: 'Visit completed. Your receipt is in History.',
            ),
          ],
        ],
      )),

      // ── `.cta-bar` ─────────────────────────────────────────────────
      CharakCtaBar(children: [
        if (status == 'completed') ...[
          Expanded(
            child: CharakButton(
              label: 'View bill',
              outlined: true,
              onPressed: () => context.push('/booking/$bookingId/bill'),
            ),
          ),
          Expanded(
            child: CharakButton(
              label: 'Rate your visit',
              onPressed: () => context.push('/booking/$bookingId/rate'),
            ),
          ),
        ] else ...[
          Expanded(
            child: CharakButton(
              label: "I'm running late",
              outlined: true,
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Doctor notified')),
              ),
            ),
          ),
          Expanded(
            child: CharakButton(
              label: 'Cancel',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cancellation under review')),
              ),
            ),
          ),
        ],
      ]),
    ]);
  }
}

/// `.act-card` — plain 16px-padded bordered card.
class _ActCard extends StatelessWidget {
  final Widget child;
  const _ActCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CharakSpacing.base),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      border: Border.all(color: CharakColors.border),
      borderRadius: const BorderRadius.all(CharakRadius.card),
    ),
    child: child,
  );
}

/// `.act-row` — 17px primary glyph, 14px label, value pushed right; the last
/// row drops its rule (`.act-row:last-child { border-bottom: 0 }`).
class _ActRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final bool tabular;
  final bool last;

  const _ActRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
    this.tabular = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: last ? null : const Border(bottom: BorderSide(color: CharakColors.border)),
    ),
    child: Row(children: [
      Icon(icon, size: 17, color: CharakColors.primary),
      const SizedBox(width: 10),
      Text(label,
          style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.ink)),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: CharakText.fontFamily,
            fontSize: 14,
            height: 1.4,
            fontWeight: muted ? FontWeight.w400 : FontWeight.w500,
            color: muted ? CharakColors.inkMuted : CharakColors.ink,
            fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
          ),
        ),
      ),
    ]),
  );
}

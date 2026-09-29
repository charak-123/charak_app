import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _incomingProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/bookings/doctor/incoming');
  return List<Map<String, dynamic>>.from(res as List);
});

// ── RequestsTab ───────────────────────────────────────────────────────────────

class RequestsTab extends ConsumerStatefulWidget {
  const RequestsTab({super.key});
  @override
  ConsumerState<RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends ConsumerState<RequestsTab> {
  CharakPoller? _poll;
  final Set<String> _seen = {};

  /// Requests that landed live in this session — these get the `.req-card.new`
  /// primary ring and the "NEW" tag, and animate in from above.
  final Set<String> _fresh = {};

  /// Requests mid-dismissal, playing `.req-item.leaving` before the refetch.
  final Set<String> _leaving = {};

  /// False until the realtime stream has delivered its first snapshot; rows
  /// in that snapshot were already waiting, so they don't raise a heads-up.
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _pollIncoming();
  }

  /// Polls /bookings/doctor/incoming for requests that have appeared since the
  /// last look, so the new-request highlight and heads-up prompt still work.
  ///
  /// Supabase realtime cannot serve this: the app holds only the anon key and
  /// authenticates with a FastAPI JWT, so `auth.uid()` is NULL and the
  /// bookings RLS policies match nothing — the stream never fired and the tab
  /// only ever updated on a manual pull-to-refresh. Push (`booking.requested`)
  /// remains the immediate signal; this is the safety net.
  void _pollIncoming() {
    // This one never "completes" — a doctor's inbox is open-ended — so it
    // always returns false and simply eases off to a minute while nothing
    // arrives, resetting the moment the doctor brings the app forward.
    _poll = CharakPoller(
      interval: const Duration(seconds: 15),
      maxInterval: const Duration(minutes: 1),
      onPoll: () async {
        if (!mounted) return true;
        final rows = List<Map<String, dynamic>>.from(
            await ApiClient.instance.get('/bookings/doctor/incoming') as List);
        final freshRows =
            rows.where((r) => !_seen.contains(r['id'] as String)).toList();
        final isFirstSync = !_synced;
        _synced = true;
        if (freshRows.isNotEmpty && mounted) {
          for (final r in freshRows) {
            _seen.add(r['id'] as String);
            if (!isFirstSync) _fresh.add(r['id'] as String);
          }
          ref.invalidate(_incomingProvider);
          // Heads-up: a new request drops in from the top (not for the rows
          // already there when polling first starts).
          if (!isFirstSync) _headsUp(freshRows.last);
        }
        return false;
      },
    )..start();
  }

  Future<void> _headsUp(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final channel = row['channel'] == 'home_visit' ? 'Home visit' : 'Online consult';
    final review = await showCharakHeadsUp(
      context,
      overline: 'New request · now',
      message: channel,
    );
    if (review && mounted) context.push('/request/$id');
  }

  Future<void> _decline(String bookingId) async {
    // Declined: the card fades and slides away (motion.exit) before the
    // list refetches.
    setState(() => _leaving.add(bookingId));
    await Future<void>.delayed(CharakMotion.exit);
    if (!mounted) return;
    try {
      await ApiClient.instance.patch('/bookings/$bookingId/decline', {});
      _fresh.remove(bookingId);
      ref.invalidate(_incomingProvider);
      if (mounted) {
        showCharakToast(context, message: 'Request declined — patient notified');
      }
    } on ApiException catch (e) {
      if (mounted) {
        showCharakToast(context, message: e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _leaving.remove(bookingId));
    }
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(_incomingProvider);
    final doctorName = ref.watch(authProvider).user?['name'] as String?;
    final count = incoming.valueOrNull?.length;
    return CharakLargeTitleScaffold(
      eyebrow: doctorName == null ? null : 'Dr. $doctorName',
      title: 'Requests',
      subtitle: count == null
          ? 'New requests arrive live.'
          : count == 0
              ? 'Nothing waiting. New requests arrive live.'
              : '$count waiting for your decision',
      subtitleColor: (count ?? 0) > 0 ? CharakColors.greeting : null,
      onRefresh: () => ref.refresh(_incomingProvider.future),
      children: incoming.when(
        loading: () => const [_RequestCardSkeleton(), _RequestCardSkeleton(), _RequestCardSkeleton()],
        error: (e, _) => [
          CharakEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn\'t load requests',
            message: 'Check your connection and try again.',
            action: CharakButton(
              label: 'Retry',
              variant: CharakButtonVariant.outline,
              onPressed: () => ref.invalidate(_incomingProvider),
            ),
          ),
        ],
        data: (bookings) => bookings.isEmpty
            ? [
                CharakEmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'All caught up',
                  message: 'New booking requests will appear here the moment a patient sends one.',
                  action: CharakButton(
                    label: 'Refresh',
                    variant: CharakButtonVariant.outline,
                    onPressed: () => ref.invalidate(_incomingProvider),
                  ),
                ),
              ]
            : [
                for (final b in bookings)
                  _RequestItem(
                    key: ValueKey(b['id']),
                    leaving: _leaving.contains(b['id']),
                    arrive: _fresh.contains(b['id']),
                    child: CharakStatusPulse(
                      trigger: b['status'],
                      child: _RequestCard(
                        booking: b,
                        isNew: _fresh.contains(b['id']),
                        onDecline: () => _decline(b['id'] as String),
                      ),
                    ),
                  ),
              ],
      ),
    );
  }
}

/// Wraps a request card in its two list motions: a live arrival slides down
/// into the list (motion.emphasized, 450ms) and a declined card fades,
/// slides and collapses (motion.exit, 200ms).
class _RequestItem extends StatefulWidget {
  final Widget child;
  final bool leaving;
  final bool arrive;
  const _RequestItem({super.key, required this.child, required this.leaving, required this.arrive});

  @override
  State<_RequestItem> createState() => _RequestItemState();
}

class _RequestItemState extends State<_RequestItem> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: CharakDurations.newRequest,
    value: widget.arrive ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.arrive) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: CharakMotion.exit,
      curve: CharakCurves.exit,
      offset: widget.leaving ? const Offset(0.18, 0) : Offset.zero,
      child: AnimatedOpacity(
        duration: CharakMotion.exit,
        opacity: widget.leaving ? 0 : 1,
        child: AnimatedSize(
          duration: CharakMotion.exit,
          curve: CharakCurves.exit,
          alignment: Alignment.topCenter,
          child: widget.leaving
              ? const SizedBox(width: double.infinity, height: 0)
              : AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) {
                    final t = CharakCurves.emphasized.transform(_ctrl.value);
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(offset: Offset(0, -CharakMotion.liftOffset * (1 - t)), child: child),
                    );
                  },
                  child: Padding(padding: const EdgeInsets.only(bottom: 12), child: widget.child),
                ),
        ),
      ),
    );
  }
}

/// Loading placeholder shaped like the request card.
class _RequestCardSkeleton extends StatelessWidget {
  const _RequestCardSkeleton();

  @override
  Widget build(BuildContext context) => const CharakSkeletonCard();
}

/// Request card (V2 doctor mock): avatar, patient and channel, a "Waiting"
/// chip; the complaint; a hairline, then time · channel and the fee in
/// narrow tabular figures; then Decline (soft red) and Review (blue).
/// A live arrival carries a blue "New" chip instead of "Waiting".
class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool isNew;
  final VoidCallback onDecline;
  const _RequestCard({required this.booking, required this.isNew, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    final patient = booking['users'] as Map<String, dynamic>?;
    final name    = patient?['name'] as String? ?? 'Patient';
    final channel = booking['channel'] as String? ?? '';
    final start   = booking['scheduled_start'] as String? ?? '';
    final dt      = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    final dateStr = dt != null ? DateFormat('EEE d MMM, h:mm a').format(dt) : '—';
    final price   = (booking['price_confirmed'] as num?)?.toDouble();
    final id      = booking['id'] as String;
    final address = booking['patient_address'] as String?;
    final channelLabel = channel == 'home_visit' ? 'Home visit' : 'Online';

    return CharakCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CharakAvatar(name: name, radius: 24),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: CharakText.titleSmall.copyWith(fontSize: 19), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(channel == 'home_visit' ? 'Home visit request' : 'Online consult request',
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          isNew
              ? const CharakBadge(label: 'New', variant: CharakBadgeVariant.primary)
              : const CharakBadge(label: 'Waiting', variant: CharakBadgeVariant.muted),
        ]),
        if (address != null && address.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.place_outlined, size: 16, color: CharakColors.inkMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(address,
                  style: CharakText.body.copyWith(color: CharakColors.inkMuted),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: CharakColors.border))),
          child: Row(children: [
            Icon(Icons.schedule_rounded, size: 16, color: CharakColors.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: dateStr, style: CharakText.label.tabular.copyWith(color: CharakColors.ink)),
                  TextSpan(text: ' · $channelLabel'),
                ]),
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (price != null)
              Text('₹${price.toStringAsFixed(0)}', style: CharakText.numeric.copyWith(color: CharakColors.ink)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: CharakButton(label: 'Decline', variant: CharakButtonVariant.danger, onPressed: onDecline),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CharakButton(label: 'Review', onPressed: () => context.push('/request/$id')),
          ),
        ]),
      ]),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _incomingProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/bookings/doctor/incoming');
  return List<Map<String, dynamic>>.from(res as List);
});

final _meProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
});

/// Whether new patients can send requests ("Accepting requests" switch).
/// Defaults to on: a backend without the column has no way to pause.
final _acceptingProvider = FutureProvider.autoDispose<bool>((ref) async {
  final me = await ref.watch(_meProvider.future);
  return me['accepting_requests'] as bool? ?? true;
});

/// What stops patients booking a channel the doctor offers, as one line and
/// the screen that fixes it; null when everything offered is bookable.
/// From GET /doctors/me `listing` (backend services/listing.py).
({String lead, String message, String route})? _listingGap(Map<String, dynamic>? me) {
  final listing = me?['listing'] as Map<String, dynamic>?;
  if (listing == null) return null;
  final channels = (listing['channels'] as Map?)?.cast<String, dynamic>() ?? const {};
  const names = {'online_consult': 'online consults', 'home_visit': 'home visits'};
  const words = {'price': 'a price', 'hours': 'your hours', 'base_location': 'your base location'};
  final offered = channels.entries.where((e) => (e.value as Map)['offered'] == true).toList();
  if (offered.isEmpty) {
    return (
      lead: "Patients can't book you yet.",
      message: ' Choose online consults, home visits or both.',
      route: '/setup/channels',
    );
  }
  final gaps = [
    for (final e in offered)
      if (((e.value as Map)['missing'] as List?)?.isNotEmpty == true)
        (channel: e.key, missing: List<String>.from((e.value as Map)['missing'] as List)),
  ];
  if (gaps.isEmpty) return null;
  final first = gaps.first;
  final route = first.missing.contains('price')
      ? '/setup/pricing'
      : (first.channel == 'home_visit' ? '/setup/home-visit' : '/setup/online');
  String list(List<String> m) {
    final w = [for (final k in m) words[k] ?? k];
    return w.length == 1 ? w.first : '${w.sublist(0, w.length - 1).join(', ')} and ${w.last}';
  }
  String capital(String t) => '${t[0].toUpperCase()}${t.substring(1)}';
  return (
    lead: listing['visible'] == true
        ? '${capital(names[first.channel]!)} are hidden from patients.'
        : "Patients can't book you yet.",
    // One channel: "Add your hours and your base location." Both: name each.
    message: gaps.length == 1
        ? ' Add ${list(first.missing)}.'
        : ' ${[for (final g in gaps) 'For ${names[g.channel]}, add ${list(g.missing)}'].join('. ')}.',
    route: route,
  );
}

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

  StreamSubscription<CharakPushMessage>? _pushSub;

  @override
  void initState() {
    super.initState();
    _pollIncoming();
    // A request, cancellation or payment pushed while this tab is open shows
    // here straight away rather than at the next poll.
    _pushSub = CharakPush.instance.messages.listen((m) {
      if (m.opened) return;
      if (const {'booking.requested', 'booking.cancelled', 'booking.hold_expired', 'payment.received'}
          .contains(m.event)) {
        _poll?.pokeNow();
        ref.invalidate(_incomingProvider);
      }
    });
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
    final patient = (row['users'] as Map?)?['name'] as String? ?? 'A patient';
    final issue = row['issue'] as String?;
    final review = await showCharakHeadsUp(
      context,
      overline: 'New request · now',
      message: issue != null && issue.isNotEmpty ? '$patient · $issue' : '$patient · ${CharakFormat.channel(row['channel'] as String?)}',
    );
    if (review && mounted) context.push('/request/$id');
  }

  Future<void> _accept(String bookingId) async {
    setState(() => _leaving.add(bookingId));
    await Future<void>.delayed(CharakMotion.exit);
    if (!mounted) return;
    try {
      // A new Practitioner Agreement or policy version is signed first.
      await charakWithSignatures(
          context, () => ApiClient.instance.patch('/bookings/$bookingId/accept', {}));
      _fresh.remove(bookingId);
      ref.invalidate(_incomingProvider);
      if (mounted) showCharakToast(context, message: 'Accepted · the patient has been asked to pay');
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _leaving.remove(bookingId));
    }
  }

  bool? _acceptingOverride;

  Future<void> _setAccepting(bool value) async {
    setState(() => _acceptingOverride = value);
    try {
      await ApiClient.instance.patch('/doctors/me', {'accepting_requests': value});
      ref.invalidate(_meProvider);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _acceptingOverride = !value);
        showCharakToast(context, message: e.message, isError: true);
      }
    }
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
    _pushSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(_incomingProvider);
    final doctorName = ref.watch(authProvider).user?['name'] as String?;
    final count = incoming.valueOrNull?.length;
    final accepting = _acceptingOverride ?? ref.watch(_acceptingProvider).valueOrNull ?? true;
    final availability = CharakCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Accepting requests', style: CharakText.titleSmall.copyWith(fontSize: 17, color: CharakColors.ink)),
            const SizedBox(height: 2),
            CharakFadeSwap(
              child: Text(
                accepting ? 'Patients can send you requests' : 'Paused · hidden from search',
                key: ValueKey(accepting),
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Semantics(
          label: 'Accepting requests',
          child: CharakSwitch(value: accepting, onChanged: _setAccepting),
        ),
      ]),
    );
    return CharakLargeTitleScaffold(
      eyebrow: doctorName == null ? null : CharakFormat.doctor(doctorName),
      eyebrowColor: CharakColors.inkMuted,
      title: 'Requests',
      subtitle: count == null
          ? 'New requests arrive live.'
          : count == 0
              ? 'Nothing waiting. New requests arrive live.'
              : '$count waiting for your decision',
      subtitleColor: (count ?? 0) > 0 ? CharakColors.greeting : null,
      onRefresh: () {
        ref.invalidate(_meProvider);
        return ref.refresh(_incomingProvider.future);
      },
      children: [
        if (_listingGap(ref.watch(_meProvider).valueOrNull) case final gap?) ...[
          CharakPressable(
            onTap: () async {
              await context.push(gap.route);
              ref.invalidate(_meProvider);
            },
            child: CharakNoteBanner(
              icon: LucideIcons.eyeOff,
              tone: CharakStatusTone.review,
              leadLabel: gap.lead,
              message: gap.message,
            ),
          ),
          const SizedBox(height: 12),
        ],
        availability,
        const SizedBox(height: 12),
        ...incoming.when(
        loading: () => const [_RequestCardSkeleton(), _RequestCardSkeleton(), _RequestCardSkeleton()],
        error: (e, _) => [
          CharakEmptyState(
            icon: LucideIcons.cloudOff,
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
                  icon: LucideIcons.inbox,
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
                        onAccept: () => _accept(b['id'] as String),
                      ),
                    ),
                  ),
              ],
      ),
      ],
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

/// Request card (design system V2, Doctor · Requests): avatar, patient and a
/// "Waiting" chip; the patient's own words; a hairline, then "Today, 6:00 PM ·
/// Home visit" and the fee in narrow tabular figures; then Decline (soft red)
/// and Accept (blue). Tapping the card opens the full request.
class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool isNew;
  final VoidCallback onDecline;
  final VoidCallback onAccept;
  const _RequestCard({
    required this.booking,
    required this.isNew,
    required this.onDecline,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final patient = booking['users'] as Map<String, dynamic>?;
    final name    = patient?['name'] as String? ?? 'Patient';
    final channel = booking['channel'] as String?;
    final start   = DateTime.tryParse(booking['scheduled_start'] as String? ?? '');
    final price   = booking['price_confirmed'] as num?;
    final id      = booking['id'] as String;
    final issue   = booking['issue'] as String?;
    final km      = booking['distance_km'] as num?;

    return CharakCard(
      onTap: () => context.push('/request/$id'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CharakAvatar(name: name, radius: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: CharakText.titleSmall.copyWith(fontSize: 19, color: CharakColors.ink),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              [
                CharakFormat.channel(channel),
                if (channel == 'home_visit' && km != null) '${km.toStringAsFixed(1)} km away',
              ].join(' · '),
              style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ])),
          const SizedBox(width: 8),
          isNew
              ? const CharakBadge(label: 'New', variant: CharakBadgeVariant.primary)
              : const CharakBadge(label: 'Waiting', variant: CharakBadgeVariant.muted),
        ]),
        if (issue != null && issue.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(issue,
              style: CharakText.body.copyWith(color: CharakColors.ink),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: CharakColors.border))),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: start != null ? CharakFormat.dayTime(start) : '—',
                    style: CharakText.label.tabular.copyWith(color: CharakColors.ink),
                  ),
                  TextSpan(text: ' · ${CharakFormat.channel(channel)}'),
                ]),
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (price != null)
              Text(CharakFormat.rupees(price),
                  style: CharakText.numeric.copyWith(fontSize: 20, color: CharakColors.ink)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: CharakButton(label: 'Decline', variant: CharakButtonVariant.danger, onPressed: onDecline),
          ),
          const SizedBox(width: 10),
          Expanded(child: CharakButton(label: 'Accept', onPressed: onAccept)),
        ]),
      ]),
    );
  }
}

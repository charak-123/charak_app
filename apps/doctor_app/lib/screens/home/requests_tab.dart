import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  StreamSubscription? _realtimeSub;
  final Set<String> _seen = {};

  /// Requests that landed live in this session — these get the `.req-card.new`
  /// primary ring and the "NEW" tag, and animate in from above.
  final Set<String> _fresh = {};

  /// Requests mid-dismissal, playing `.req-item.leaving` before the refetch.
  final Set<String> _leaving = {};

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final doctorId = ref.read(authProvider).user?['id'];
    if (doctorId == null) return;

    _realtimeSub = Supabase.instance.client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('doctor_id', doctorId)
        .listen((rows) {
      final newRequests = rows.where(
        (r) => r['status'] == 'requested' && !_seen.contains(r['id'] as String),
      );
      if (newRequests.isNotEmpty && mounted) {
        for (final r in newRequests) {
          _seen.add(r['id'] as String);
          _fresh.add(r['id'] as String);
        }
        ref.invalidate(_incomingProvider);
      }
    });
  }

  Future<void> _decline(String bookingId) async {
    // `.req-item.leaving` — 240ms slide-out before the list refetches.
    setState(() => _leaving.add(bookingId));
    await Future<void>.delayed(CharakDurations.sheetOpen);
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
    _realtimeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(_incomingProvider);
    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        bottom: false,
        child: incoming.when(
          // `.skel` placeholders shaped like the real `.req-card` stack so the
          // header stays put and the cards don't jump in.
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: const [
              CharakScreenHeader(
                title: 'Requests',
                subtitle: 'Decide on each — new requests arrive live.',
              ),
              SizedBox(height: 14),
              _RequestCardSkeleton(),
              _RequestCardSkeleton(),
              _RequestCardSkeleton(),
            ],
          ),
          error: (e, _) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: CharakColors.danger, size: 40),
              const SizedBox(height: 8),
              Text('Failed to load requests', style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
              TextButton(onPressed: () => ref.invalidate(_incomingProvider), child: const Text('Retry')),
            ]),
          ),
          data: (bookings) => RefreshIndicator(
            onRefresh: () => ref.refresh(_incomingProvider.future),
            child: ListView(
              // `.body` — 20px gutters, this tab's `padding-top:14px`.
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                CharakScreenHeader(
                  title: 'Requests',
                  subtitle: 'Decide on each — new requests arrive live.',
                  trailing: bookings.isNotEmpty
                      ? CharakBadge(label: '${bookings.length} new', variant: CharakBadgeVariant.primary)
                      : null,
                ),
                const SizedBox(height: 14),
                if (bookings.isEmpty)
                  CharakEmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'All caught up',
                    message: 'New booking requests will appear here the moment a patient sends one.',
                    action: CharakButton(
                      label: 'Refresh',
                      outlined: true,
                      onPressed: () => ref.invalidate(_incomingProvider),
                    ),
                  )
                else
                  ...bookings.map((b) {
                    final id = b['id'] as String;
                    return _RequestItem(
                      key: ValueKey(id),
                      leaving: _leaving.contains(id),
                      arrive: _fresh.contains(id),
                      // `.pulse` — an existing row flashes primarySoft when its
                      // status changes. Arrival/dismissal motion lives in
                      // _RequestItem, so the two never overlap.
                      child: CharakStatusPulse(
                        trigger: b['status'],
                        child: _RequestCard(
                          booking: b,
                          isNew: _fresh.contains(id),
                          onDecline: () => _decline(id),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a request card in the two list motions from `core.css`:
/// `.arrive` (slide down from -16px, 320ms) on first build, and
/// `.req-item.leaving` (slide right 60px, collapse, 240ms) on dismissal.
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
    // `@keyframes req-out` — translateX(60px), fade, then max-height/margin
    // collapse, all inside 240ms.
    return AnimatedSlide(
      duration: CharakDurations.sheetOpen,
      curve: Curves.easeOut,
      offset: widget.leaving ? const Offset(0.18, 0) : Offset.zero,
      child: AnimatedOpacity(
        duration: CharakDurations.sheetOpen,
        opacity: widget.leaving ? 0 : 1,
        child: AnimatedSize(
          duration: CharakDurations.sheetOpen,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: widget.leaving
              ? const SizedBox(width: double.infinity, height: 0)
              : AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) {
                    final t = Curves.easeOut.transform(_ctrl.value);
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(offset: Offset(0, -16 * (1 - t)), child: child),
                    );
                  },
                  // `.req-card` — 10px bottom gutter between cards.
                  child: Padding(padding: const EdgeInsets.only(bottom: 10), child: widget.child),
                ),
        ),
      ),
    );
  }
}

/// Loading placeholder shaped like `.req-card`: the 48px avatar + two-line
/// identity stack, the `.req-mid` time/price line and the 42px `.req-actions`
/// pair, so the real card lands without shifting anything.
class _RequestCardSkeleton extends StatelessWidget {
  const _RequestCardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      borderRadius: const BorderRadius.all(CharakRadius.card),
      border: Border.all(color: CharakColors.border),
      boxShadow: const [CharakShadow.card],
    ),
    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CharakSkeleton(width: 48, height: 48, radius: 24),
        SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CharakSkeleton(width: 132, height: 15.5),
            SizedBox(height: 6),
            CharakSkeleton(width: 88, height: 12.5),
          ]),
        ),
      ]),
      SizedBox(height: 13),
      Row(children: [
        Expanded(child: CharakSkeleton(width: 150, height: 13)),
        SizedBox(width: 10),
        CharakSkeleton(width: 62, height: 15),
      ]),
      SizedBox(height: 13),
      Row(children: [
        Expanded(child: CharakSkeleton(height: 42, radius: 10)),
        SizedBox(width: 10),
        Expanded(child: CharakSkeleton(height: 42, radius: 10)),
      ]),
    ]),
  );
}

/// `.req-card` — 15px padding on the card radius. The `.new` variant adds a
/// primary border plus a `0 0 0 1px` primary ring and hangs a "NEW" pill off
/// the top edge at `top:-9px; left:14px`.
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

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
        border: Border.all(color: isNew ? CharakColors.primary : CharakColors.border),
        // `.req-card.new` — box-shadow: 0 0 0 1px var(--color-primary)
        boxShadow: isNew
            ? const [BoxShadow(color: CharakColors.primary, blurRadius: 0, spreadRadius: 1)]
            : const [CharakShadow.card],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // `.req-top` — 48px avatar, 12px gap.
        Row(children: [
          CharakAvatar(name: name, radius: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: CharakText.h2.copyWith(fontSize: 15.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            Text(
              channel == 'home_visit' ? 'Home Visit' : 'Online Consult',
              style: _sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ])),
        ]),
        // `.req-mid` — 13px muted line with the price pushed right.
        const SizedBox(height: 11),
        Row(children: [
          const Icon(Icons.access_time_rounded, size: 14, color: CharakColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(dateStr,
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (price != null)
            Text.rich(TextSpan(children: [
              TextSpan(
                text: '₹${price.toStringAsFixed(0)}',
                style: CharakText.h2.copyWith(
                  fontSize: 15,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              // `.per` — 11px/500 muted unit.
              const TextSpan(text: '/15m', style: _per),
            ])),
        ]),
        if (address != null && address.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.place_outlined, size: 13, color: CharakColors.inkMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(address, style: _sub, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ],
        // `.req-actions` — 42px / 14px buttons, not the default 50px CTA.
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: _ReqAction(label: 'Decline', onPressed: onDecline)),
          const SizedBox(width: 10),
          Expanded(
            child: _ReqAction(
              label: 'Review',
              primary: true,
              onPressed: () => context.push('/request/$id'),
            ),
          ),
        ]),
      ]),
    );

    if (!isNew) return card;
    return Stack(clipBehavior: Clip.none, children: [
      card,
      const Positioned(
        top: -9,
        left: 14,
        child: _ReqTag(),
      ),
    ]);
  }

  static const _sub = TextStyle(
    fontFamily: CharakText.fontFamily,
    fontSize: 12.5,
    height: 1.4,
    color: CharakColors.inkMuted,
  );

  static const _per = TextStyle(
    fontFamily: CharakText.fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: CharakColors.inkMuted,
  );
}

/// `.req-tag` — solid primary pill, 10.5px/600 uppercase with 0.05em tracking.
class _ReqTag extends StatelessWidget {
  const _ReqTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: const BoxDecoration(
      color: CharakColors.primary,
      borderRadius: BorderRadius.all(CharakRadius.pill),
    ),
    child: const Text(
      'NEW',
      style: TextStyle(
        fontFamily: CharakText.fontFamily,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 10.5 * 0.05,
        color: Colors.white,
      ),
    ),
  );
}

/// `.req-actions .btn` — the compact 42px / 14px in-card action pair.
class _ReqAction extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback? onPressed;
  const _ReqAction({required this.label, this.primary = false, this.onPressed});

  @override
  Widget build(BuildContext context) => Material(
    color: primary ? CharakColors.primary : Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(CharakRadius.button),
      side: primary ? BorderSide.none : const BorderSide(color: CharakColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 42,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: primary ? Colors.white : CharakColors.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
// intl is a direct dependency; don't rely on shadcn_ui re-exporting DateFormat.
// ignore: unnecessary_import
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../visit_navigation.dart';

// ── Procedure checklist entry ─────────────────────────────────────────────────

class _ProcedureEntry {
  final String procedureId;
  final String name;
  final double unitPrice;
  bool selected = false;
  _ProcedureEntry({
    required this.procedureId,
    required this.name,
    required this.unitPrice,
  });
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _activeVisitProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final results = await Future.wait([
    ApiClient.instance.get('/bookings/$id'),
    ApiClient.instance.get('/doctors/me/procedures'),
  ]);
  return {
    'booking': results[0] as Map<String, dynamic>,
    'procedures': results[1] as List,
  };
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ActiveVisitScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const ActiveVisitScreen({super.key, required this.bookingId});
  @override
  ConsumerState<ActiveVisitScreen> createState() => _State();
}

class _State extends ConsumerState<ActiveVisitScreen> {
  List<_ProcedureEntry> _procedures = [];
  bool _acting = false;
  bool _billing = false;
  bool _billed = false;
  bool _notifyingLate = false;

  /// Time since the consultation started (the server's `started_at`). A
  /// reference for the doctor, not a billing input.
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _refresh() => ref.invalidate(_activeVisitProvider(widget.bookingId));

  String _clock(DateTime since) {
    final e = _now.difference(since);
    final elapsed = e.isNegative ? Duration.zero : e;
    final h = elapsed.inHours;
    final mm = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  void _initProcedures(List rawProcs) {
    if (_procedures.isEmpty && rawProcs.isNotEmpty) {
      _procedures = rawProcs.map((p) {
        final m = p as Map<String, dynamic>;
        return _ProcedureEntry(
          procedureId: m['id'] as String,
          name: m['name'] as String,
          unitPrice: double.tryParse(m['price'].toString()) ?? 0,
        );
      }).toList();
    }
  }

  double get _total => _procedures
      .where((p) => p.selected)
      .fold(0.0, (sum, p) => sum + p.unitPrice);

  List<Map<String, dynamic>> get _selectedItems => _procedures
      .where((p) => p.selected)
      .map((p) => {'name': p.name, 'price': p.unitPrice})
      .toList();

  /// Runs one server action, then reloads the visit. A failure leaves the
  /// screen as it was and says why: nothing shows as done until the server
  /// says it is.
  Future<void> _act(Future<void> Function() action, {String? done}) async {
    setState(() => _acting = true);
    try {
      await action();
      if (mounted && done != null) showCharakToast(context, message: done);
      _refresh();
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _startJourney() async {
    final ok = await showCharakConfirm(
      context,
      title: 'Start journey?',
      message: 'Tap this as you leave for the patient. They are told you are on the way. '
          'From now, if they cancel, the fee is not refunded.',
      confirmLabel: 'Start journey',
    );
    if (!ok || !mounted) return;
    await _act(() => ApiClient.instance.post('/bookings/${widget.bookingId}/journey/start', {}),
        done: 'Journey started. The patient has been told.');
  }

  Future<void> _startConsultation() async {
    final ok = await showCharakConfirm(
      context,
      title: 'Start the consultation?',
      message: "Tap this when you're with the patient. The booking can't be cancelled after this.",
      confirmLabel: 'Start',
    );
    if (!ok || !mounted) return;
    await _act(() => ApiClient.instance.post('/bookings/${widget.bookingId}/consultation/start', {}));
  }

  Future<void> _openPrescription() async {
    await context.push('/visit/${widget.bookingId}/prescription');
    _refresh();
  }

  Future<void> _billProcedures() async {
    final items = _selectedItems;
    final ok = await showCharakConfirm(
      context,
      title: 'Bill ${items.length} procedure${items.length == 1 ? '' : 's'}?',
      message: '${CharakFormat.rupees(_total)} is billed to the patient. '
          'Bills above your review threshold go to a senior doctor first.',
      confirmLabel: 'Send bill',
    );
    if (!ok || !mounted) return;
    setState(() => _billing = true);
    try {
      await ApiClient.instance.post('/bookings/${widget.bookingId}/procedure-bill', {'items': items});
      if (mounted) {
        setState(() => _billed = true);
        showCharakToast(context, message: 'Procedure bill sent');
      }
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _billing = false);
    }
  }

  /// Opens the patient's location in whatever maps app the phone has.
  ///
  /// Coordinates are preferred — a home visit is often to an address a
  /// geocoder gets wrong, and the pin the patient dropped is the one that is
  /// actually right. The text address is the fallback, and if neither is
  /// present the address has not been released yet.
  Future<void> _navigateToPatient(Map<String, dynamic> booking) async {
    final uri = patientMapUri(booking);
    if (uri == null) {
      showCharakToast(context,
          message: "The patient's address hasn't been released yet",
          isError: true);
      return;
    }

    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;

    // No app registered for geo: — the web map is something every phone opens.
    final web = patientMapWebUri(booking);
    if (web == null || !await launchUrl(web, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showCharakToast(context,
            message: 'No maps app could be opened', isError: true);
      }
    }
  }

  /// Tells the patient the doctor is delayed. A nudge only — the booking does
  /// not change state, so this stays available however many times it is needed.
  Future<void> _runningLate(Map<String, dynamic> booking) async {
    final minutes = await showCharakSheet<int>(
      context,
      title: 'Let the patient know',
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'They are notified straight away. The slot is unchanged.',
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
              ),
            ),
            for (final m in const [10, 15, 30, 45])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CharakButton(
                  label: '$m minutes late',
                  variant: CharakButtonVariant.outline,
                  onPressed: () => Navigator.pop(ctx, m),
                ),
              ),
          ],
        ),
      ),
    );
    if (minutes == null || !mounted) return;

    setState(() => _notifyingLate = true);
    try {
      await ApiClient.instance.post(
        '/bookings/${widget.bookingId}/running-late',
        {'minutes': minutes},
      );
      if (mounted) {
        showCharakToast(context, message: 'Patient notified — $minutes min');
      }
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _notifyingLate = false);
    }
  }

  /// Can't make it, or the call failed: offer the patient up to three new
  /// times (same price). They pick one or take a full refund.
  Future<void> _proposeTimes(Map<String, dynamic> booking) async {
    final minutes = (booking['duration_min'] as num?)?.toInt();
    final lengthParam = const [10, 15, 20, 30, 45, 60].contains(minutes) ? '&duration_min=$minutes' : '';
    Map<String, dynamic> grid;
    try {
      grid = await ApiClient.instance.get(
          '/doctors/${booking['doctor_id']}/slots?days=3$lengthParam') as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
      return;
    }
    if (!mounted) return;
    final picked = await showCharakSheet<({String cause, List<String> times})>(
      context,
      title: 'Propose new times',
      child: _ProposeTimes(grid: grid),
    );
    if (picked == null || !mounted) return;
    await _act(() => ApiClient.instance.post('/bookings/${widget.bookingId}/reschedule-requests', {
          'cause': picked.cause,
          'options': picked.times,
        }), done: 'Sent. The patient picks a time or takes a refund.');
  }

  /// The one thing to do next, for the CTA bar, and why it may not be open yet.
  ({String label, IconData icon, VoidCallback? onPressed, String? hint}) _next(
      Map<String, dynamic> booking) {
    final status = booking['status'] as String? ?? '';
    final isHome = booking['channel'] == 'home_visit';
    final start = DateTime.tryParse(booking['scheduled_start'] as String? ?? '')?.toLocal();
    final journeyAt = DateTime.tryParse(booking['journey_started_at'] as String? ?? '')?.toLocal();
    final opens = start?.subtract(Duration(minutes: isHome ? 120 : 15));
    final early = opens != null && _now.isBefore(opens);
    final opensLine = opens == null ? null : 'Opens at ${DateFormat('h:mm a').format(opens)}';

    switch (status) {
      case 'paid' when isHome && journeyAt == null:
        return (
          label: 'Start journey',
          icon: LucideIcons.navigation,
          onPressed: early ? null : _startJourney,
          hint: early ? '$opensLine, 2 hours before the visit' : 'Tap as you leave',
        );
      case 'paid' when isHome:
        return (
          label: 'Start consultation',
          icon: LucideIcons.stethoscope,
          onPressed: early ? null : _startConsultation,
          hint: early ? opensLine : null,
        );
      case 'paid':
        return (
          label: 'Join call',
          icon: LucideIcons.video,
          onPressed: early ? null : () => context.push('/consult/${widget.bookingId}'),
          hint: early ? '$opensLine, 15 minutes before' : 'Joining starts the consultation',
        );
      case 'in_progress':
        return (
          label: 'Write prescription',
          icon: LucideIcons.notebookPen,
          onPressed: _openPrescription,
          hint: null,
        );
      case 'consulted' || 'completed':
        return (
          label: 'View prescription',
          icon: LucideIcons.fileText,
          onPressed: _openPrescription,
          hint: null,
        );
      default:
        return (
          label: 'Waiting for payment',
          icon: LucideIcons.hourglass,
          onPressed: null,
          hint: 'The visit opens once the patient pays',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_activeVisitProvider(widget.bookingId));
    return CharakScreen(
      title: 'Visit',
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: const [
            CharakSkeleton(height: 78, radius: 26),
            SizedBox(height: 12),
            CharakSkeleton(height: 104, radius: 26),
            SizedBox(height: 14),
            CharakSkeleton(height: 210, radius: 26),
          ],
        ),
        error: (e, _) => CharakErrorState(error: e, onRetry: _refresh),
        data: (data) {
          final booking = data['booking'] as Map<String, dynamic>;
          final procs   = data['procedures'] as List;
          _initProcedures(procs);
          final status = booking['status'] as String? ?? '';
          final isHome = booking['channel'] == 'home_visit';
          final price  = booking['price_confirmed'] as num?;
          final journeyAt = DateTime.tryParse(booking['journey_started_at'] as String? ?? '')?.toLocal();
          final startedAt = DateTime.tryParse(booking['started_at'] as String? ?? '')?.toLocal();
          final before = status == 'accepted' || status == 'paid';
          final during = status == 'in_progress' || status == 'consulted';
          final next = _next(booking);

          final threshold = (booking['doctors'] as Map<String, dynamic>?)?['procedure_review_threshold'];
          final needsReview = threshold != null && _total > (threshold as num);

          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                color: CharakColors.primary,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  children: [
                    CharakStatusPulse(
                      trigger: status,
                      child: _PatientInfoCard(booking: booking),
                    ),
                    const SizedBox(height: 12),
                    if (status == 'in_progress' && startedAt != null) ...[
                      _VisitTimer(clock: _clock(startedAt)),
                      const SizedBox(height: 12),
                    ],
                    if (journeyAt != null && before) ...[
                      CharakNoteBanner(
                        icon: LucideIcons.navigation,
                        leadLabel: 'Journey started',
                        message: ' at ${DateFormat('h:mm a').format(journeyAt)}. The patient knows you are on the way.',
                        tone: CharakStatusTone.active,
                      ),
                      const SizedBox(height: 12),
                    ] else if (status == 'paid') ...[
                      CharakNoteBanner(
                        icon: LucideIcons.banknote,
                        leadLabel: 'Paid',
                        message: ' ${CharakFormat.rupees(price)} confirmed. The visit goes ahead.',
                        tone: CharakStatusTone.confirmed,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (status == 'consulted') ...[
                      const CharakNoteBanner(
                        icon: LucideIcons.send,
                        leadLabel: 'Prescription sent.',
                        message: ' The visit completes when the patient opens it, or 72 hours after you sent it.',
                        tone: CharakStatusTone.active,
                      ),
                      const SizedBox(height: 12),
                    ] else if (status == 'completed') ...[
                      const CharakNoteBanner(
                        icon: LucideIcons.circleCheck,
                        leadLabel: 'Visit complete.',
                        message: ' The fee shows in Earnings and can be withdrawn once its hold ends.',
                        tone: CharakStatusTone.confirmed,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _VisitLinesCard(booking: booking),
                    const SizedBox(height: 14),
                    if (isHome && during) ...[
                      CharakStatusPulse(
                        trigger: needsReview,
                        child: _ProcedureChecklist(
                          procedures: _procedures,
                          total: _total,
                          threshold: threshold != null ? (threshold as num).toDouble() : null,
                          needsReview: needsReview,
                          onToggle: _billed
                              ? null
                              : (i) => setState(() => _procedures[i].selected = !_procedures[i].selected),
                          action: CharakButton(
                            label: _billed ? 'Bill sent' : 'Send procedure bill',
                            variant: CharakButtonVariant.tonal,
                            isLoading: _billing,
                            onPressed: _billed || _selectedItems.isEmpty ? null : _billProcedures,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (before && isHome) ...[
                      CharakButton(
                        label: 'Navigate to patient',
                        icon: LucideIcons.mapPinned,
                        variant: CharakButtonVariant.outline,
                        onPressed: () => _navigateToPatient(booking),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (status == 'in_progress' && !isHome) ...[
                      CharakButton(
                        label: 'Rejoin call',
                        icon: LucideIcons.video,
                        variant: CharakButtonVariant.outline,
                        onPressed: () => context.push('/consult/${widget.bookingId}'),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (status == 'paid' || status == 'in_progress') ...[
                      CharakButton(
                        label: "Can't make it? Propose new times",
                        icon: LucideIcons.calendarClock,
                        variant: CharakButtonVariant.outline,
                        onPressed: () => _proposeTimes(booking),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (before)
                      CharakButton(
                        label: 'Running late',
                        variant: CharakButtonVariant.outline,
                        icon: LucideIcons.clock,
                        isLoading: _notifyingLate,
                        onPressed: () => _runningLate(booking),
                      ),
                  ],
                ),
              ),
            ),
            CharakCtaBar(
              header: next.hint == null
                  ? null
                  : Text(next.hint!, textAlign: TextAlign.center, style: charakHintStyle),
              children: [
                Expanded(
                  child: CharakButton(
                    label: next.label,
                    icon: next.icon,
                    isLoading: _acting,
                    onPressed: next.onPressed,
                  ),
                ),
              ],
            ),
          ]);
        },
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// `.act-doctor-card` — 15px-padded card: avatar, 16px/600 name over a
/// 12.5px muted channel · slot line, and a success status pill.
class _PatientInfoCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _PatientInfoCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final patient = booking['users'] as Map<String, dynamic>? ?? {};
    final name    = patient['name'] as String? ?? 'Patient';
    final channel = booking['channel'] as String? ?? '';
    final start   = booking['scheduled_start'] as String? ?? '';
    final dt      = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    final label   = CharakFormat.channel(channel);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
      ),
      child: Row(children: [
        CharakAvatar(name: name, radius: 24),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: CharakText.h2.copyWith(fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text(
            dt != null ? '$label · ${_slotFormat.format(dt)}' : label,
            style: CharakText.caption.tabular.copyWith(color: CharakColors.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ])),
        const SizedBox(width: 10),
        // `.fade-swap` — keyed on the status so the pill lifts and
        // cross-fades whenever the booking moves on.
        CharakFadeSwap(
          child: CharakStatusPill.forStatus(
            booking['status'] as String? ?? '',
            key: ValueKey(booking['status']),
          ),
        ),
      ]),
    );
  }
}

final _slotFormat = DateFormat('EEE d MMM, h:mm a');

/// `.card` with the 6px/14px inset wrapping the visit's `.visit-line` rows.
class _VisitLinesCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _VisitLinesCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final isHome  = booking['channel'] == 'home_visit';
    final start   = booking['scheduled_start'] as String? ?? '';
    final dt      = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    final address = booking['patient_address'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
      ),
      child: Column(children: [
        CharakVisitLine(
          icon: LucideIcons.clock,
          value: dt != null ? _slotFormat.format(dt) : '—',
        ),
        if (isHome)
          CharakVisitLine(
            icon: LucideIcons.mapPin,
            value: (address != null && address.isNotEmpty) ? address : 'Address in the booking',
          )
        else
          const CharakVisitLine(
            icon: LucideIcons.video,
            value: 'Video consult',
            trailing: 'start the call at slot time',
          ),
      ]),
    );
  }
}

/// Procedures card — `.proc-check` rows (11px, hairline-separated, 18px
/// checkbox, muted tabular price), a `.proc-total` footer, and either the
/// senior-review banner or the threshold `.hint-line`.
class _ProcedureChecklist extends StatelessWidget {
  final List<_ProcedureEntry> procedures;
  final double total;
  final double? threshold;
  final bool needsReview;

  /// Null once the bill is sent: the list is then a record.
  final void Function(int)? onToggle;
  final Widget action;
  const _ProcedureChecklist({
    required this.procedures,
    required this.total,
    required this.threshold,
    required this.needsReview,
    required this.onToggle,
    required this.action,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      borderRadius: const BorderRadius.all(CharakRadius.card),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const CharakSectionTitle(label: 'Procedures performed'),
      const SizedBox(height: 2),
      Text(
        'Tick the procedures done this visit (your fixed rates), then send the bill. '
        'The patient pays it separately.',
        style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
      ),
      const SizedBox(height: 10),
      if (procedures.isEmpty)
        Text('No procedures configured.\nAdd procedures in Profile → Pricing.',
            style: CharakText.caption.copyWith(color: CharakColors.inkMuted))
      else
        ...procedures.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          return GestureDetector(
            onTap: onToggle == null ? null : () => onToggle!(i),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: i == procedures.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: CharakColors.border)),
              ),
              child: Row(children: [
                Expanded(child: Text(p.name, style: CharakText.body.copyWith(fontSize: 14))),
                Text(
                  CharakFormat.rupees(p.unitPrice),
                  style: CharakText.body.tabular.copyWith(color: CharakColors.inkMuted, fontSize: 15),
                ),
                const SizedBox(width: 10),
                // `.proc-check input` — 18px, primary accent.
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: p.selected,
                    activeColor: CharakColors.primary,
                    side: BorderSide(color: CharakColors.border, width: 1.5),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: onToggle == null ? null : (_) => onToggle!(i),
                  ),
                ),
              ]),
            ),
          );
        }),
      // `.proc-total` — 12px top gap, 13.5px muted label, 16px ink figure.
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            'Procedures total',
            style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
          ),
          Text(
            CharakFormat.rupees(total),
            style: CharakText.h2.copyWith(
              fontSize: 16,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      ),
      if (needsReview && threshold != null) ...[
        const SizedBox(height: 10),
        CharakNoteBanner(
          icon: LucideIcons.shieldQuestionMark,
          leadLabel: 'Senior review needed',
          message: '— this bill is above ${CharakFormat.rupees(threshold!)}. '
              'A senior doctor verifies it before the patient pays.',
        ),
      ] else if (threshold != null) ...[
        const SizedBox(height: 8),
        CharakHintLine(
          text: 'Bills above ${CharakFormat.rupees(threshold!)} are auto-sent for senior review.',
        ),
      ],
      if (procedures.isNotEmpty) ...[const SizedBox(height: 14), action],
    ]),
  );
}


/// Time on site, counting from when the doctor opened this screen.
///
/// Deliberately informational: nothing bills off it, and it is not sent
/// anywhere. It exists because a doctor mid-visit has no other way to see how
/// long they have been there.
class _VisitTimer extends StatelessWidget {
  final String clock;
  const _VisitTimer({required this.clock});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: CharakColors.bgSubtle,
          borderRadius: const BorderRadius.all(CharakRadius.card),
          border: Border.all(color: CharakColors.border),
        ),
        child: Row(children: [
          Icon(LucideIcons.timer, size: 17, color: CharakColors.inkMuted),
          const SizedBox(width: 9),
          Text('Time on visit',
              style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
          const Spacer(),
          Text(
            clock,
            style: CharakText.bodyMed.copyWith(
              fontSize: 14,
              color: CharakColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      );
}


const _causes = <String, String>{
  'doctor_unavailable': "I can't make it",
  'doctor_device': 'My phone or connection failed',
  'patient_device': "The patient's connection failed",
  'platform': 'The app had a problem',
  'mutual': 'We agreed to move it',
  'other': 'Something else',
};

/// Why, then up to three open times over the next 3 days.
class _ProposeTimes extends StatefulWidget {
  final Map<String, dynamic> grid;
  const _ProposeTimes({required this.grid});

  @override
  State<_ProposeTimes> createState() => _ProposeTimesState();
}

class _ProposeTimesState extends State<_ProposeTimes> {
  String? _cause;
  final _times = <String>[];

  @override
  Widget build(BuildContext context) {
    final days = widget.grid.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: ListView(shrinkWrap: true, children: [
        Text('Why does it need to move?', style: CharakText.label.copyWith(color: CharakColors.ink)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _causes.entries)
            CharakChip(label: e.value, selected: _cause == e.key, onTap: () => setState(() => _cause = e.key)),
        ]),
        const SizedBox(height: 6),
        Text('Moving a visit for your own reasons counts towards your reliability. '
            "The patient's or the app's problems don't.", style: charakHintStyle),
        const SizedBox(height: 16),
        Text('Offer up to 3 times', style: CharakText.label.copyWith(color: CharakColors.ink)),
        for (final day in days)
          if ((day.value as List).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(DateFormat('EEE d MMM').format(DateTime.parse(day.key)),
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final slot in (day.value as List).take(12))
                Builder(builder: (_) {
                  final iso = '${day.key}T${slot['start']}:00+05:30';
                  final on = _times.contains(iso);
                  return CharakChip(
                    label: slot['start'] as String,
                    numeric: true,
                    selected: on,
                    disabled: !on && _times.length >= 3,
                    onTap: () => setState(() => on ? _times.remove(iso) : _times.add(iso)),
                  );
                }),
            ]),
          ],
        const SizedBox(height: 18),
        CharakButton(
          label: 'Send to the patient',
          onPressed: _cause == null || _times.isEmpty
              ? null
              : () => Navigator.pop(context, (cause: _cause!, times: List<String>.of(_times))),
        ),
      ]),
    );
  }
}

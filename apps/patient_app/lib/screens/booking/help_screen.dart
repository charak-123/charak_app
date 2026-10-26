import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

import '../home/booking_providers.dart';

/// What the patient can do about a visit going wrong (GET /bookings/{id}/help).
final bookingHelpProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  return await ApiClient.instance.get('/bookings/$id/help') as Map<String, dynamic>;
});

const _reportLabels = <String, (String, String, IconData)>{
  'doctor_not_arrived': ("Doctor hasn't arrived", 'Your doctor hasn\'t reached you yet', LucideIcons.mapPinOff),
  'doctor_not_joined': ("Doctor hasn't joined", 'Your doctor isn\'t on the call', LucideIcons.videoOff),
  'call_failed': ('Problem with the call', 'The call dropped or wouldn\'t connect', LucideIcons.wifiOff),
  'other': ('Something else', 'Tell us what went wrong', LucideIcons.messageCircleWarning),
};

/// "Get help" for one booking (spec §13, §14): report a problem, follow the
/// case (CHK-…), choose a refund or another doctor when that's available,
/// and answer new times the doctor proposed. Nothing here is a verdict on the
/// doctor; that's decided separately.
class HelpScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const HelpScreen({super.key, required this.bookingId});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(bookingHelpProvider(widget.bookingId));
    ref.invalidate(patientBookingsProvider);
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) showCharakToast(context, message: done);
      _refresh();
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report(String type) async {
    final note = TextEditingController();
    final (title, _, _) = _reportLabels[type]!;
    final ok = await showCharakSheet<bool>(
      context,
      title: title,
      child: Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            type == 'doctor_not_arrived' || type == 'doctor_not_joined'
                ? "We'll check what happened. If the doctor didn't start, you can get a full refund or "
                    'choose another doctor straight away.'
                : 'Our team will look into it and get back to you.',
            style: charakHintStyle,
          ),
          const SizedBox(height: 12),
          CharakField(label: 'Anything to add? (optional)', controller: note, maxLines: 3, minLines: 2,
              textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 14),
          CharakButton(label: 'Report it', onPressed: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final res = await ApiClient.instance.post('/bookings/${widget.bookingId}/issues', {
        'reported_as': type,
        'note': note.text.trim().isEmpty ? null : note.text.trim(),
      }) as Map<String, dynamic>;
      if (mounted) showCharakToast(context, message: 'Reported. Your case is ${res['case_ref']}.');
    });
  }

  Future<void> _refund(Map<String, dynamic> incident, int paise) async {
    final ok = await showCharakConfirm(
      context,
      title: 'Get a full refund?',
      message: '${CharakFormat.rupees(paise / 100)} goes back to the way you paid. '
          'Banks usually take 5–7 working days.',
      confirmLabel: 'Refund me',
    );
    if (!ok || !mounted) return;
    await _run(() => ApiClient.instance.post('/incidents/${incident['id']}/remedy/refund', {}),
        done: 'Refund started');
  }

  void _chooseAnother(Map<String, dynamic> incident, Map<String, dynamic> remedies) {
    context.push('/directory', extra: {
      'replaces_incident_id': incident['id'],
      'budget_paise': remedies['replacement_budget_paise'],
      'exclude_doctor_id': remedies['exclude_doctor_id'],
      'channel': remedies['channel'],
    });
  }

  Future<void> _acceptTime(Map<String, dynamic> req, String start) async {
    final when = DateFormat('EEE d MMM, h:mm a').format(DateTime.parse(start).toLocal());
    final ok = await showCharakConfirm(context, title: 'Move your visit to $when?',
        message: 'Same doctor, same price.', confirmLabel: 'Move it');
    if (!ok || !mounted) return;
    await _run(() => ApiClient.instance.post('/reschedule-requests/${req['id']}/accept', {'start': start}),
        done: 'Your visit has moved to $when');
  }

  Future<void> _declineTimes(Map<String, dynamic> req) async {
    final ok = await showCharakConfirm(context, title: 'None of these work?',
        message: "You'll get a full refund instead.", confirmLabel: 'Refund me');
    if (!ok || !mounted) return;
    await _run(() => ApiClient.instance.post('/reschedule-requests/${req['id']}/decline', {}),
        done: 'Refund started');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bookingHelpProvider(widget.bookingId));
    return CharakScreen(
      title: 'Get help',
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => CharakErrorState(error: e, onRetry: _refresh),
        data: (h) {
          final incident = h['incident'] as Map<String, dynamic>?;
          final req = h['reschedule_request'] as Map<String, dynamic>?;
          final can = List<String>.from(h['can_report'] as List? ?? const []);
          final opens = DateTime.tryParse(h['help_opens_at'] as String? ?? '')?.toLocal();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(bookingHelpProvider(widget.bookingId).future),
            color: CharakColors.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 4, CharakSpacing.gutter, 32),
              children: [
                if (req != null) ...[
                  _RescheduleCard(req: req, busy: _busy, onPick: (s) => _acceptTime(req, s),
                      onDecline: () => _declineTimes(req)),
                  const SizedBox(height: 16),
                ],
                if (incident != null) ...[
                  _CaseCard(
                    incident: incident,
                    busy: _busy,
                    onRefund: (p) => _refund(incident, p),
                    onChooseAnother: () => _chooseAnother(incident, incident['remedies'] as Map<String, dynamic>),
                  ),
                  const SizedBox(height: 16),
                ],
                if (can.isNotEmpty) ...[
                  const CharakSectionTitle(label: 'Report a problem'),
                  const SizedBox(height: 8),
                  CharakGroupedList(children: [
                    for (final (i, t) in can.indexed)
                      CharakListRow(
                        icon: _reportLabels[t]!.$3,
                        title: _reportLabels[t]!.$1,
                        subtitle: _reportLabels[t]!.$2,
                        last: i == can.length - 1,
                        onTap: _busy ? null : () => _report(t),
                      ),
                  ]),
                ] else if (incident == null && req == null && opens != null && opens.isAfter(DateTime.now()))
                  CharakNoteBanner(
                    icon: LucideIcons.clock,
                    message: 'If your doctor hasn\'t arrived or joined by '
                        '${DateFormat('h:mm a').format(opens)} '
                        '(${h['grace_minutes']} minutes after the start), you can report it here.',
                    tone: CharakStatusTone.muted,
                  ),
                const SizedBox(height: 16),
                Text('In an emergency, call 112.', style: charakHintStyle, textAlign: TextAlign.center),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  final Map<String, dynamic> incident;
  final bool busy;
  final ValueChanged<int> onRefund;
  final VoidCallback onChooseAnother;
  const _CaseCard({required this.incident, required this.busy, required this.onRefund, required this.onChooseAnother});

  @override
  Widget build(BuildContext context) {
    final remedies = incident['remedies'] as Map<String, dynamic>? ?? const {};
    final available = remedies['available'] == true;
    final paise = (remedies['refund_paise'] as num?)?.toInt() ?? 0;
    final remedy = incident['remedy'] as String? ?? 'none';
    final status = incident['status'] as String? ?? 'reported';
    final defaultAt = DateTime.tryParse(remedies['default_refund_at'] as String? ?? '')?.toLocal();
    final (tone, label) = switch (status) {
      'confirmed' => (CharakStatusTone.confirmed, 'Confirmed'),
      'dismissed' => (CharakStatusTone.muted, 'Closed'),
      'undetermined' => (CharakStatusTone.muted, 'Closed'),
      _ => (CharakStatusTone.review, 'We\'re looking into it'),
    };
    final outcome = switch (remedy) {
      'refund' => 'You chose a full refund. You can follow it in Profile → Payments.',
      'replacement' => 'You chose another doctor. Your earlier payment covers it; anything left over is refunded.',
      'rescheduled' => 'Your visit was moved to a new time.',
      _ => null,
    };
    return CharakCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Case ${incident['case_ref']}', style: CharakText.body.weight(600).tabular.copyWith(color: CharakColors.ink)),
          const Spacer(),
          CharakStatusPill(label: label, tone: tone),
        ]),
        const SizedBox(height: 6),
        Text('Quote this if you contact support.', style: charakHintStyle),
        if (incident['decision_reason'] != null && status != 'reported') ...[
          const SizedBox(height: 10),
          Text(incident['decision_reason'] as String, style: CharakText.body.copyWith(color: CharakColors.ink)),
        ],
        if (outcome != null) ...[
          const SizedBox(height: 10),
          CharakNoteBanner(icon: LucideIcons.circleCheck, message: outcome, tone: CharakStatusTone.confirmed),
        ],
        if (available) ...[
          const SizedBox(height: 14),
          Text("Sorry about this. What would you like?", style: CharakText.label.copyWith(color: CharakColors.ink)),
          const SizedBox(height: 10),
          CharakButton(
            label: 'Full refund · ${CharakFormat.rupees(paise / 100)}',
            isLoading: busy,
            onPressed: () => onRefund(paise),
          ),
          const SizedBox(height: 8),
          CharakButton(
            label: 'Choose another doctor',
            variant: CharakButtonVariant.outline,
            onPressed: busy ? null : onChooseAnother,
          ),
          if (defaultAt != null) ...[
            const SizedBox(height: 8),
            Text("If you don't choose by ${DateFormat('EEE h:mm a').format(defaultAt)}, we'll refund you.",
                style: charakHintStyle, textAlign: TextAlign.center),
          ],
        ],
      ]),
    );
  }
}

class _RescheduleCard extends StatelessWidget {
  final Map<String, dynamic> req;
  final bool busy;
  final ValueChanged<String> onPick;
  final VoidCallback onDecline;
  const _RescheduleCard({required this.req, required this.busy, required this.onPick, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    final options = List<String>.from(req['options'] as List? ?? const []);
    final expires = DateTime.tryParse(req['expires_at'] as String? ?? '')?.toLocal();
    return CharakCard(
      tone: CharakCardTone.tint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your doctor asked to move this visit',
            style: CharakText.titleSmall.copyWith(fontSize: 18, color: CharakColors.ink)),
        const SizedBox(height: 4),
        Text(
          [
            if (req['note'] != null) '"${req['note']}"',
            'Pick a new time (same price), or get a full refund.',
          ].join(' '),
          style: CharakText.body.copyWith(color: CharakColors.inkMuted),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in options)
            CharakChip(
              label: DateFormat('EEE d MMM, h:mm a').format(DateTime.parse(o).toLocal()),
              numeric: true,
              disabled: busy || DateTime.parse(o).isBefore(DateTime.now()),
              onTap: () => onPick(o),
            ),
        ]),
        const SizedBox(height: 12),
        CharakButton(label: 'None of these work · refund me', variant: CharakButtonVariant.outline,
            onPressed: busy ? null : onDecline),
        if (expires != null) ...[
          const SizedBox(height: 8),
          Text("No answer by ${DateFormat('EEE h:mm a').format(expires)} and you'll be refunded.",
              style: charakHintStyle, textAlign: TextAlign.center),
        ],
      ]),
    );
  }
}

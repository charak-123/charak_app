import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

final _reliabilityProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return await ApiClient.instance.get('/doctors/me/reliability') as Map<String, dynamic>;
});

const _types = <String, String>{
  'doctor_no_show': 'Visit missed',
  'technical': 'Call problem',
  'doctor_reschedule': 'Visit moved',
  'doctor_late_cancel': 'Late cancellation',
  'other': 'Other problem',
};

/// The doctor's reliability (visits kept, last 90 days), kept apart from the
/// patients' rating, and every case about them: what was reported, what was
/// decided and why, and what they can do (respond, or appeal within 7 days).
/// Reports never count until our team confirms them.
class ReliabilityScreen extends ConsumerWidget {
  const ReliabilityScreen({super.key});

  Future<void> _write(BuildContext context, WidgetRef ref, String id, String action) async {
    final ctrl = TextEditingController();
    final appeal = action == 'appeal';
    final ok = await showCharakSheet<bool>(
      context,
      title: appeal ? 'Appeal this decision' : 'Tell us what happened',
      child: Builder(
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              appeal
                  ? 'Explain why it shouldn\'t count, with anything that shows it. A case can be appealed once.'
                  : 'Our team reads this before deciding. Stick to what happened; the patient doesn\'t see it.',
              style: charakHintStyle,
            ),
            const SizedBox(height: 12),
            CharakField(label: appeal ? 'Your appeal' : 'What happened', controller: ctrl,
                maxLines: 6, minLines: 3, textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: 14),
            CharakButton(label: appeal ? 'Send appeal' : 'Send', onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ApiClient.instance.post('/incidents/$id/$action', {'note': ctrl.text.trim()});
      ref.invalidate(_reliabilityProvider);
      if (context.mounted) showCharakToast(context, message: appeal ? 'Appeal sent' : 'Sent to our team');
    } on ApiException catch (e) {
      if (context.mounted) showCharakToast(context, message: e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_reliabilityProvider);
    return CharakScreen(
      title: 'Reliability',
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => CharakErrorState(error: e, onRetry: () => ref.invalidate(_reliabilityProvider)),
        data: (r) {
          final pct = (r['kept_pct'] as num?)?.toInt();
          final cases = List<Map<String, dynamic>>.from(r['cases'] as List? ?? const []);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_reliabilityProvider.future),
            color: CharakColors.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 4, CharakSpacing.gutter, 32),
              children: [
                CharakCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(pct == null ? '—' : '$pct%',
                        style: CharakText.titleLarge.tabular.copyWith(color: CharakColors.ink)),
                    Text(
                      pct == null
                          ? 'Not enough visits in the last 90 days yet'
                          : 'of visits kept · ${r['visits_kept']} went ahead, ${r['counted']} counted against you',
                      style: CharakText.caption.tabular.copyWith(color: CharakColors.inkMuted),
                    ),
                    const SizedBox(height: 10),
                    Text(r['explanation'] as String? ?? '', style: charakHintStyle),
                    const SizedBox(height: 6),
                    Text('Separate from your patients\' rating, which this never changes.', style: charakHintStyle),
                  ]),
                ),
                const SizedBox(height: 24),
                if (cases.isEmpty)
                  const CharakEmptyState(
                    icon: LucideIcons.shieldCheck,
                    title: 'No cases',
                    message: 'Problems patients report, and visits you move or cancel late, show here.',
                  )
                else ...[
                  const CharakSectionTitle(label: 'Cases'),
                  const SizedBox(height: 8),
                  for (final c in cases) ...[
                    _CaseTile(
                      c: c,
                      onRespond: () => _write(context, ref, c['id'] as String, 'respond'),
                      onAppeal: () => _write(context, ref, c['id'] as String, 'appeal'),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CaseTile extends StatelessWidget {
  final Map<String, dynamic> c;
  final VoidCallback onRespond;
  final VoidCallback onAppeal;
  const _CaseTile({required this.c, required this.onRespond, required this.onAppeal});

  @override
  Widget build(BuildContext context) {
    final status = c['status'] as String;
    final appeal = c['appeal_status'] as String? ?? 'none';
    final (tone, label) = switch ((status, appeal)) {
      (_, 'appealed') => (CharakStatusTone.review, 'Appeal under review'),
      (_, 'reversed') => (CharakStatusTone.confirmed, 'Reversed on appeal'),
      ('confirmed', _) when c['counts'] == true => (CharakStatusTone.declined, 'Counts'),
      ('confirmed', _) => (CharakStatusTone.muted, 'Not your fault'),
      ('dismissed', _) => (CharakStatusTone.confirmed, 'Dismissed'),
      ('undetermined', _) => (CharakStatusTone.muted, 'Undetermined'),
      _ => (CharakStatusTone.review, 'Being reviewed'),
    };
    final when = DateTime.tryParse(c['created_at'] as String? ?? '')?.toLocal();
    return CharakCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${_types[c['type']] ?? 'Case'} · ${c['case_ref']}',
                style: CharakText.body.weight(600).tabular.copyWith(color: CharakColors.ink)),
          ),
          CharakStatusPill(label: label, tone: tone),
        ]),
        if (when != null)
          Text(DateFormat('d MMM y, h:mm a').format(when),
              style: CharakText.caption.tabular.copyWith(color: CharakColors.inkMuted)),
        for (final (k, v) in [
          ('Decision', c['decision_reason']),
          ('You said', c['doctor_response']),
          ('Your appeal', c['appeal_note']),
          ('Appeal outcome', c['appeal_reason']),
        ])
          if (v is String && v.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(k.toUpperCase(), style: CharakText.overline.copyWith(color: CharakColors.inkMuted)),
            Text(v, style: CharakText.body.copyWith(color: CharakColors.ink)),
          ],
        if (c['can_respond'] == true) ...[
          const SizedBox(height: 12),
          CharakButton(label: 'Tell us what happened', variant: CharakButtonVariant.tonal, onPressed: onRespond),
        ],
        if (c['can_appeal'] == true) ...[
          const SizedBox(height: 12),
          CharakButton(label: 'Appeal', variant: CharakButtonVariant.outline, onPressed: onAppeal),
        ],
      ]),
    );
  }
}

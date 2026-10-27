import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import '../models/charak_prescription.dart';
import 'charak_controls.dart';

/// A prescription's content, as the patient reads it and as the doctor
/// reviews it before sending: findings, medicines, investigations, advice and
/// the follow-up. Flat 26px blocks on the ground, one per section, in the order
/// of the printed prescription (Telemedicine Practice Guidelines sample).
///
/// [followUpAction] sits under the follow-up (the patient's Book button);
/// leave it null on the doctor's review.
class CharakPrescriptionView extends StatelessWidget {
  final CharakPrescription prescription;
  final Widget? followUpAction;

  const CharakPrescriptionView({super.key, required this.prescription, this.followUpAction});

  @override
  Widget build(BuildContext context) {
    final rx = prescription;
    final findings = [
      if (rx.complaints != null) ('Complaints', rx.complaints!),
      if (rx.diagnosis != null) ('Provisional diagnosis', rx.diagnosis!),
    ];
    final blocks = <Widget>[
      if (findings.isNotEmpty)
        _Block(children: [
          for (final (label, text) in findings) _Labelled(label: label, text: text),
        ]),
      if (rx.isNotes)
        _Block(title: 'Consultation notes', children: [
          Text('No medicines prescribed.', style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
        ])
      else if (rx.items.isNotEmpty)
        _Block(title: 'Medicines', children: [
          for (var i = 0; i < rx.items.length; i++)
            CharakMedicineLine(medicine: rx.items[i], last: i == rx.items.length - 1),
        ]),
      if (rx.hasUpload)
        _Block(children: [
          CharakNoteBanner(
            icon: LucideIcons.fileImage,
            leadLabel: 'Handwritten prescription',
            message: ' attached. Open it from the buttons below.',
            tone: CharakStatusTone.primary,
          ),
        ]),
      if (rx.investigations != null)
        _Block(children: [_Labelled(label: 'Investigations', text: rx.investigations!)]),
      if (rx.advice != null) _Block(children: [_Labelled(label: 'Advice', text: rx.advice!)]),
      if (rx.followUp != null)
        _Block(title: 'Follow-up', children: [
          CharakFollowUpLine(followUp: rx.followUp!),
          if (followUpAction != null) ...[const SizedBox(height: 14), followUpAction!],
        ]),
    ];
    return CharakStaggerIn(
      children: [
        for (final b in blocks) Padding(padding: const EdgeInsets.only(bottom: 12), child: b),
      ],
    );
  }
}

/// One medicine: name and strength, then the schedule in narrow tabular
/// figures, then the form, route and the doctor's own instructions.
class CharakMedicineLine extends StatelessWidget {
  final CharakMedicine medicine;
  final bool last;
  final Widget? trailing;

  const CharakMedicineLine({super.key, required this.medicine, this.last = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final m = medicine;
    final detail = [m.formRoute, m.instructions].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: CharakColors.border)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 12),
          child: Icon(LucideIcons.pill, size: 18, color: CharakColors.primary),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.title, style: CharakText.body.weight(600).copyWith(color: CharakColors.ink)),
            if (m.schedule.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(m.schedule, style: CharakText.body.tabular.copyWith(color: CharakColors.ink)),
            ],
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(detail, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
            ],
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// "Around Thu 5 Nov · Home visit", and the doctor's note.
class CharakFollowUpLine extends StatelessWidget {
  final CharakFollowUp followUp;
  const CharakFollowUpLine({super.key, required this.followUp});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 12),
          child: Icon(LucideIcons.calendarClock, size: 18, color: CharakColors.primary),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Around ${DateFormat('EEE d MMM').format(followUp.date)}',
                style: CharakText.body.weight(600).tabular.copyWith(color: CharakColors.ink)),
            Text(followUp.channelLabel, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
            if (followUp.note != null) ...[
              const SizedBox(height: 6),
              Text(followUp.note!, style: CharakText.body.copyWith(color: CharakColors.ink)),
            ],
          ]),
        ),
      ]);
}

class _Block extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const _Block({this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 16, CharakSpacing.gutter, 16),
        decoration: BoxDecoration(
          color: CharakColors.card,
          borderRadius: const BorderRadius.all(CharakRadius.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) ...[CharakSectionTitle(label: title!), const SizedBox(height: 4)],
          ...children,
        ]),
      );
}

class _Labelled extends StatelessWidget {
  final String label;
  final String text;
  const _Labelled({required this.label, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: CharakText.overline.copyWith(color: CharakColors.inkMuted)),
          const SizedBox(height: 4),
          Text(text, style: CharakText.body.copyWith(color: CharakColors.ink)),
        ]),
      );
}

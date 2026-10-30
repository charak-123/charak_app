import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import 'charak_button.dart';
import 'charak_controls.dart';
import 'charak_sheet.dart';

/// Time picker as a sheet (V2): a readout up top, then the hour, the minutes
/// and AM/PM as taps. Everything is on screen at once, so nothing scrolls.
///
/// Material's time picker was used before. It nests its clock face inside two
/// scroll views, so on a phone the whole dialog slid about under the thumb
/// while you were trying to turn the dial, and it was a centred dialog, not a
/// sheet. Minutes come in quarter hours, which is how doctors keep hours; a
/// time saved off the quarter keeps its own minute as a fifth choice.
///
/// Returns null when dismissed.
Future<TimeOfDay?> showCharakTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
  String title = 'Choose a time',
  String confirmLabel = 'Set time',
}) async {
  final range = await showCharakSheet<(TimeOfDay, TimeOfDay?)>(
    context,
    title: title,
    child: CharakTimeRangePicker(start: initial, confirmLabel: confirmLabel),
  );
  return range?.$1;
}

/// From and to in one sheet: tap "From" or "To", then set it below. Opens on
/// the times passed in, which is what a doctor changing their hours expects
/// to see. Confirm stays off until the end is after the start; moving the
/// start past the end carries the end along an hour later.
///
/// Returns `(start, end)`, or null when dismissed.
///
/// [editEnd] opens with "To" selected, for a field the person tapped "To" on.
Future<(TimeOfDay, TimeOfDay)?> showCharakTimeRangePicker(
  BuildContext context, {
  required TimeOfDay start,
  required TimeOfDay end,
  String title = 'Choose hours',
  String confirmLabel = 'Set hours',
  bool editEnd = false,
}) async {
  final range = await showCharakSheet<(TimeOfDay, TimeOfDay?)>(
    context,
    title: title,
    child: CharakTimeRangePicker(start: start, end: end, confirmLabel: confirmLabel, editEnd: editEnd),
  );
  if (range == null || range.$2 == null) return null;
  return (range.$1, range.$2!);
}

/// The body of [showCharakTimePicker] (no [end]) and
/// [showCharakTimeRangePicker]. Pops `(start, end)`; end is null for a single
/// time.
class CharakTimeRangePicker extends StatefulWidget {
  final TimeOfDay start;
  final TimeOfDay? end;
  final String confirmLabel;

  /// Called with the choice instead of popping it (the gallery).
  final void Function(TimeOfDay start, TimeOfDay? end)? onConfirm;

  /// Start on "To" rather than "From" (range only).
  final bool editEnd;

  const CharakTimeRangePicker({
    super.key,
    required this.start,
    this.end,
    this.confirmLabel = 'Set time',
    this.onConfirm,
    this.editEnd = false,
  });

  @override
  State<CharakTimeRangePicker> createState() => _CharakTimeRangePickerState();
}

class _CharakTimeRangePickerState extends State<CharakTimeRangePicker> {
  late TimeOfDay _start = widget.start;
  late TimeOfDay? _end = widget.end;
  late bool _editingEnd = widget.editEnd && widget.end != null;

  bool get _isRange => widget.end != null;
  TimeOfDay get _value => _editingEnd ? _end! : _start;

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;
  bool get _valid => !_isRange || _minutes(_end!) > _minutes(_start);

  void _set(TimeOfDay t) => setState(() {
        if (_editingEnd) {
          _end = t;
          return;
        }
        final before = _start;
        _start = t;
        // Keep the hours valid while the start moves: an end it overtakes
        // follows it, an hour later, as long as that is still today.
        if (_isRange && _minutes(_end!) <= _minutes(t)) {
          final carried = _minutes(t) + (_minutes(_end!) - _minutes(before)).clamp(60, 24 * 60);
          if (carried < 24 * 60) _end = TimeOfDay(hour: carried ~/ 60, minute: carried % 60);
        }
      });

  void _setHour12(int h12) {
    final pm = _value.period == DayPeriod.pm;
    _set(_value.replacing(hour: (h12 % 12) + (pm ? 12 : 0)));
  }

  void _setPeriod(DayPeriod p) {
    if (p == _value.period) return;
    _set(_value.replacing(hour: (_value.hour + 12) % 24));
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final h12 = v.hourOfPeriod == 0 ? 12 : v.hourOfPeriod;
    final minutes = {0, 15, 30, 45, v.minute}.toList()..sort();

    // Fits a phone with room to spare, so nothing moves under the thumb. The
    // scroll view only matters on a screen too short for it (a split screen,
    // very large text), where it beats an overflow.
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        if (_isRange)
          Row(children: [
            Expanded(
              child: _Readout(
                label: 'From',
                time: _start,
                selected: !_editingEnd,
                onTap: () => setState(() => _editingEnd = false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Readout(
                label: 'To',
                time: _end!,
                selected: _editingEnd,
                error: !_valid,
                onTap: () => setState(() => _editingEnd = true),
              ),
            ),
          ])
        else
          _Readout(label: 'Time', time: _start, selected: true),
        const SizedBox(height: 18),
        _Label(_isRange ? (_editingEnd ? 'Ends at · hour' : 'Starts at · hour') : 'Hour'),
        const SizedBox(height: 8),
        for (final row in const [
          [12, 1, 2, 3, 4, 5],
          [6, 7, 8, 9, 10, 11],
        ]) ...[
          Row(children: [
            for (final (i, h) in row.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _Cell(
                  label: '$h',
                  selected: h == h12,
                  semantics: '$h o\'clock',
                  onTap: () => _setHour12(h),
                ),
              ),
            ],
          ]),
          if (row.first == 12) const SizedBox(height: 6),
        ],
        const SizedBox(height: 16),
        const _Label('Minutes'),
        const SizedBox(height: 8),
        Row(children: [
          for (final (i, m) in minutes.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _Cell(
                label: ':${m.toString().padLeft(2, '0')}',
                selected: m == v.minute,
                semantics: '$m minutes',
                onTap: () => _set(v.replacing(minute: m)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        CharakSegmented<DayPeriod>(
          segments: const [
            CharakSegment(value: DayPeriod.am, label: 'AM'),
            CharakSegment(value: DayPeriod.pm, label: 'PM'),
          ],
          value: v.period,
          onChanged: _setPeriod,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 18,
          child: !_valid
              ? Text('The end has to be after the start.',
                  textAlign: TextAlign.center,
                  style: CharakText.caption.copyWith(color: CharakColors.danger))
              : null,
        ),
        const SizedBox(height: 6),
        CharakButton(
          label: widget.confirmLabel,
          onPressed: !_valid
              ? null
              : () => widget.onConfirm != null
                  ? widget.onConfirm!(_start, _end)
                  : Navigator.of(context).pop((_start, _end)),
        ),
      ],
      ),
    );
  }
}

/// "9:30 AM" in tabular figures.
String charakTimeLabel(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
}

class _Readout extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final bool selected;
  final bool error;
  final VoidCallback? onTap;

  const _Readout({
    required this.label,
    required this.time,
    required this.selected,
    this.error = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = error
        ? CharakColors.danger
        : (selected && onTap != null ? CharakColors.primary : Colors.transparent);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$label ${charakTimeLabel(time)}',
      child: CharakPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: charakReduceMotion(context) ? Duration.zero : CharakMotion.standard,
          curve: CharakCurves.standard,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: selected ? CharakColors.primarySoft : CharakColors.bgSubtle,
            border: Border.all(color: border, width: 2),
            borderRadius: const BorderRadius.all(CharakRadius.tile),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: onTap == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text(label, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                const SizedBox(height: 2),
                Text(
                  charakTimeLabel(time),
                  style: CharakText.titleMedium.tabular.copyWith(
                    color: selected ? CharakColors.primaryDeep : CharakColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final bool selected;
  final String semantics;
  final VoidCallback onTap;

  const _Cell({
    required this.label,
    required this.selected,
    required this.semantics,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: semantics,
        excludeSemantics: true,
        child: CharakPressable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: charakReduceMotion(context) ? Duration.zero : CharakMotion.standard,
            curve: CharakCurves.standard,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? CharakColors.primary : CharakColors.card,
              border: Border.all(
                color: selected ? Colors.transparent : CharakColors.borderStrong,
                width: 1.5,
              ),
              borderRadius: const BorderRadius.all(CharakRadius.pill),
            ),
            child: Text(
              label,
              style: CharakText.label.tabular.copyWith(
                color: selected ? CharakColors.onPrimary : CharakColors.ink,
              ),
            ),
          ),
        ),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: CharakText.caption.weight(600).copyWith(color: CharakColors.inkMuted));
}

import 'package:flutter/material.dart';
import 'package:charak_core/charak_core.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class ScheduleBlock {
  int dayOfWeek;
  TimeOfDay start;
  TimeOfDay end;
  ScheduleBlock({required this.dayOfWeek, required this.start, required this.end});

  Map<String, dynamic> toJson() => {
    'day_of_week': dayOfWeek,
    'start_time': '${start.hour.toString().padLeft(2,'0')}:${start.minute.toString().padLeft(2,'0')}',
    'end_time':   '${end.hour.toString().padLeft(2,'0')}:${end.minute.toString().padLeft(2,'0')}',
  };
}

class ScheduleEditor extends StatefulWidget {
  final List<ScheduleBlock> blocks;
  final ValueChanged<List<ScheduleBlock>> onChanged;

  const ScheduleEditor({super.key, required this.blocks, required this.onChanged});

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late List<ScheduleBlock> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = List.from(widget.blocks);
  }

  void _add(int dayIndex) async {
    final start = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (start == null || !mounted) return;
    final end = await showTimePicker(context: context, initialTime: TimeOfDay(hour: start.hour + 2, minute: 0));
    if (end == null) return;
    setState(() => _blocks.add(ScheduleBlock(dayOfWeek: dayIndex, start: start, end: end)));
    widget.onChanged(_blocks);
  }

  void _remove(ScheduleBlock b) {
    setState(() => _blocks.remove(b));
    widget.onChanged(_blocks);
  }

  String _fmt(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(7, (i) {
        final dayBlocks = _blocks.where((b) => b.dayOfWeek == i).toList();
        // `.day-row` — 11px vertical padding, hairline divider except the last.
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: i == 6
                ? null
                : const Border(bottom: BorderSide(color: CharakColors.border)),
          ),
          child: Row(
            children: [
              // `.day` — 34px column; muted/500 when the day has no hours.
              SizedBox(
                width: 34,
                child: Text(
                  _days[i],
                  style: TextStyle(
                    fontFamily: CharakText.fontFamily,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: dayBlocks.isEmpty ? FontWeight.w500 : FontWeight.w600,
                    color: dayBlocks.isEmpty ? CharakColors.inkMuted : CharakColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // `.block-chips` — wrapping 6px grid that takes the free space.
              Expanded(
                child: dayBlocks.isEmpty
                    ? const Text(
                        'No hours',
                        style: TextStyle(
                          fontFamily: CharakText.fontFamily,
                          fontSize: 12.5,
                          height: 1.4,
                          color: CharakColors.inkMuted,
                        ),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: dayBlocks
                            .map((b) => _BlockChip(
                                  label: '${_fmt(b.start)}–${_fmt(b.end)}',
                                  onRemove: () => _remove(b),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(width: 10),
              _BlockAdd(onTap: () => _add(i)),
            ],
          ),
        );
      }),
    );
  }
}

/// `.block-chip` — primarySoft pill, 12px/500 primaryDeep label, 11px dismiss.
class _BlockChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _BlockChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: const BoxDecoration(
      color: CharakColors.primarySoft,
      borderRadius: BorderRadius.all(CharakRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: CharakText.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.3,
            color: CharakColors.primaryDeep,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 5),
        GestureDetector(
          onTap: onRemove,
          child: const Icon(Icons.close, size: 11, color: CharakColors.primaryDeep),
        ),
      ],
    ),
  );
}

/// `.block-add` — 30px dashed square with a 14px plus.
class _BlockAdd extends StatelessWidget {
  final VoidCallback onTap;
  const _BlockAdd({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: CustomPaint(
      painter: CharakDashedBorderPainter(
        color: CharakColors.border,
        dashed: true,
        radius: 8,
        strokeWidth: 1,
      ),
      child: const SizedBox(
        width: 30,
        height: 30,
        child: Icon(Icons.add, size: 14, color: CharakColors.inkMuted),
      ),
    ),
  );
}

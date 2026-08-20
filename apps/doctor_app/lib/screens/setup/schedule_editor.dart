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
        return Padding(
          padding: const EdgeInsets.only(bottom: CharakSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Text(_days[i], style: CharakText.caption.copyWith(color: CharakColors.ink, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: CharakSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...dayBlocks.map((b) => Padding(
                      padding: const EdgeInsets.only(bottom: CharakSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: CharakColors.primarySoft,
                                borderRadius: BorderRadius.all(CharakRadius.pill),
                              ),
                              child: Text('${_fmt(b.start)} – ${_fmt(b.end)}',
                                  style: CharakText.caption.copyWith(color: CharakColors.primaryDeep)),
                            ),
                          ),
                          const SizedBox(width: CharakSpacing.xs),
                          GestureDetector(
                            onTap: () => _remove(b),
                            child: const Icon(Icons.close, size: 16, color: CharakColors.inkMuted),
                          ),
                        ],
                      ),
                    )),
                    GestureDetector(
                      onTap: () => _add(i),
                      child: Text('+ Add block',
                          style: CharakText.caption.copyWith(color: CharakColors.primary,
                              decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

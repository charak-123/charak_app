import 'package:flutter/material.dart';
import 'package:charak_core/charak_core.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class ScheduleBlock {
  int dayOfWeek;
  TimeOfDay start;
  TimeOfDay end;
  ScheduleBlock({required this.dayOfWeek, required this.start, required this.end});

  /// A row of GET /schedules/me ("09:00:00" or "09:00").
  factory ScheduleBlock.fromJson(Map<String, dynamic> j) => ScheduleBlock(
        dayOfWeek: j['day_of_week'] as int,
        start: _parse(j['start_time'] as String),
        end: _parse(j['end_time'] as String),
      );

  static TimeOfDay _parse(String t) {
    final p = t.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  Map<String, dynamic> toJson() => {
    'day_of_week': dayOfWeek,
    'start_time': '${start.hour.toString().padLeft(2,'0')}:${start.minute.toString().padLeft(2,'0')}',
    'end_time':   '${end.hour.toString().padLeft(2,'0')}:${end.minute.toString().padLeft(2,'0')}',
  };

  int get _from => start.hour * 60 + start.minute;
  int get _to => end.hour * 60 + end.minute;
  bool overlaps(ScheduleBlock o) => o.dayOfWeek == dayOfWeek && o._from < _to && _from < o._to;
}

/// The doctor's saved hours for one channel, for the editors to open on.
Future<List<ScheduleBlock>> loadScheduleBlocks(String channel) async {
  final rows = await ApiClient.instance.get('/schedules/me?channel=$channel') as List;
  return [for (final r in rows) ScheduleBlock.fromJson(Map<String, dynamic>.from(r as Map))];
}

/// "Mon–Fri 9:00 AM–1:00 PM · Sat 10:00 AM–12:00 PM", for Profile.
String? summariseSchedule(List<ScheduleBlock> blocks) {
  if (blocks.isEmpty) return null;
  final byHours = <String, List<int>>{};
  for (final b in [...blocks]..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek))) {
    final hours = '${charakTimeLabel(b.start)}–${charakTimeLabel(b.end)}';
    (byHours[hours] ??= []).add(b.dayOfWeek);
  }
  String days(List<int> d) {
    final u = d.toSet().toList()..sort();
    final run = u.length > 2 && u.last - u.first == u.length - 1;
    return run ? '${_days[u.first]}–${_days[u.last]}' : u.map((i) => _days[i]).join(', ');
  }
  return byHours.entries.map((e) => '${days(e.value)} ${e.key}').join(' · ');
}

/// Weekly hours, one row per day. Tap a block to change it (the sheet opens
/// on its current times), × to remove it, + to add one. Holds no state of its
/// own: the screen owns [blocks], so hours loaded after the first frame show.
class ScheduleEditor extends StatelessWidget {
  final List<ScheduleBlock> blocks;
  final ValueChanged<List<ScheduleBlock>> onChanged;

  const ScheduleEditor({super.key, required this.blocks, required this.onChanged});

  Future<void> _edit(BuildContext context, int dayIndex, [ScheduleBlock? existing]) async {
    final dayBlocks = blocks.where((b) => b.dayOfWeek == dayIndex).toList()
      ..sort((a, b) => a._from.compareTo(b._from));
    // A new block starts where the day's last one ends, so "add another"
    // offers the free time rather than 9 AM again.
    final from = existing?.start ??
        (dayBlocks.isEmpty ? const TimeOfDay(hour: 9, minute: 0) : dayBlocks.last.end);
    final defaultEnd = (from.hour * 60 + from.minute + 120).clamp(0, 23 * 60 + 45);
    final to = existing?.end ?? TimeOfDay(hour: defaultEnd ~/ 60, minute: defaultEnd % 60);

    final picked = await showCharakTimeRangePicker(
      context,
      title: '${_days[dayIndex]} hours',
      start: from,
      end: to,
      confirmLabel: existing == null ? 'Add hours' : 'Save hours',
    );
    if (picked == null || !context.mounted) return;

    final block = ScheduleBlock(dayOfWeek: dayIndex, start: picked.$1, end: picked.$2);
    final clash = blocks.where((b) => !identical(b, existing) && b.overlaps(block)).firstOrNull;
    if (clash != null) {
      showCharakToast(context,
          message: 'Overlaps ${charakTimeLabel(clash.start)}–${charakTimeLabel(clash.end)} on ${_days[dayIndex]}',
          isError: true);
      return;
    }
    onChanged([
      for (final b in blocks)
        if (!identical(b, existing)) b,
      block,
    ]);
  }

  void _remove(ScheduleBlock b) => onChanged([for (final x in blocks) if (!identical(x, b)) x]);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(7, (i) {
        final dayBlocks = blocks.where((b) => b.dayOfWeek == i).toList()
          ..sort((a, b) => a._from.compareTo(b._from));
        // `.day-row` — 11px vertical padding, hairline divider except the last.
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: i == 6
                ? null
                : Border(bottom: BorderSide(color: CharakColors.border)),
          ),
          child: Row(
            children: [
              // `.day` — 34px column; muted/500 when the day has no hours.
              SizedBox(
                width: 34,
                child: Text(
                  _days[i],
                  style: CharakText.caption.copyWith(color: dayBlocks.isEmpty ? CharakColors.inkMuted : CharakColors.ink, fontWeight: dayBlocks.isEmpty ? FontWeight.w500 : FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              // `.block-chips` — wrapping 6px grid that takes the free space.
              Expanded(
                child: dayBlocks.isEmpty
                    ? Text(
                        'No hours',
                        style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: dayBlocks
                            .map((b) => _BlockChip(
                                  label: '${charakTimeLabel(b.start)}–${charakTimeLabel(b.end)}',
                                  onTap: () => _edit(context, i, b),
                                  onRemove: () => _remove(b),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(width: 10),
              _BlockAdd(onTap: () => _edit(context, i)),
            ],
          ),
        );
      }),
    );
  }
}

/// `.block-chip` — primarySoft pill, 12px/500 primaryDeep label. Tapping the
/// label edits the block; the × has its own 32px target so a slip doesn't
/// delete hours.
class _BlockChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _BlockChip({required this.label, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: CharakColors.primarySoft,
      borderRadius: const BorderRadius.all(CharakRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Change $label',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 2, 7),
              child: Text(
                label,
                style: CharakText.caption.tabular.copyWith(color: CharakColors.primaryDeep, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Remove $label',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: SizedBox(
              width: 28,
              height: 30,
              child: Icon(LucideIcons.x, size: 12, color: CharakColors.primaryDeep),
            ),
          ),
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add hours',
    child: GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: CharakDashedBorderPainter(
          color: CharakColors.border,
          dashed: true,
          radius: 8,
          strokeWidth: 1,
        ),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(LucideIcons.plus, size: 14, color: CharakColors.inkMuted),
        ),
      ),
    ),
  );
}

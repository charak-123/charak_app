import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:charak_core/charak_core.dart';
// intl is a direct dependency; don't rely on shadcn_ui re-exporting DateFormat.
// ignore: unnecessary_import
import 'package:intl/intl.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _slotsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, from) async {
  final res = await ApiClient.instance.get('/schedules/me/slots?from_date=$from');
  return res as Map<String, dynamic>;
});

final _activeBookingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/bookings/doctor/active');
  return List<Map<String, dynamic>>.from(res as List);
});

final _blocksProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/slot-blocks/me');
  return List<Map<String, dynamic>>.from(res as List);
});

// ── One agenda row on the selected day ──────────────────────────────────────

enum _RowKind { booked, home, open, blocked }

class _AgendaRow {
  final String time; // "09:00"
  final _RowKind kind;
  final String title;
  final String subtitle;
  _AgendaRow({required this.time, required this.kind, required this.title, required this.subtitle});
}

class ScheduleTab extends ConsumerStatefulWidget {
  const ScheduleTab({super.key});

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<ScheduleTab> {
  late DateTime _weekStart;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  String get _fromKey => DateFormat('yyyy-MM-dd').format(_weekStart);

  Future<void> _blockSheet() async {
    DateTime chosen = _selectedDay;
    TimeOfDay from = const TimeOfDay(hour: 16, minute: 0);
    TimeOfDay to   = const TimeOfDay(hour: 17, minute: 0);

    await showCharakSheet<void>(
      context,
      title: 'Block a time slot',
      child: StatefulBuilder(builder: (ctx, setSheetState) {
        Widget dateChip(DateTime d, String label) {
          final on = DateFormat('yyyy-MM-dd').format(d) == DateFormat('yyyy-MM-dd').format(chosen);
          return GestureDetector(
            onTap: () => setSheetState(() => chosen = d),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: on ? CharakColors.ink : CharakColors.bgSubtle,
                borderRadius: const BorderRadius.all(CharakRadius.pill),
              ),
              child: Text(label, style: CharakText.caption.copyWith(color: on ? Colors.white : CharakColors.ink)),
            ),
          );
        }

        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text('One-off unavailability — your weekly template stays untouched.',
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
            const SizedBox(height: 14),
            Row(children: [
              dateChip(DateTime.now(), 'Today'),
              dateChip(DateTime.now().add(const Duration(days: 1)), 'Tomorrow'),
              dateChip(DateTime.now().add(const Duration(days: 2)),
                  DateFormat('EEE').format(DateTime.now().add(const Duration(days: 2)))),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _TimeField(label: 'From', value: from,
                  onTap: () async {
                    final t = await showTimePicker(context: ctx, initialTime: from);
                    if (t != null) setSheetState(() => from = t);
                  })),
              const SizedBox(width: 12),
              Expanded(child: _TimeField(label: 'To', value: to,
                  onTap: () async {
                    final t = await showTimePicker(context: ctx, initialTime: to);
                    if (t != null) setSheetState(() => to = t);
                  })),
            ]),
            const SizedBox(height: 18),
            CharakButton(
              label: 'Block slot',
              onPressed: () async {
                try {
                  await ApiClient.instance.post('/slot-blocks/me', {
                    'date': DateFormat('yyyy-MM-dd').format(chosen),
                    'start_time': '${from.hour.toString().padLeft(2, '0')}:${from.minute.toString().padLeft(2, '0')}',
                    'end_time': '${to.hour.toString().padLeft(2, '0')}:${to.minute.toString().padLeft(2, '0')}',
                  });
                  ref.invalidate(_blocksProvider);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } on ApiException catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
                    );
                  }
                }
              },
            ),
          ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slotsAsync   = ref.watch(_slotsProvider(_fromKey));
    final bookingsAsync = ref.watch(_activeBookingsProvider);
    final blocksAsync  = ref.watch(_blocksProvider);

    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            // `.sched-head` — 22px title with a compact 38px auto-width action.
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Schedule', style: CharakText.h1),
                  _CompactGhostButton(label: 'Block time', onPressed: _blockSheet),
                ],
              ),
            ),
            _DayStrip(
              weekStart: _weekStart,
              selected: _selectedDay,
              onSelect: (d) => setState(() => _selectedDay = d),
            ),
            const SizedBox(height: 16),
            CharakSectionTitle(
              label: DateFormat('yyyy-MM-dd').format(_selectedDay) ==
                      DateFormat('yyyy-MM-dd').format(DateTime.now())
                  ? 'Today, ${DateFormat('EEEE').format(_selectedDay)}'
                  : DateFormat('EEEE, d MMM').format(_selectedDay),
            ),
            const SizedBox(height: 9),
            slotsAsync.when(
              loading: () => const _AgendaSkeleton(),
              error: (e, _) => Text('Failed to load schedule', style: CharakText.body.copyWith(color: CharakColors.danger)),
              data: (slots) => bookingsAsync.when(
                loading: () => const _AgendaSkeleton(),
                error: (e, _) => Text('Failed to load bookings', style: CharakText.body.copyWith(color: CharakColors.danger)),
                data: (bookings) => blocksAsync.when(
                  loading: () => const _AgendaSkeleton(),
                  error: (e, _) => Text('Failed to load blocks', style: CharakText.body.copyWith(color: CharakColors.danger)),
                  data: (blocks) {
                    final rows = _buildAgenda(slots, bookings, blocks);
                    if (rows.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text('No hours set for this day',
                            style: CharakText.body.copyWith(color: CharakColors.inkMuted))),
                      );
                    }
                    return Column(children: rows.map((r) => _SlotRow(row: r)).toList());
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_AgendaRow> _buildAgenda(
    Map<String, dynamic> slots,
    List<Map<String, dynamic>> bookings,
    List<Map<String, dynamic>> blocks,
  ) {
    final dayKey = DateFormat('yyyy-MM-dd').format(_selectedDay);
    final rows = <_AgendaRow>[];

    final daySlots = List<Map<String, dynamic>>.from(slots[dayKey] as List? ?? []);
    for (final s in daySlots) {
      rows.add(_AgendaRow(time: s['start'] as String, kind: _RowKind.open, title: 'Open slot', subtitle: 'Bookable by patients'));
    }

    for (final b in bookings) {
      final start = b['scheduled_start'] as String? ?? '';
      final dt = DateTime.tryParse(start)?.toLocal();
      if (dt == null || DateFormat('yyyy-MM-dd').format(dt) != dayKey) continue;
      final isHome = b['channel'] == 'home_visit';
      final patient = (b['users'] as Map?)?['name'] as String? ?? 'Patient';
      final price = (b['price_confirmed'] as num?)?.toStringAsFixed(0);
      rows.add(_AgendaRow(
        time: DateFormat('HH:mm').format(dt),
        kind: isHome ? _RowKind.home : _RowKind.booked,
        title: isHome ? 'Home Visit' : 'Online Consult',
        subtitle: price != null ? '$patient · ₹$price' : patient,
      ));
    }

    for (final b in blocks) {
      if (b['date'] != dayKey) continue;
      rows.add(_AgendaRow(
        time: (b['start_time'] as String? ?? '').substring(0, 5),
        kind: _RowKind.blocked,
        title: 'Blocked',
        subtitle: '${b['start_time']}–${b['end_time']}',
      ));
    }

    rows.sort((a, b) => a.time.compareTo(b.time));
    return rows;
  }
}

/// `.skel` stand-in for the day's agenda: four `.slot-row`-shaped blocks on
/// the row's 9px gutter. The `.week-strip` above it stays live, so only the
/// list area shimmers.
class _AgendaSkeleton extends StatelessWidget {
  const _AgendaSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      4,
      (_) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(CharakRadius.card),
          border: Border.all(color: CharakColors.border),
        ),
        child: const Row(children: [
          SizedBox(width: 54, child: CharakSkeleton(width: 40, height: 13)),
          SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CharakSkeleton(width: 104, height: 13.5),
              SizedBox(height: 5),
              CharakSkeleton(width: 140, height: 12),
            ]),
          ),
          SizedBox(width: 10),
          CharakSkeleton(width: 46, height: 10.5),
        ]),
      ),
    ),
  );
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;
  const _TimeField({required this.label, required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // `.field label` — 13px/600, 7px gap above a `.input`-shaped control.
      Text(label, style: CharakText.caption.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 7),
      Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: CharakColors.bg,
          borderRadius: const BorderRadius.all(CharakRadius.button),
          border: Border.all(color: CharakColors.border),
        ),
        child: Text(value.format(context),
            style: CharakText.body.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    ]),
  );
}

/// `.week-strip` / `.wday` — seven equal cells on a 6px grid; the selected
/// day inverts to the ink fill with white type.
class _DayStrip extends StatelessWidget {
  final DateTime weekStart;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _DayStrip({required this.weekStart, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 7; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: _buildDay(weekStart.add(Duration(days: i)))),
      ],
    ],
  );

  Widget _buildDay(DateTime d) {
    final on = DateFormat('yyyy-MM-dd').format(d) == DateFormat('yyyy-MM-dd').format(selected);
    return GestureDetector(
      onTap: () => onSelect(d),
      child: AnimatedContainer(
        duration: CharakDurations.buttonPress,
        padding: const EdgeInsets.only(top: 8, bottom: 7),
        decoration: BoxDecoration(
          color: on ? CharakColors.ink : CharakColors.bgSubtle,
          borderRadius: const BorderRadius.all(CharakRadius.button),
        ),
        child: Column(
          children: [
            // `.wday .d` — 10.5px/500
            Text(
              DateFormat('EE').format(d).substring(0, 2),
              style: TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: on ? Colors.white : CharakColors.inkMuted,
              ),
            ),
            const SizedBox(height: 1),
            // `.wday .n` — 13.5px/600 tabular
            Text(
              d.day.toString(),
              style: TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: on ? Colors.white : CharakColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.sched-head .btn` — the ghost button shrunk to 38px tall / 13px, sized to
/// its label rather than stretched full width.
class _CompactGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _CompactGhostButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(CharakRadius.button),
      side: BorderSide(color: CharakColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: CharakText.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: CharakColors.ink,
          ),
        ),
      ),
    ),
  );
}

/// `.slot-row` — a 54px / 1fr / auto grid with the four state variants:
/// `.booked` (primarySoft, primaryDeep status), `.home` (10%-success wash,
/// success status), `.open` (dashed border, muted status) and `.blocked`
/// (the whole row dimmed to 0.6, danger status).
class _SlotRow extends StatelessWidget {
  final _AgendaRow row;
  const _SlotRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final (bg, borderColor, dashed, statusLabel, statusColor) = switch (row.kind) {
      _RowKind.booked =>
        (CharakColors.primarySoft, Colors.transparent, false, 'Booked', CharakColors.primaryDeep),
      // `.slot-row.home` — rgba(31,170,109,0.1), keeping the default hairline.
      _RowKind.home =>
        (const Color(0x1A1FAA6D), CharakColors.border, false, 'Booked', CharakColors.success),
      _RowKind.open =>
        (CharakColors.bg, CharakColors.border, true, 'Open', CharakColors.inkMuted),
      _RowKind.blocked =>
        (CharakColors.bg, CharakColors.border, false, 'Blocked', CharakColors.danger),
    };

    final body = Row(
        children: [
          // `.slot-row .t` — 54px tabular time column.
          SizedBox(
            width: 54,
            child: Text(
              row.time,
              style: const TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: CharakColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // `.tt` / `.ts`
                Text(row.title,
                    style: CharakText.h2.copyWith(fontSize: 13.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(
                  row.subtitle,
                  style: const TextStyle(
                    fontFamily: CharakText.fontFamily,
                    fontSize: 12,
                    height: 1.4,
                    color: CharakColors.inkMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // `.st` — 10.5px/600 uppercase, 0.05em.
          Text(
            statusLabel.toUpperCase(),
            style: TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
              letterSpacing: 10.5 * 0.05,
              color: statusColor,
            ),
          ),
        ],
      );

    // `.slot-row.open` has no solid border — Flutter needs a painter for the
    // dashed one. Either way the row keeps its 9px bottom gutter.
    const inset = EdgeInsets.symmetric(horizontal: 13, vertical: 11);
    final framed = Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: dashed
          ? CustomPaint(
              painter: CharakDashedBorderPainter(
                color: CharakColors.border,
                dashed: true,
                radius: 12,
                strokeWidth: 1,
              ),
              child: Padding(padding: inset, child: body),
            )
          : Container(
              padding: inset,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.all(CharakRadius.card),
                border: Border.all(color: borderColor),
              ),
              child: body,
            ),
    );

    // `.slot-row.blocked { opacity: 0.6 }`
    return row.kind == _RowKind.blocked ? Opacity(opacity: 0.6, child: framed) : framed;
  }
}

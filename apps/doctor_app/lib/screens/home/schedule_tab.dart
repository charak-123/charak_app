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
        Widget dateChip(DateTime d, String label) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CharakChip(
                label: label,
                selected: DateUtils.isSameDay(d, chosen),
                onTap: () => setSheetState(() => chosen = d),
              ),
            );

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
                      SnackBar(content: Text(e.message), backgroundColor: CharakPalette.statusDeclined),
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

    return CharakLargeTitleScaffold(
      title: 'Schedule',
      subtitle: DateFormat('MMMM yyyy').format(_selectedDay),
      actions: [
        CharakButton(
          label: 'Block time',
          icon: Icons.block_rounded,
          variant: CharakButtonVariant.tonal,
          compact: true,
          expand: false,
          onPressed: _blockSheet,
        ),
      ],
      children: [
        _DayStrip(
          weekStart: _weekStart,
          selected: _selectedDay,
          onSelect: (d) => setState(() => _selectedDay = d),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 10),
          child: CharakSectionTitle(
            label: DateFormat('yyyy-MM-dd').format(_selectedDay) ==
                    DateFormat('yyyy-MM-dd').format(DateTime.now())
                ? 'Today, ${DateFormat('EEEE').format(_selectedDay)}'
                : DateFormat('EEEE, d MMM').format(_selectedDay),
          ),
        ),
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
                  return const CharakEmptyState(
                    icon: Icons.event_available_outlined,
                    title: 'No hours set for this day',
                    message: 'Set your consult hours in Profile → Channels & hours.',
                  );
                }
                return Column(children: rows.map((r) => _SlotRow(row: r)).toList());
              },
            ),
          ),
        ),
      ],
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
        color: CharakColors.card,
          borderRadius: const BorderRadius.all(CharakRadius.card),
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
  Widget build(BuildContext context) => CharakPressable(
    onTap: onTap,
    child: Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: CharakColors.card,
        borderRadius: const BorderRadius.all(CharakRadius.input),
        border: Border.all(color: CharakColors.borderStrong, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: CharakText.caption.weight(600).copyWith(color: CharakColors.inkMuted)),
        Text(value.format(context), style: CharakText.bodyLarge.tabular.copyWith(color: CharakColors.ink)),
      ]),
    ),
  );
}

/// Week strip: seven day pills. The chosen day fills blue (motion.standard)
/// and pops once so it's clear the choice landed.
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
    final on = DateUtils.isSameDay(d, selected);
    final fg = on ? CharakColors.onPrimary : CharakColors.ink;
    return CharakPressable(
      onTap: () => onSelect(d),
      child: AnimatedScale(
        scale: on ? 1.0 : 0.97,
        duration: CharakMotion.standard,
        curve: CharakCurves.emphasized,
        child: AnimatedContainer(
          duration: CharakMotion.standard,
          curve: CharakCurves.standard,
          height: 64,
          decoration: BoxDecoration(
            color: on ? CharakColors.primary : CharakColors.card,
            borderRadius: const BorderRadius.all(CharakRadius.tile),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(DateFormat('EEE').format(d),
                  style: CharakText.caption.copyWith(
                      color: on ? CharakPalette.blue100 : CharakColors.inkMuted)),
              const SizedBox(height: 2),
              Text('${d.day}', style: CharakText.numeric.copyWith(fontSize: 19, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Agenda row. Each state owns one status colour: booked online = Accepted
/// blue, booked home visit = Confirmed sage, open = dashed outline, blocked =
/// Declined red on a 50% row (it recedes without jumping).
class _SlotRow extends StatelessWidget {
  final _AgendaRow row;
  const _SlotRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final (tone, statusLabel) = switch (row.kind) {
      _RowKind.booked => (CharakStatusTone.accepted, 'Booked'),
      _RowKind.home => (CharakStatusTone.confirmed, 'Home visit'),
      _RowKind.open => (CharakStatusTone.muted, 'Open'),
      _RowKind.blocked => (CharakStatusTone.declined, 'Blocked'),
    };
    final dashed = row.kind == _RowKind.open;
    final (soft, _) = charakToneColors(tone);
    final bg = switch (row.kind) {
      _RowKind.booked || _RowKind.home => soft,
      _ => CharakColors.card,
    };

    final body = Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(row.time, style: CharakText.numeric.copyWith(fontSize: 17, color: CharakColors.ink)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.title,
                  style: CharakText.body.weight(600).copyWith(color: CharakColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(row.subtitle,
                  style: CharakText.caption.tabular.copyWith(color: CharakColors.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 10),
        CharakStatusPill(label: statusLabel, tone: tone),
      ],
    );

    const inset = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    final framed = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: dashed
          ? CustomPaint(
              painter: CharakDashedBorderPainter(
                color: CharakColors.borderStrong,
                dashed: true,
                radius: CharakRadii.tile,
              ),
              child: Padding(padding: inset, child: body),
            )
          : Container(
              padding: inset,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.all(CharakRadius.tile),
              ),
              child: body,
            ),
    );

    return row.kind == _RowKind.blocked ? Opacity(opacity: 0.5, child: framed) : framed;
  }
}

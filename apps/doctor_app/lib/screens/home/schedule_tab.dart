import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:charak_core/charak_core.dart';

final _slotsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, from) async {
  final res = await ApiClient.instance.get('/slots/me?from=$from');
  return res as Map<String, dynamic>;
});

class ScheduleTab extends ConsumerStatefulWidget {
  const ScheduleTab({super.key});

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<ScheduleTab> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = now.subtract(Duration(days: now.weekday - 1)); // Monday
  }

  String get _fromDate => DateFormat('yyyy-MM-dd').format(_weekStart);

  void _prevWeek() => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
  void _nextWeek() => setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(_slotsProvider(_fromDate));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${DateFormat('MMM d').format(_weekStart)} – ${DateFormat('MMM d').format(_weekStart.add(const Duration(days: 6)))}',
        ),
        leading: IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevWeek),
        actions: [IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextWeek)],
      ),
      body: slots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load schedule', style: CharakText.body.copyWith(color: CharakColors.danger))),
        data: (data) => _WeekGrid(weekStart: _weekStart, slots: data),
      ),
    );
  }
}

class _WeekGrid extends StatelessWidget {
  final DateTime weekStart;
  final Map<String, dynamic> slots;

  const _WeekGrid({required this.weekStart, required this.slots});

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(7, (i) {
          final date = weekStart.add(Duration(days: i));
          final key  = DateFormat('yyyy-MM-dd').format(date);
          final daySlots = (slots[key] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == key;

          return SizedBox(
            width: 56,
            child: Column(
              children: [
                // Day header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: CharakSpacing.sm),
                  decoration: BoxDecoration(
                    color: isToday ? CharakColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.all(CharakRadius.pill),
                  ),
                  child: Column(
                    children: [
                      Text(days[i],
                          style: CharakText.micro.copyWith(
                              color: isToday ? Colors.white : CharakColors.inkMuted)),
                      Text(date.day.toString(),
                          style: CharakText.caption.copyWith(
                              color: isToday ? Colors.white : CharakColors.ink,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: CharakSpacing.xs),
                // Slots
                ...daySlots.take(6).map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 2, left: 2, right: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: CharakColors.primarySoft,
                    borderRadius: BorderRadius.all(CharakRadius.pill),
                  ),
                  child: Text(
                    s['start'] as String,
                    style: CharakText.micro.copyWith(color: CharakColors.primary),
                    textAlign: TextAlign.center,
                  ),
                )),
                if (daySlots.length > 6)
                  Text('+${daySlots.length - 6}',
                      style: CharakText.micro.copyWith(color: CharakColors.inkMuted)),
                if (daySlots.isEmpty)
                  Text('–', style: CharakText.caption.copyWith(color: CharakColors.border),
                      textAlign: TextAlign.center),
              ],
            ),
          );
        }),
      ),
    );
  }
}

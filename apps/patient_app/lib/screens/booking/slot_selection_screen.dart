import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _slotsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, doctorId) async {
  final from = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final res  = await ApiClient.instance.get('/doctors/$doctorId/slots?from=$from&days=6');
  return res as Map<String, dynamic>;
});

final _doctorHeaderProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, doctorId) async {
  final res = await ApiClient.instance.get('/doctors/$doctorId');
  return res as Map<String, dynamic>;
});

String _fmt12h(String t24) {
  final parts = t24.split(':');
  final h = int.parse(parts[0]);
  final m = parts[1];
  final period = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m $period';
}

/// A slot the doctor has already given away still shows, struck through, so
/// the grid reads as a real day rather than a filtered list.
bool _isTaken(Map<String, dynamic> slot) =>
    slot['available'] == false || slot['booked'] == true;

// ── SlotSelectionScreen ───────────────────────────────────────────────────────

class SlotSelectionScreen extends ConsumerStatefulWidget {
  final String doctorId;
  const SlotSelectionScreen({super.key, required this.doctorId});
  @override
  ConsumerState<SlotSelectionScreen> createState() => _State();
}

class _State extends ConsumerState<SlotSelectionScreen> {
  DateTime _selectedDay = DateTime.now();
  String? _selectedSlot; // "09:00"

  // 6-day relative strip: Today, Tomorrow, then weekday names.
  List<DateTime> get _days => List.generate(6, (i) => DateTime.now().add(Duration(days: i)));

  String _dayLabel(DateTime d, int i) {
    if (i == 0) return 'Today';
    if (i == 1) return 'Tomorrow';
    return DateFormat('EEE').format(d);
  }

  void _proceed(Map<String, dynamic> slotData) {
    if (_selectedSlot == null) return;
    final dayStr = DateFormat('yyyy-MM-dd').format(_selectedDay);
    final slots  = List<Map<String,dynamic>>.from(
        (slotData[dayStr] as List? ?? []));
    final slot   = slots.firstWhere((s) => s['start'] == _selectedSlot);

    final scheduledStart =
        '${dayStr}T${slot['start']}:00+05:30'; // IST

    context.push('/book/${widget.doctorId}/channel', extra: {
      'scheduled_start': scheduledStart,
      'slot': slot,
      'day': dayStr,
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_slotsProvider(widget.doctorId));
    final doctorAsync = ref.watch(_doctorHeaderProvider(widget.doctorId));
    final doctorName = doctorAsync.maybeWhen(data: (d) => d['name'] as String?, orElse: () => null);
    final doctorSpec = doctorAsync.maybeWhen(
        data: (d) => (d['categories'] as Map?)?['name'] as String?, orElse: () => null);

    return Scaffold(
      backgroundColor: CharakColors.ground,
      appBar: const CharakTopBar(title: ''),
      body: async.when(
        loading: () => const _SlotsLoading(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (slotData) {
          final dayKey = DateFormat('yyyy-MM-dd').format(_selectedDay);
          final slots = List<Map<String,dynamic>>.from(
              (slotData[dayKey] as List? ?? []));
          final selectedIndex = _days.indexWhere(
              (d) => DateFormat('yyyy-MM-dd').format(d) == dayKey);
          final anyTaken = slots.any(_isTaken);

          return Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  // Look up top: the question, big and wide.
                  Text('Pick a day and time', style: charakScreenTitleStyle),
                  if (doctorName != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      doctorSpec != null ? 'Dr. $doctorName · $doctorSpec' : 'Dr. $doctorName',
                      style: charakScreenSubStyle,
                    ),
                  ],
                  const SizedBox(height: 24),
                  CharakSectionTitle(label: _monthRange()),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: _days.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final d = _days[i];
                        final selected = DateFormat('yyyy-MM-dd').format(d) == dayKey;
                        return _DateChip(
                          weekday: i == 0 ? 'Today' : DateFormat('EEE').format(d),
                          day: DateFormat('d').format(d),
                          selected: selected,
                          onTap: () => setState(() {
                            _selectedDay = d;
                            _selectedSlot = null;
                          }),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (slots.isEmpty)
                    const CharakEmptyState(
                      icon: Icons.event_busy_outlined,
                      title: 'No slots this day',
                      message: 'Try another day. Only the doctor\'s open slots are shown.',
                    )
                  else ...[
                    const CharakSectionTitle(label: 'Available slots'),
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 48,
                      ),
                      itemCount: slots.length,
                      itemBuilder: (_, i) {
                        final s = slots[i];
                        final t = s['start'] as String;
                        return _TimeSlot(
                          label: _fmt12h(t),
                          selected: _selectedSlot == t,
                          taken: _isTaken(s),
                          onTap: () => setState(() => _selectedSlot = t),
                        );
                      },
                    ),
                    if (anyTaken) ...[
                      const SizedBox(height: 10),
                      const CharakHintLine(text: 'Struck-through slots are already booked.'),
                    ],
                  ],
                  const SizedBox(height: 20),
                  // What happens next, on the tint surface.
                  CharakCard(
                    tone: CharakCardTone.tint,
                    padding: const EdgeInsets.all(16),
                    child: CharakHintLine(
                      icon: Icons.info_outline_rounded,
                      text: 'You describe the problem next. '
                          '${doctorName != null ? 'Dr. $doctorName' : 'The doctor'} reads it and decides. '
                          'You pay only after the doctor accepts.',
                    ),
                  ),
                ],
              ),
            ),

            // Button wakes up: grey until a slot is picked, then blue with
            // an arrow.
            CharakCtaBar.single(
              CharakButton(
                label: _selectedSlot != null
                    ? '${_dayLabel(_selectedDay, selectedIndex)}, ${_fmt12h(_selectedSlot!)} · Continue'
                    : 'Pick a slot to continue',
                trailingIcon: _selectedSlot != null ? Icons.arrow_forward_rounded : null,
                onPressed: _selectedSlot != null ? () => _proceed(slotData) : null,
              ),
            ),
          ]);
        },
      ),
    );
  }

  String _monthRange() {
    if (_days.isEmpty) return '';
    final a = DateFormat('MMM').format(_days.first).toUpperCase();
    final b = DateFormat('MMM').format(_days.last).toUpperCase();
    return a == b ? a : '$a – $b';
  }
}

// ── Day chip ──────────────────────────────────────────────────────────────────

/// Day chip: weekday over the date in narrow tabular figures. The pick fills
/// blue (motion.standard) and pops so it's clear the choice landed.
class _DateChip extends StatelessWidget {
  final String weekday;
  final String day;
  final bool selected;
  final VoidCallback onTap;

  const _DateChip({
    required this.weekday,
    required this.day,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => CharakPressable(
    onTap: onTap,
    child: _Pop(
      on: selected,
      child: AnimatedContainer(
        duration: CharakMotion.standard,
        curve: CharakCurves.standard,
        width: 60,
        decoration: BoxDecoration(
          color: selected ? CharakColors.primary : CharakColors.card,
          borderRadius: const BorderRadius.all(CharakRadius.tile),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(weekday,
              style: CharakText.caption.copyWith(
                  color: selected ? CharakPalette.blue100 : CharakColors.inkMuted)),
          const SizedBox(height: 2),
          Text(day,
              style: CharakText.numeric.copyWith(
                  color: selected ? CharakColors.onPrimary : CharakColors.ink)),
        ]),
      ),
    ),
  );
}

// ── Time slot ─────────────────────────────────────────────────────────────────

/// Slot pill (48px). Free slots are outlined, the pick fills blue and pops
/// 0.9 → 1.05 → 1, a taken slot greys out and strikes through.
class _TimeSlot extends StatelessWidget {
  final String label;
  final bool selected;
  final bool taken;
  final VoidCallback onTap;

  const _TimeSlot({
    required this.label,
    required this.selected,
    required this.taken,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = taken ? CharakColors.inkFaint : (selected ? CharakColors.onPrimary : CharakColors.ink);
    return CharakPressable(
      onTap: taken ? null : onTap,
      child: _Pop(
        on: selected,
        child: AnimatedContainer(
          duration: CharakMotion.standard,
          curve: CharakCurves.standard,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: taken
                ? CharakColors.bgSubtle
                : (selected ? CharakColors.primary : CharakColors.card),
            borderRadius: const BorderRadius.all(CharakRadius.pill),
            border: Border.all(
              color: (taken || selected) ? Colors.transparent : CharakColors.borderStrong,
              width: 1.5,
            ),
          ),
          child: Text(label,
              style: CharakText.label.tabular.copyWith(
                fontSize: 16,
                color: fg,
                decoration: taken ? TextDecoration.lineThrough : null,
                decorationColor: fg,
              )),
        ),
      ),
    );
  }
}

/// The "pop" when a choice lands: 0.9 → 1.05 → 1 over motion.standard.
class _Pop extends StatelessWidget {
  final bool on;
  final Widget child;
  const _Pop({required this.on, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!on || charakReduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      key: const ValueKey('pop'),
      tween: Tween(begin: 0, end: 1),
      duration: CharakMotion.standard,
      builder: (_, t, c) {
        final scale = t < 0.5 ? 0.9 + (0.15 * t / 0.5) : 1.05 - (0.05 * (t - 0.5) / 0.5);
        return Transform.scale(scale: scale, child: c);
      },
      child: child,
    );
  }
}

/// Loading state: `.skel` blocks for the `.date-strip` chips and the 3-column
/// `.time-grid`, so the grid doesn't jump when the real slots land.
class _SlotsLoading extends StatelessWidget {
  const _SlotsLoading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: CharakSkeleton(width: 190, height: 14),
      ),
      // `.date-strip`
      SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          itemCount: 6,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, __) => const CharakSkeleton(width: 52, height: 42, radius: 12),
        ),
      ),
      // `.time-grid` — same 3-up geometry and 44px extent as the real grid.
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 44,
          ),
          itemCount: 9,
          itemBuilder: (_, __) => const CharakSkeleton(height: 44, radius: 12),
        ),
      ),
    ],
  );
}

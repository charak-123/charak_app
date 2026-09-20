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
      backgroundColor: CharakColors.bg,
      appBar: const CharakTopBar(title: 'Pick a slot'),
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
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  if (doctorName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        doctorSpec != null ? '$doctorName · $doctorSpec' : doctorName,
                        style: charakScreenSubStyle,
                      ),
                    ),

                  // ── `.date-strip` ─────────────────────────────────────
                  SizedBox(
                    height: 56,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(top: 2, bottom: 12),
                      itemCount: _days.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final d = _days[i];
                        final selected = DateFormat('yyyy-MM-dd').format(d) == dayKey;
                        return _DateChip(
                          weekday: DateFormat('EEE').format(d),
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

                  // ── `.time-grid` ──────────────────────────────────────
                  if (slots.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('No slots available on this day',
                            style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
                      ),
                    )
                  else
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
                    ),

                  // ── `.slot-hint` ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.info_outline, size: 14, color: CharakColors.inkMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _selectedSlot != null
                              ? 'Selected: ${_dayLabel(_selectedDay, selectedIndex)}, '
                                  '${_fmt12h(_selectedSlot!)}'
                              : anyTaken
                                  ? 'Greyed slots are already booked'
                                  : "Only the doctor's available slots are shown",
                          style: charakHintStyle,
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),

            CharakCtaBar.single(
              CharakButton(
                label: 'Continue',
                onPressed: _selectedSlot != null ? () => _proceed(slotData) : null,
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ── `.date-chip` ──────────────────────────────────────────────────────────────

/// 58px-wide stacked day chip: weekday over day-of-month, inverted to solid
/// `ink` when picked.
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
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: CharakDurations.buttonPress,
      width: 58,
      padding: const EdgeInsets.only(top: 9, bottom: 8),
      decoration: BoxDecoration(
        color: selected ? CharakColors.ink : CharakColors.bgSubtle,
        borderRadius: const BorderRadius.all(CharakRadius.button),
        border: Border.all(color: Colors.transparent),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(weekday,
            style: TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: selected ? Colors.white : CharakColors.inkMuted,
            )),
        const SizedBox(height: 1),
        Text(day,
            style: TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: selected ? Colors.white : CharakColors.inkMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ]),
    ),
  );
}

// ── `.time-slot` ──────────────────────────────────────────────────────────────

/// 44px grid cell. Free slots are outlined, the pick fills primary, and a
/// taken slot greys out and strikes through with taps disabled.
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

  /// `.time-slot.off` colour — not a token, defined only for this state.
  static const _offInk = Color(0xFFB9C1CE);

  @override
  Widget build(BuildContext context) {
    final body = AnimatedContainer(
      duration: CharakDurations.buttonPress,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: taken
            ? CharakColors.bgSubtle
            : (selected ? CharakColors.primary : CharakColors.bg),
        borderRadius: const BorderRadius.all(CharakRadius.button),
        border: Border.all(
          color: taken
              ? Colors.transparent
              : (selected ? CharakColors.primary : CharakColors.border),
        ),
      ),
      child: Text(label,
          style: TextStyle(
            fontFamily: CharakText.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.3,
            color: taken
                ? _offInk
                : (selected ? Colors.white : CharakColors.ink),
            decoration: taken ? TextDecoration.lineThrough : null,
            decorationColor: _offInk,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
    );
    if (taken) return body;
    return GestureDetector(onTap: onTap, child: body);
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

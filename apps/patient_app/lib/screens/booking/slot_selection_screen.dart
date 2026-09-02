import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import '../shared/charak_button.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _slotsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, doctorId) async {
  final from = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final res  = await ApiClient.instance.get('/doctors/$doctorId/slots?from=$from&days=14');
  return res as Map<String, dynamic>;
});

// ── SlotSelectionScreen ───────────────────────────────────────────────────────

class SlotSelectionScreen extends ConsumerStatefulWidget {
  final String doctorId;
  const SlotSelectionScreen({super.key, required this.doctorId});
  @override
  ConsumerState<SlotSelectionScreen> createState() => _State();
}

class _State extends ConsumerState<SlotSelectionScreen> {
  DateTime _selectedDay = DateTime.now();
  String? _selectedSlot;        // "09:00"
  String? _selectedChannel;     // "online_consult" | "home_visit"

  // Generate 14 days from today
  List<DateTime> get _days => List.generate(
    14, (i) => DateTime.now().add(Duration(days: i)),
  );

  void _proceed(Map<String, dynamic> slotData) {
    if (_selectedSlot == null || _selectedChannel == null) return;
    final dayStr = DateFormat('yyyy-MM-dd').format(_selectedDay);
    final slots  = List<Map<String,dynamic>>.from(
        (slotData[dayStr] as List? ?? []));
    final slot   = slots.firstWhere((s) => s['start'] == _selectedSlot);

    final scheduledStart =
        '${dayStr}T${slot['start']}:00+05:30'; // IST

    context.push('/book/${widget.doctorId}/channel', extra: {
      'channel': _selectedChannel,
      'scheduled_start': scheduledStart,
      'slot': slot,
      'day': dayStr,
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_slotsProvider(widget.doctorId));
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Select a Slot'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (slotData) {
          final dayKey = DateFormat('yyyy-MM-dd').format(_selectedDay);
          final slots = List<Map<String,dynamic>>.from(
              (slotData[dayKey] as List? ?? []));

          return Column(children: [
            // Channel selector
            Container(
              color: CharakColors.bg,
              padding: const EdgeInsets.all(CharakSpacing.base),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Consultation Type', style: CharakText.h2),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _ChannelChip(
                    label: 'Online Consult',
                    icon: Icons.videocam_outlined,
                    selected: _selectedChannel == 'online_consult',
                    onTap: () => setState(() => _selectedChannel = 'online_consult'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _ChannelChip(
                    label: 'Home Visit',
                    icon: Icons.home_outlined,
                    selected: _selectedChannel == 'home_visit',
                    onTap: () => setState(() => _selectedChannel = 'home_visit'),
                  )),
                ]),
              ]),
            ),

            const Divider(height: 1, color: CharakColors.border),

            // Date strip
            Container(
              color: CharakColors.bg,
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                itemCount: _days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final d = _days[i];
                  final selected = DateFormat('yyyy-MM-dd').format(d) ==
                      DateFormat('yyyy-MM-dd').format(_selectedDay);
                  final hasSlots = slotData.containsKey(DateFormat('yyyy-MM-dd').format(d));
                  return GestureDetector(
                    onTap: () => setState(() { _selectedDay = d; _selectedSlot = null; }),
                    child: Container(
                      width: 52,
                      decoration: BoxDecoration(
                        color: selected ? CharakColors.primary : CharakColors.bg,
                        borderRadius: BorderRadius.all(CharakRadius.card),
                        border: Border.all(
                          color: selected ? CharakColors.primary : CharakColors.border,
                        ),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(DateFormat('EEE').format(d),
                            style: CharakText.micro.copyWith(
                              color: selected ? Colors.white70 : CharakColors.inkMuted,
                            )),
                        const SizedBox(height: 2),
                        Text(DateFormat('d').format(d),
                            style: CharakText.bodyMed.copyWith(
                              color: selected ? Colors.white : CharakColors.ink,
                            )),
                        if (!hasSlots)
                          Container(width: 4, height: 4,
                            decoration: const BoxDecoration(
                              color: CharakColors.border, shape: BoxShape.circle)),
                      ]),
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1, color: CharakColors.border),

            // Time grid
            Expanded(
              child: slots.isEmpty
                  ? Center(
                      child: Text('No slots available on this day',
                          style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(CharakSpacing.base),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.2,
                      ),
                      itemCount: slots.length,
                      itemBuilder: (_, i) {
                        final s = slots[i];
                        final t = s['start'] as String;
                        final selected = _selectedSlot == t;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedSlot = t),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? CharakColors.primary : CharakColors.bg,
                              borderRadius: BorderRadius.all(CharakRadius.button),
                              border: Border.all(
                                color: selected ? CharakColors.primary : CharakColors.border,
                              ),
                            ),
                            child: Text(t,
                                style: CharakText.caption.copyWith(
                                  color: selected ? Colors.white : CharakColors.ink,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                )),
                          ),
                        );
                      },
                    ),
            ),

            // CTA
            Container(
              padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 12, CharakSpacing.base, 24),
              color: CharakColors.bg,
              child: CharakButton(
                label: 'Confirm Slot',
                onPressed: (_selectedSlot != null && _selectedChannel != null)
                    ? () => _proceed(slotData)
                    : null,
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ChannelChip({required this.label, required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: CharakDurations.buttonPress,
      height: 52,
      decoration: BoxDecoration(
        color: selected ? CharakColors.primarySoft : CharakColors.bgSubtle,
        borderRadius: BorderRadius.all(CharakRadius.button),
        border: Border.all(
          color: selected ? CharakColors.primary : CharakColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: selected ? CharakColors.primary : CharakColors.inkMuted),
        const SizedBox(width: 6),
        Text(label,
            style: CharakText.caption.copyWith(
              color: selected ? CharakColors.primary : CharakColors.ink,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
      ]),
    ),
  );
}

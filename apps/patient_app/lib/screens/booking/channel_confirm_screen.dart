import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import '../shared/charak_button.dart';

/// Confirms the channel choice.
/// For home_visit: shows the patient's current location (stub — geolocator
/// integration done in Day 35 followup) and allows address entry.
class ChannelConfirmScreen extends ConsumerStatefulWidget {
  final String doctorId;
  final Map<String, dynamic> extra; // {channel, scheduled_start, slot, day}
  const ChannelConfirmScreen({super.key, required this.doctorId, required this.extra});
  @override
  ConsumerState<ChannelConfirmScreen> createState() => _State();
}

class _State extends ConsumerState<ChannelConfirmScreen> {
  final _addressCtrl = TextEditingController();

  @override
  void dispose() { _addressCtrl.dispose(); super.dispose(); }

  bool get _isHome => (extra['channel'] as String) == 'home_visit';
  Map<String,dynamic> get extra => widget.extra;

  void _proceed() {
    context.push('/book/${widget.doctorId}/intake', extra: {
      ...extra,
      if (_isHome) 'address': _addressCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final channel = extra['channel'] as String;
    final start   = extra['scheduled_start'] as String;
    final dt      = DateTime.tryParse(start.replaceAll('+05:30', ''))?.toLocal();
    final dateStr = dt != null ? DateFormat('EEEE, d MMMM · h:mm a').format(dt) : start;

    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Confirm Booking'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
      ),
      body: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(CharakSpacing.base), children: [
          // Summary card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(CharakRadius.card),
              side: const BorderSide(color: CharakColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(CharakSpacing.base),
              child: Column(children: [
                _Row(
                  icon: channel == 'home_visit' ? Icons.home_outlined : Icons.videocam_outlined,
                  label: channel == 'home_visit' ? 'Home Visit' : 'Online Consult',
                ),
                const SizedBox(height: 10),
                _Row(icon: Icons.schedule, label: dateStr),
              ]),
            ),
          ),

          // Address field for home visit
          if (_isHome) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(CharakRadius.card),
                side: const BorderSide(color: CharakColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(CharakSpacing.base),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your Address', style: CharakText.h2),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _addressCtrl,
                    maxLines: 3,
                    style: CharakText.body,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Flat, building, street, landmark, city...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The doctor will use this address to navigate to you.',
                    style: CharakText.micro.copyWith(color: CharakColors.inkMuted),
                  ),
                ]),
              ),
            ),
          ],
        ])),

        Container(
          padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 12, CharakSpacing.base, 24),
          color: CharakColors.bg,
          child: CharakButton(
            label: 'Next: Add Details',
            onPressed: (!_isHome || _addressCtrl.text.trim().length > 5)
                ? _proceed
                : null,
          ),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Row({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: CharakColors.inkMuted),
    const SizedBox(width: 8),
    Expanded(child: Text(label, style: CharakText.body)),
  ]);
}

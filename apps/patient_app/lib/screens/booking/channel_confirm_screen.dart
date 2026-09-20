import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

// ── Provider for doctor pricing ───────────────────────────────────────────────

final _pricingProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, doctorId) async {
  final res = await ApiClient.instance.get('/doctors/$doctorId');
  return res as Map<String, dynamic>;
});

// ── ChannelConfirmScreen ──────────────────────────────────────────────────────

class ChannelConfirmScreen extends ConsumerStatefulWidget {
  final String doctorId;
  final Map<String, dynamic> extra; // {channel, scheduled_start, slot, day}
  const ChannelConfirmScreen({super.key, required this.doctorId, required this.extra});
  @override
  ConsumerState<ChannelConfirmScreen> createState() => _State();
}

class _State extends ConsumerState<ChannelConfirmScreen> {
  late String _channel = widget.extra['channel'] as String? ?? 'online_consult';
  final _addressCtrl = TextEditingController();

  @override
  void dispose() { _addressCtrl.dispose(); super.dispose(); }

  bool get _isHome => _channel == 'home_visit';

  void _proceed() {
    context.push('/book/${widget.doctorId}/intake', extra: {
      ...widget.extra,
      'channel': _channel,
      if (_isHome) 'address': _addressCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final start   = widget.extra['scheduled_start'] as String;
    final dt      = DateTime.tryParse(start.replaceAll('+05:30', ''))?.toLocal();
    final dateStr = dt != null ? DateFormat('EEE d MMM, h:mm a').format(dt) : start;

    final async = ref.watch(_pricingProvider(widget.doctorId));
    final pricing = async.maybeWhen(
      data: (d) => List<Map<String,dynamic>>.from(d['doctor_pricing'] as List? ?? []),
      orElse: () => <Map<String,dynamic>>[],
    );
    final docName = async.maybeWhen(
      data: (d) => d['name'] as String? ?? 'Doctor',
      orElse: () => 'Doctor',
    );

    final onlineP    = pricing.where((p) => p['channel'] == 'online_consult').firstOrNull;
    final homeP      = pricing.where((p) => p['channel'] == 'home_visit').firstOrNull;
    final onlinePrice = (onlineP?['price'] as num?)?.toDouble() ?? 0;
    final homePrice   = (homeP?['price'] as num?)?.toDouble() ?? 0;
    final onlineExtra = (onlineP?['extra_rate_per_15min'] as num?)?.toDouble() ?? 150;
    final homeExtra   = (homeP?['extra_rate_per_15min'] as num?)?.toDouble() ?? 200;
    final radius      = async.maybeWhen(
      data: (d) => d['service_radius_km'],
      orElse: () => null,
    );

    final confirmPrice = _isHome ? homePrice : onlinePrice;
    final (successBg, _) = charakToneColors(CharakStatusTone.success);

    return Scaffold(
      backgroundColor: CharakColors.bg,
      appBar: const CharakTopBar(title: 'How should the visit happen?'),
      body: Column(children: [
        Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text('$dateStr · $docName', style: charakScreenSubStyle),
            const SizedBox(height: 16),

            // ── `.chan-card` — Online Consult ─────────────────────────────
            if (onlineP != null)
              _ChannelCard(
                selected: _channel == 'online_consult',
                icon: Icons.videocam_outlined,
                iconBg: CharakColors.primarySoft,
                iconColor: CharakColors.primaryDeep,
                title: 'Online Consult',
                description: 'Video call on CHARAK. Price covers a 15-min '
                    'consult, paid before the call.',
                note: '+ ₹${onlineExtra.toStringAsFixed(0)} per extra 15 min',
                price: onlinePrice,
                onTap: () => setState(() => _channel = 'online_consult'),
              ),

            if (onlineP != null && homeP != null) const SizedBox(height: 12),

            // ── `.chan-card` — Home Visit ─────────────────────────────────
            if (homeP != null)
              _ChannelCard(
                selected: _channel == 'home_visit',
                icon: Icons.home_outlined,
                iconBg: successBg,
                iconColor: CharakColors.success,
                title: 'Home Visit',
                description: 'Doctor comes to you. Consult fee paid upfront; '
                    'procedures (if any) billed after at fixed rates.',
                note: '+ ₹${homeExtra.toStringAsFixed(0)} per extra 15 min'
                    '${radius != null ? ' · within $radius km' : ''}',
                price: homePrice,
                onTap: () => setState(() => _channel = 'home_visit'),
              ),

            // ── Address (home only) ───────────────────────────────────────
            if (_isHome) ...[
              const SizedBox(height: 18),
              CharakField(
                label: 'Your address',
                controller: _addressCtrl,
                placeholder: 'Flat, building, street, landmark…',
                maxLines: null,
                minLines: 3,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              CharakInfoStrip(
                icon: Icons.location_on_outlined,
                label: _addressCtrl.text.trim().isNotEmpty
                    ? '${_addressCtrl.text.trim()} — in range for Home Visit'
                    : "Enter your address to confirm you're in range for Home Visit",
              ),
            ],
          ],
        )),

        CharakCtaBar.single(
          CharakButton(
            label: confirmPrice > 0
                ? 'Continue · ₹${confirmPrice.toStringAsFixed(0)}'
                    '${_isHome ? ' + procedures' : ''}'
                : 'Continue',
            onPressed: (!_isHome || _addressCtrl.text.trim().length > 5)
                ? _proceed
                : null,
          ),
        ),
      ]),
    );
  }
}

// ── `.chan-card` ──────────────────────────────────────────────────────────────

/// Channel option: a 44px tinted glyph, title + explanation + extra-time note,
/// and a right-aligned price. Selection draws the spec's doubled primary edge
/// (`border-color` plus a 1px ring).
class _ChannelCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String description;
  final String note;
  final double price;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.selected,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.note,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: CharakDurations.buttonPress,
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
        border: Border.all(color: selected ? CharakColors.primary : CharakColors.border),
        boxShadow: selected
            ? const [BoxShadow(color: CharakColors.primary, spreadRadius: 1)]
            : null,
      ),
      padding: const EdgeInsets.all(CharakSpacing.base),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 13),

        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: CharakText.h2.copyWith(fontSize: 16)),
          const SizedBox(height: 3),
          Text(description,
              style: CharakText.caption.copyWith(
                  color: CharakColors.inkMuted, height: 1.5)),
          const SizedBox(height: 4),
          // `.chan-note`
          Text(note,
              style: const TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 12,
                height: 1.4,
                color: CharakColors.inkMuted,
              )),
        ])),

        const SizedBox(width: 10),
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: '₹${price.toStringAsFixed(0)}',
              style: CharakText.h2.copyWith(
                  fontSize: 16,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            TextSpan(
              text: '/15m',
              style: CharakText.micro
                  .copyWith(color: CharakColors.inkMuted, letterSpacing: 0),
            ),
          ]),
        ),
      ]),
    ),
  );
}

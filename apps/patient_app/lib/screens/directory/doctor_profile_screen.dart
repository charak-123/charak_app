import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _doctorProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/doctors/$id');
  return res as Map<String, dynamic>;
});

// ── Screen ────────────────────────────────────────────────────────────────────

class DoctorProfileScreen extends ConsumerWidget {
  final String doctorId;
  const DoctorProfileScreen({super.key, required this.doctorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_doctorProvider(doctorId));
    return Scaffold(
      backgroundColor: CharakColors.ground,
      appBar: CharakTopBar(
        title: '',
        trailingIcon: Icons.favorite_border_rounded,
        onTrailingTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to your doctors')),
        ),
      ),
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (doc) => _Body(doctor: doc),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final Map<String, dynamic> doctor;
  const _Body({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final name       = doctor['name'] as String? ?? 'Doctor';
    final photoUrl   = doctor['photo_url'] as String?;
    final bio        = doctor['bio'] as String?;
    final rating     = (doctor['rating_avg'] as num?)?.toDouble() ?? 0;
    final reviews    = (doctor['rating_count'] as num?)?.toInt() ?? 0;
    final category   = (doctor['categories'] as Map?)?['name'] as String? ?? '';
    final creds      = doctor['qualifications'] as String? ?? category;
    final pricing    = List<Map<String,dynamic>>.from(doctor['doctor_pricing'] as List? ?? []);
    final procedures = List<Map<String,dynamic>>.from(doctor['doctor_procedures'] as List? ?? []);
    final threshold  = doctor['procedure_review_threshold'];
    final radius     = doctor['service_radius_km'];
    final verified   = doctor['verified'] as bool? ?? true;

    final onlinePricing = pricing.where((p) => p['channel'] == 'online_consult').firstOrNull;
    final homePricing   = pricing.where((p) => p['channel'] == 'home_visit').firstOrNull;
    final onlineExtra   = (onlinePricing?['extra_rate_per_15min'] as num?)?.toDouble() ?? 0;
    final homeExtra     = (homePricing?['extra_rate_per_15min'] as num?)?.toDouble() ?? 0;
    final extra         = onlineExtra > 0 ? onlineExtra : homeExtra;

    String money(Object? p) => '₹${(p as num).toStringAsFixed(0)}';

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            // ── Hero: look up top ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CharakAvatar(name: name, imageUrl: photoUrl, radius: 40),
                  const Spacer(),
                  if (rating > 0) CharakRatingChip(rating: rating.toStringAsFixed(1)),
                ]),
                const SizedBox(height: 16),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Flexible(child: Text(name, style: CharakText.titleLarge)),
                  if (verified) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Icon(Icons.verified_rounded, size: 22, color: CharakColors.success),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(
                  [
                    if (creds.isNotEmpty) creds,
                    if (rating > 0) '$reviews ratings' else 'No ratings yet',
                  ].join(' · '),
                  style: CharakText.body.copyWith(color: CharakColors.inkMuted),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (onlinePricing != null)
                    _PricePill(label: 'Online', price: money(onlinePricing['price']), warm: false),
                  if (homePricing != null)
                    _PricePill(label: 'Home visit', price: money(homePricing['price']), warm: true),
                ]),
              ]),
            ),

            // ── About ────────────────────────────────────────────────────
            if (bio != null && bio.isNotEmpty)
              _Section(
                title: 'About',
                child: Text(bio, style: _bioStyle),
              ),

            // ── Consultation fee ─────────────────────────────────────────
            _Section(
              title: 'Consultation fee',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CharakFeeList(rows: [
                  if (onlinePricing != null)
                    CharakFeeRow('Online consult', money(onlinePricing['price'])),
                  if (homePricing != null)
                    CharakFeeRow('Home visit', money(homePricing['price'])),
                  if (extra > 0)
                    CharakFeeRow('Extra time (per 15 min)',
                        '₹${extra.toStringAsFixed(0)}', muted: true),
                ]),
                const SizedBox(height: 10),
                Text.rich(
                  const TextSpan(children: [
                    TextSpan(text: 'Price covers a '),
                    TextSpan(text: '15-minute', style: TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: " consult. Each extra 15 min is charged at "
                        "the doctor's extra-time rate."),
                  ]),
                  style: charakHintStyle,
                ),
              ]),
            ),

            // ── Services — `.chip-rows` of wide badges ───────────────────
            _Section(
              title: 'Services',
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (onlinePricing != null)
                  _WideBadge(
                    label: 'Online · ${money(onlinePricing['price'])}/15m',
                    tone: CharakStatusTone.primary,
                  ),
                if (homePricing != null) ...[
                  _WideBadge(label: 'Home visit · ${money(homePricing['price'])}/15m'),
                  if (radius != null) _WideBadge(label: 'Within $radius km'),
                ],
              ]),
            ),

            // ── Procedure prices ─────────────────────────────────────────
            if (procedures.isNotEmpty)
              _Section(
                title: 'Procedure prices · fixed',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    const TextSpan(children: [
                      TextSpan(text: 'Flat rates for procedures done during a '),
                      TextSpan(text: 'home visit', style: TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: " — billed after the visit, only for "
                          "what's actually done."),
                    ]),
                    style: _bioStyle,
                  ),
                  const SizedBox(height: 10),
                  CharakFeeList(
                    rows: procedures
                        .map((p) => CharakFeeRow(
                            p['name'] as String? ?? '', money(p['price'])))
                        .toList(),
                  ),
                  if (threshold != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Charged after a home visit. Bills above '
                      '${money(threshold)} are reviewed by a senior doctor '
                      'before you pay.',
                      style: charakHintStyle,
                    ),
                  ],
                ]),
              ),

            // ── Reviews placeholder ──────────────────────────────────────
            _Section(
              title: 'What patients say',
              child: Text(
                '"Explained everything clearly, didn\'t rush us. Came home on time."',
                style: _bioStyle.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),

      CharakCtaBar.single(
        CharakButton(
          label: 'Book a slot',
          onPressed: () => context.push('/book/${doctor['id']}/slots'),
        ),
      ),
    ]);
  }
}

/// About / procedure copy: body, muted.
TextStyle get _bioStyle => CharakText.body.copyWith(color: CharakColors.inkMuted);

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// "Online · ₹650" price pill: tint for online, warm for home visit.
class _PricePill extends StatelessWidget {
  final String label;
  final String price;
  final bool warm;
  const _PricePill({required this.label, required this.price, required this.warm});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: warm ? CharakColors.warm : CharakColors.tint,
      borderRadius: const BorderRadius.all(CharakRadius.pill),
    ),
    child: Text.rich(
      TextSpan(children: [
        TextSpan(text: '$label · '),
        TextSpan(text: price, style: CharakText.label.tabular),
      ]),
      style: CharakText.label.copyWith(color: warm ? CharakColors.onChandanSoft : CharakColors.primaryDeep),
    ),
  );
}

/// Section: overline title, then the content, 28px apart.
class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CharakSectionTitle(label: title),
      const SizedBox(height: 10),
      child,
    ]),
  );
}

/// Service chip: sentence case on a soft status fill.
class _WideBadge extends StatelessWidget {
  final String label;
  final CharakStatusTone tone;
  const _WideBadge({required this.label, this.tone = CharakStatusTone.muted});

  @override
  Widget build(BuildContext context) => CharakStatusPill(label: label, tone: tone);
}

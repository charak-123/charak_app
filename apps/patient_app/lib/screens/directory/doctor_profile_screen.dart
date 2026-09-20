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
      backgroundColor: CharakColors.bg,
      appBar: CharakTopBar(
        title: 'Doctor',
        trailingIcon: Icons.bookmark_outline_rounded,
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            // ── `.dp-hero` ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
              child: Column(children: [
                CharakAvatar(name: name, imageUrl: photoUrl, radius: 42),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(
                    child: Text(name,
                        style: CharakText.h1.copyWith(fontSize: 21),
                        textAlign: TextAlign.center),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 7),
                    const Icon(Icons.verified_user_rounded,
                        size: 17, color: CharakColors.success),
                  ],
                ]),
                if (creds.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(creds,
                      style: CharakText.body.copyWith(
                          fontSize: 14, color: CharakColors.inkMuted),
                      textAlign: TextAlign.center),
                ],
              ]),
            ),

            // ── `.dp-stats` — bordered strip of equal cells ───────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: CharakColors.border),
                  borderRadius: const BorderRadius.all(CharakRadius.card),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _Stat(
                    value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                    icon: Icons.star_rounded,
                    label: rating > 0 ? '$reviews ratings' : 'No ratings yet',
                    tabular: true,
                  ),
                  if (verified) ...[
                    const _StatDivider(),
                    const _Stat(value: 'Verified', label: 'License checked'),
                  ],
                  if (onlinePricing != null) ...[
                    const _StatDivider(),
                    _Stat(
                      value: money(onlinePricing['price']),
                      per: '/15m',
                      label: 'Online consult',
                      tabular: true,
                    ),
                  ],
                  if (homePricing != null) ...[
                    const _StatDivider(),
                    _Stat(
                      value: money(homePricing['price']),
                      per: '/15m',
                      label: 'Home visit',
                      tabular: true,
                    ),
                  ],
                ]),
              ),
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
                const Text.rich(
                  TextSpan(children: [
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
                  _WideBadge(label: 'Home Visit · ${money(homePricing['price'])}/15m'),
                  if (radius != null) _WideBadge(label: 'Within $radius km'),
                ],
              ]),
            ),

            // ── Procedure prices ─────────────────────────────────────────
            if (procedures.isNotEmpty)
              _Section(
                title: 'Procedure prices · fixed',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text.rich(
                    TextSpan(children: [
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

/// `.dp-bio` — 14px on a generous 1.6 leading.
const _bioStyle = TextStyle(
  fontFamily: CharakText.fontFamily,
  fontSize: 14,
  height: 1.6,
  color: CharakColors.inkMuted,
);

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// `.dp-stat` — 16px/600 value (optionally with a star or a `/15m` suffix)
/// over an 11px wide-tracked caption.
class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final String? per;
  final IconData? icon;
  final bool tabular;
  const _Stat({
    required this.value,
    required this.label,
    this.per,
    this.icon,
    this.tabular = false,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: CharakColors.warning),
            const SizedBox(width: 3),
          ],
          Text(value,
              style: CharakText.h2.copyWith(
                fontSize: 16,
                fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
              )),
          if (per != null)
            Text(per!,
                style: CharakText.micro.copyWith(
                    color: CharakColors.inkMuted, letterSpacing: 0)),
        ]),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 11,
              height: 1.3,
              letterSpacing: 11 * 0.03,
              color: CharakColors.inkMuted,
            ),
            textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 1, child: ColoredBox(color: CharakColors.border));
}

/// `.dp-sec` — 18px above, an uppercase `.sec-title`, then the content.
class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CharakSectionTitle(label: title),
      const SizedBox(height: 8),
      child,
    ]),
  );
}

/// `.chip-rows .badge` — the roomier badge variant: 6/12 padding, 12px text.
class _WideBadge extends StatelessWidget {
  final String label;
  final CharakStatusTone tone;
  const _WideBadge({required this.label, this.tone = CharakStatusTone.muted});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = charakToneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: CharakText.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.3,
          letterSpacing: 12 * 0.04,
          color: fg,
        ),
      ),
    );
  }
}

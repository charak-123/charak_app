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
    return CharakScreen(
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => CharakErrorState(error: e, onRetry: () => ref.invalidate(_doctorProvider(doctorId))),
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
    final name       = CharakFormat.doctor(doctor['name'] as String?);
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
    int mins(Map<String, dynamic>? p) => (p?['base_duration_min'] as num?)?.toInt() ?? 15;
    int extraMins(Map<String, dynamic>? p) => (p?['extra_duration_min'] as num?)?.toInt() ?? 15;

    String money(Object? p) => CharakFormat.rupees(p as num);

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            // ── Hero: look up top (board "Patient · Doctor & slot") ───────
            // 88px avatar with the verified tick on its corner, the rating
            // chip level with it, then the name and one meta line.
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Stack(clipBehavior: Clip.none, children: [
                    CharakAvatar(name: name, imageUrl: photoUrl, radius: 44),
                    if (verified)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Semantics(
                          label: 'Verified doctor',
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: CharakColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: CharakColors.ground, width: 3),
                            ),
                            alignment: Alignment.center,
                            child: Icon(LucideIcons.check, size: 12, color: CharakColors.onPrimary),
                          ),
                        ),
                      ),
                  ]),
                  const Spacer(),
                  if (rating > 0) CharakRatingChip(rating: rating.toStringAsFixed(1)),
                ]),
                const SizedBox(height: 16),
                Text(name, style: CharakText.titleLarge.copyWith(color: CharakColors.ink)),
                const SizedBox(height: 6),
                Text(
                  [
                    if (creds.isNotEmpty) creds,
                    if (reviews > 0) '$reviews ratings',
                    if (homePricing != null && radius != null) 'Home visits within $radius km',
                  ].join(' · '),
                  style: CharakText.body.copyWith(color: CharakColors.inkMuted),
                ),
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
                    CharakFeeRow('Online consult · ${mins(onlinePricing)} min', money(onlinePricing['price'])),
                  if (homePricing != null)
                    CharakFeeRow('Home visit · ${mins(homePricing)} min', money(homePricing['price'])),
                  if (onlinePricing != null && onlineExtra > 0)
                    CharakFeeRow('Online extra (per ${extraMins(onlinePricing)} min)',
                        CharakFormat.rupees(onlineExtra), muted: true),
                  if (homePricing != null && homeExtra > 0)
                    CharakFeeRow('Home extra (per ${extraMins(homePricing)} min)',
                        CharakFormat.rupees(homeExtra), muted: true),
                ]),
                const SizedBox(height: 10),
                Text.rich(
                  const TextSpan(children: [
                    TextSpan(text: 'Price covers one session of the length shown. '),
                    TextSpan(text: 'Extra time', style: TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: " is charged per block at the doctor's extra-time rate."),
                  ]),
                  style: charakHintStyle,
                ),
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


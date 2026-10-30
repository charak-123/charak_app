import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../../specialties.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _doctorProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/doctors/$id');
  return res as Map<String, dynamic>;
});

/// The doctor's rating ("New" below 5 reviews) and recent comments.
final _reviewsProvider = FutureProvider.autoDispose.family<CharakRatingSummary, String>((ref, id) async {
  return CharakRatingSummary.fromJson(
      await ApiClient.instance.get('/doctors/$id/reviews?limit=5') as Map<String, dynamic>);
});

/// The doctor's first-visit prices by channel and length.
final _pricesProvider = FutureProvider.autoDispose.family<CharakPriceList, String>((ref, id) async {
  return CharakPriceList.fromJson(await ApiClient.instance.get('/doctors/$id/prices') as Map<String, dynamic>);
});

// ── Screen ────────────────────────────────────────────────────────────────────

class DoctorProfileScreen extends ConsumerWidget {
  final String doctorId;

  /// Choosing another doctor after one didn't attend (directory_screen.dart).
  final Map<String, dynamic>? replacement;
  const DoctorProfileScreen({super.key, required this.doctorId, this.replacement});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_doctorProvider(doctorId));
    return CharakScreen(
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => CharakErrorState(error: e, onRetry: () => ref.invalidate(_doctorProvider(doctorId))),
        data: (doc) => _Body(
          replacement: replacement,
          doctor: doc,
          prices: ref.watch(_pricesProvider(doctorId)).valueOrNull,
          reviews: ref.watch(_reviewsProvider(doctorId)).valueOrNull,
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final Map<String, dynamic> doctor;
  final CharakPriceList? prices;
  final CharakRatingSummary? reviews;
  final Map<String, dynamic>? replacement;
  const _Body({required this.doctor, required this.prices, required this.reviews, this.replacement});

  @override
  Widget build(BuildContext context) {
    final name       = CharakFormat.doctor(doctor['name'] as String?);
    final photoUrl   = doctor['photo_url'] as String?;
    final bio        = doctor['bio'] as String?;
    final rating     = (doctor['rating_avg'] as num?)?.toDouble() ?? 0;
    final reviewCount = (doctor['rating_count'] as num?)?.toInt() ?? 0;
    final category   = specialtyName((doctor['categories'] as Map?)?['name'] as String?);
    final creds      = doctor['qualifications'] as String? ?? category;
    final procedures = List<Map<String,dynamic>>.from(doctor['doctor_procedures'] as List? ?? []);
    final threshold  = doctor['procedure_review_threshold'];
    final radius     = doctor['service_radius_km'];
    final verified   = doctor['verified'] as bool? ?? true;

    final online = prices?.optionsFor('online_consult') ?? const <CharakPriceOption>[];
    final home   = prices?.optionsFor('home_visit') ?? const <CharakPriceOption>[];
    final validity = prices?.followUpValidityDays;

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
                    CharakAvatar(name: name, imageUrl: photoUrl, radius: 44, viewable: true),
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
                    if (reviewCount > 0) '$reviewCount review${reviewCount == 1 ? '' : 's'}',
                    if (home.isNotEmpty && radius != null) 'Home visits within $radius km',
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
                if (prices == null)
                  const CharakSkeleton(height: 72, radius: 20)
                else
                  CharakFeeList(rows: [
                    for (final o in online) CharakFeeRow('Online consult · ${o.durationMin} min', o.priceLabel),
                    for (final o in home) CharakFeeRow('Home visit · ${o.durationMin} min', o.priceLabel),
                  ]),
                const SizedBox(height: 10),
                Text(
                  'You choose the length when you book, and pay that price. Nothing is added for time.'
                  '${prices?.offersFollowUpPrices == true && validity != null ? ' A follow-up for the same problem within $validity days costs less: book it from your prescription.' : ''}',
                  style: charakHintStyle,
                ),
              ]),
            ),

            // ── Reviews ──────────────────────────────────────────────────
            if (reviews != null && reviews!.count > 0)
              _Section(
                title: 'Reviews',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CharakRatingSummaryCard(summary: reviews!, showExplanation: false),
                  for (final (i, r) in reviews!.reviews.take(3).indexed)
                    CharakReviewTile(review: r, last: i == reviews!.reviews.take(3).length - 1),
                  const SizedBox(height: 6),
                  Text(
                    'From patients who completed a visit with this doctor. '
                    '${reviews!.isNew ? 'An average is shown from ${reviews!.minReviewsShown} reviews.' : reviews!.explanation}',
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

      CharakCtaBar(
        // A doctor still setting up their hours or prices offers nothing to
        // book yet (backend services/listing.py); say so rather than open a
        // booking flow with nothing in it.
        header: prices != null && online.isEmpty && home.isEmpty
            ? Text("This doctor isn't taking bookings right now.",
                textAlign: TextAlign.center, style: charakHintStyle)
            : null,
        children: [
          Expanded(
            child: CharakButton(
              label: replacement != null ? 'Book with your earlier payment' : 'Book a consultation',
              onPressed: prices != null && online.isEmpty && home.isEmpty
                  ? null
                  : () => context.push('/book/${doctor['id']}/channel', extra: replacement),
            ),
          ),
        ],
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


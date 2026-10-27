import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:charak_core/charak_core.dart';

final _myReviewsProvider = FutureProvider.autoDispose<CharakRatingSummary>((ref) async {
  return CharakRatingSummary.fromJson(await ApiClient.instance.get('/doctors/me/reviews') as Map<String, dynamic>);
});

const _reasons = <String, String>{
  'abusive': 'Abusive or offensive',
  'privacy': 'Shares private details',
  'irrelevant': 'Not about this visit',
  'other': 'Something else',
};

/// The doctor's rating, how it's worked out, and the reviews behind it.
/// Reviewers aren't named. A review can be reported; ops decides, and a
/// review is never removed for being negative.
class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  Future<void> _report(BuildContext context, WidgetRef ref, CharakReview review) async {
    final reason = await showCharakSheet<String>(
      context,
      title: 'Report this review',
      child: Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Our team checks it. It stays up while they do, and it is only taken down if it breaks '
            'the rules below, not for being negative.',
            style: charakHintStyle,
          ),
          const SizedBox(height: 12),
          for (final e in _reasons.entries) ...[
            CharakButton(label: e.value, variant: CharakButtonVariant.outline,
                onPressed: () => Navigator.pop(ctx, e.key)),
            const SizedBox(height: 8),
          ],
        ]),
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      await ApiClient.instance.post('/doctors/me/reviews/${review.id}/report', {'reason': reason});
      ref.invalidate(_myReviewsProvider);
      if (context.mounted) showCharakToast(context, message: 'Reported. Our team will look at it.');
    } on ApiException catch (e) {
      if (context.mounted) showCharakToast(context, message: e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_myReviewsProvider);
    return CharakScreen(
      title: 'Ratings & reviews',
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => CharakErrorState(error: e, onRetry: () => ref.invalidate(_myReviewsProvider)),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(_myReviewsProvider.future),
          color: CharakColors.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 4, CharakSpacing.gutter, 32),
            children: [
              CharakRatingSummaryCard(summary: s),
              const SizedBox(height: 24),
              if (s.reviews.isEmpty)
                const CharakEmptyState(
                  icon: LucideIcons.star,
                  title: 'No reviews yet',
                  message: 'Patients can review a visit for 14 days after it\'s complete.',
                )
              else ...[
                const CharakSectionTitle(label: 'Reviews'),
                const SizedBox(height: 4),
                for (final (i, r) in s.reviews.indexed)
                  CharakReviewTile(
                    review: r,
                    last: i == s.reviews.length - 1,
                    trailing: r.reportStatus != null
                        ? CharakStatusPill(
                            label: r.reportStatus == 'open' ? 'Reported' : 'Report reviewed',
                            tone: CharakStatusTone.muted)
                        : CharakGhostButton(label: 'Report', onPressed: () => _report(context, ref, r)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

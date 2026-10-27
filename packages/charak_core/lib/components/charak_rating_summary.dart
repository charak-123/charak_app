import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/tokens.dart';
import '../models/charak_review.dart';
import 'charak_controls.dart';

/// A doctor's rating: the big number (or "New") with its count, then the
/// sub-rating averages. Ratings are Chandan: they welcome, they aren't tapped.
class CharakRatingSummaryCard extends StatelessWidget {
  final CharakRatingSummary summary;

  /// Shown under the numbers (how the rating is worked out).
  final bool showExplanation;

  const CharakRatingSummaryCard({super.key, required this.summary, this.showExplanation = true});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CharakSpacing.gutter),
      decoration: BoxDecoration(
        color: CharakColors.card,
        borderRadius: const BorderRadius.all(CharakRadius.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            s.isNew || s.overall == null ? 'New' : s.overall!.toStringAsFixed(1),
            style: CharakText.titleLarge.tabular.copyWith(color: CharakColors.ink),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!s.isNew && s.overall != null)
                CharakStarRating(value: s.overall!.round(), size: 16, gap: 3),
              Text(
                s.count == 1 ? '1 review' : '${s.count} reviews',
                style: CharakText.caption.tabular.copyWith(color: CharakColors.inkMuted),
              ),
            ]),
          ),
        ]),
        if (s.isNew) ...[
          const SizedBox(height: 6),
          Text(
            'An average is shown from ${s.minReviewsShown} reviews.',
            style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
          ),
        ] else ...[
          const SizedBox(height: 12),
          for (final e in charakReviewDimensions.entries)
            if (s.dimensions[e.key] != null) _DimensionBar(label: e.value, value: s.dimensions[e.key]!),
        ],
        if (showExplanation && s.explanation.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(s.explanation, style: charakHintStyle),
        ],
      ]),
    );
  }
}

class _DimensionBar extends StatelessWidget {
  final String label;
  final double value;
  const _DimensionBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(flex: 5, child: Text(label, style: CharakText.caption.copyWith(color: CharakColors.ink))),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(CharakRadius.pill),
              child: LinearProgressIndicator(
                value: (value / 5).clamp(0, 1),
                minHeight: 6,
                backgroundColor: CharakColors.border,
                color: CharakColors.chandan,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text(value.toStringAsFixed(1),
                textAlign: TextAlign.right, style: CharakText.caption.tabular.copyWith(color: CharakColors.ink)),
          ),
        ]),
      );
}

/// One review: stars, when, and the comment. Never who wrote it.
class CharakReviewTile extends StatelessWidget {
  final CharakReview review;
  final bool last;
  final Widget? trailing;
  const CharakReviewTile({super.key, required this.review, this.last = false, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: CharakColors.border)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CharakStarRating(value: review.overall, size: 14, gap: 2),
            const SizedBox(width: 8),
            Text(
              'Verified patient · ${DateFormat('MMM y').format(review.createdAt)}${review.edited ? ' · edited' : ''}',
              style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
            ),
            const Spacer(),
            if (trailing != null) trailing!,
          ]),
          if (review.comment != null) ...[
            const SizedBox(height: 6),
            Text(review.comment!, style: CharakText.body.copyWith(color: CharakColors.ink)),
          ],
        ]),
      );
}

/// Picking an optional sub-rating: the question, then small tappable stars.
class CharakDimensionPicker extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const CharakDimensionPicker({super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: CharakText.body.copyWith(color: CharakColors.ink))),
          // Five 24px stars and four 4px gaps; an interactive rating fills its width.
          SizedBox(width: 136, child: CharakStarRating(value: value, size: 24, gap: 4, onChanged: onChanged)),
          SizedBox(
            width: 32,
            child: value > 0
                ? IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: 'Clear',
                    onPressed: () => onChanged(0),
                    icon: Icon(LucideIcons.x, size: 16, color: CharakColors.inkMuted),
                  )
                : null,
          ),
        ]),
      );
}

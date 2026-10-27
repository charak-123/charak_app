/// A doctor's rating as the backend works it out (services/reviews.py):
/// the mean of up to the last 200 published reviews, shown only once there
/// are [minReviewsShown]; before that the doctor is "New".
class CharakRatingSummary {
  final int count;

  /// Null while the doctor is new.
  final double? overall;
  final bool isNew;

  /// Courtesy, explanation and punctuality averages (null when new or unrated).
  final Map<String, double?> dimensions;
  final int minReviewsShown;
  final String explanation;
  final List<CharakReview> reviews;

  const CharakRatingSummary({
    required this.count,
    this.overall,
    this.isNew = true,
    this.dimensions = const {},
    this.minReviewsShown = 5,
    this.explanation = '',
    this.reviews = const [],
  });

  factory CharakRatingSummary.fromJson(Map<String, dynamic> j) => CharakRatingSummary(
        count: (j['count'] as num?)?.toInt() ?? 0,
        overall: (j['overall'] as num?)?.toDouble(),
        isNew: j['is_new'] as bool? ?? true,
        dimensions: {
          for (final e in ((j['dimensions'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num?)?.toDouble(),
        },
        minReviewsShown: (j['min_reviews_shown'] as num?)?.toInt() ?? 5,
        explanation: j['explanation'] as String? ?? '',
        reviews: [
          for (final r in (j['reviews'] as List? ?? const []).whereType<Map>())
            CharakReview.fromJson(r.cast<String, dynamic>()),
        ],
      );
}

/// One review as anyone but its author sees it: never who wrote it.
class CharakReview {
  final String id;
  final int overall;
  final int? professionalism;
  final int? communication;
  final int? punctuality;
  final String? comment;
  final DateTime createdAt;
  final bool edited;

  /// The doctor's own report on it, if any: open, upheld or dismissed.
  final String? reportStatus;

  const CharakReview({
    required this.id,
    required this.overall,
    this.professionalism,
    this.communication,
    this.punctuality,
    this.comment,
    required this.createdAt,
    this.edited = false,
    this.reportStatus,
  });

  factory CharakReview.fromJson(Map<String, dynamic> j) => CharakReview(
        id: j['id'] as String,
        overall: (j['overall'] as num).toInt(),
        professionalism: (j['professionalism'] as num?)?.toInt(),
        communication: (j['communication'] as num?)?.toInt(),
        punctuality: (j['punctuality'] as num?)?.toInt(),
        comment: j['comment'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        edited: j['edited'] as bool? ?? false,
        reportStatus: j['report_status'] as String?,
      );
}

/// What each sub-rating asks, in the patient's words.
const charakReviewDimensions = <String, String>{
  'professionalism': 'Courteous and respectful',
  'communication': 'Listened and explained clearly',
  'punctuality': 'On time',
};

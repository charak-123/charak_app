import '../format/charak_format.dart';

/// One price a patient can book (backend services/pricing.py `public_rule`):
/// a channel, first visit or follow-up, a length, and the price in paise.
class CharakPriceOption {
  final String? id;
  final String channel;

  /// `initial` or `follow_up`.
  final String visitCategory;
  final int durationMin;
  final int pricePaise;

  const CharakPriceOption({
    this.id,
    required this.channel,
    this.visitCategory = 'initial',
    required this.durationMin,
    required this.pricePaise,
  });

  factory CharakPriceOption.fromJson(Map<String, dynamic> j) => CharakPriceOption(
        id: j['id'] as String?,
        channel: j['channel'] as String,
        visitCategory: j['visit_category'] as String? ?? 'initial',
        durationMin: (j['duration_min'] as num).toInt(),
        pricePaise: (j['price_paise'] as num).toInt(),
      );

  bool get isFollowUp => visitCategory == 'follow_up';
  bool get isFree => pricePaise == 0;
  double get rupees => pricePaise / 100;

  /// "₹600", or "Free" for a free follow-up.
  String get priceLabel => isFree ? 'Free' : CharakFormat.rupees(rupees);
}

/// What a patient can book with a doctor: GET /doctors/{id}/prices, or for a
/// follow-up GET /bookings/{id}/follow-up-options.
class CharakPriceList {
  /// Channel → options, shortest first. Only channels the doctor offers.
  final Map<String, List<CharakPriceOption>> channels;
  final int? followUpValidityDays;
  final bool offersFollowUpPrices;

  /// For a follow-up: the consultation it continues, and until when.
  final String? followUpOf;
  final DateTime? followUpUntil;

  const CharakPriceList({
    required this.channels,
    this.followUpValidityDays,
    this.offersFollowUpPrices = false,
    this.followUpOf,
    this.followUpUntil,
  });

  factory CharakPriceList.fromJson(Map<String, dynamic> j) => CharakPriceList(
        channels: {
          for (final e in ((j['channels'] as Map?) ?? const {}).entries)
            e.key as String: [
              for (final o in (e.value as List? ?? const []).whereType<Map>())
                CharakPriceOption.fromJson(o.cast<String, dynamic>()),
            ]..sort((a, b) => a.durationMin.compareTo(b.durationMin)),
        },
        followUpValidityDays: (j['follow_up_validity_days'] as num?)?.toInt(),
        offersFollowUpPrices: j['offers_follow_up_prices'] as bool? ?? false,
        followUpOf: j['follow_up_of'] as String?,
        followUpUntil: j['until'] is String ? DateTime.tryParse(j['until'] as String)?.toLocal() : null,
      );

  bool get isFollowUp => followUpOf != null;

  List<CharakPriceOption> optionsFor(String channel) => channels[channel] ?? const [];

  /// The cheapest option on a channel, for "from ₹X".
  CharakPriceOption? cheapest(String channel) {
    final o = optionsFor(channel);
    if (o.isEmpty) return null;
    return o.reduce((a, b) => a.pricePaise <= b.pricePaise ? a : b);
  }
}

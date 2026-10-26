import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

import 'address_picker.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _doctorProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, doctorId) async {
  return await ApiClient.instance.get('/doctors/$doctorId') as Map<String, dynamic>;
});

/// The options to choose from: the doctor's first-visit prices, or for a
/// follow-up the follow-up prices that apply to that consultation (the
/// backend checks it qualifies and says why when it doesn't).
final _optionsProvider =
    FutureProvider.autoDispose.family<CharakPriceList, (String, String?)>((ref, key) async {
  final (doctorId, followUpOf) = key;
  final res = await ApiClient.instance.get(followUpOf == null
      ? '/doctors/$doctorId/prices'
      : '/bookings/$followUpOf/follow-up-options');
  return CharakPriceList.fromJson(res as Map<String, dynamic>);
});

// ── ChannelConfirmScreen ──────────────────────────────────────────────────────

/// The first step of booking: how the visit happens (online or at home), how
/// long it is, and so what it costs. The time comes next, from slots that fit
/// that length. For a home visit, where the doctor should come.
///
/// [extra] may carry `follow_up_of`: the patient is booking the follow-up to
/// that consultation, at the follow-up price.
class ChannelConfirmScreen extends ConsumerStatefulWidget {
  final String doctorId;
  final Map<String, dynamic> extra;
  const ChannelConfirmScreen({super.key, required this.doctorId, this.extra = const {}});
  @override
  ConsumerState<ChannelConfirmScreen> createState() => _State();
}

class _State extends ConsumerState<ChannelConfirmScreen> {
  String? _channel;
  CharakPriceOption? _option;

  /// Which saved address a home visit goes to. The backend books against this
  /// id — it needs the stored coordinates to check the doctor's service radius,
  /// which a typed-in address could never supply.
  String? _addressId;

  String? get _followUpOf => widget.extra['follow_up_of'] as String?;
  bool get _isHome => _channel == 'home_visit';

  void _pick(String channel, CharakPriceOption option) => setState(() {
        _channel = channel;
        _option = option;
      });

  void _proceed(CharakPriceList list) {
    final o = _option!;
    context.push('/book/${widget.doctorId}/slots', extra: {
      ...widget.extra,
      'channel': _channel,
      if (_isHome) 'address_id': _addressId,
      'price_rule_id': o.id,
      'duration_min': o.durationMin,
      'price_paise': o.pricePaise,
      'visit_category': o.visitCategory,
      if (list.followUpUntil != null) 'follow_up_until': list.followUpUntil!.toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_optionsProvider((widget.doctorId, _followUpOf)));
    final doctor = ref.watch(_doctorProvider(widget.doctorId)).valueOrNull;
    final docName = CharakFormat.doctor(doctor?['name'] as String?);
    final radius = doctor?['service_radius_km'];

    return CharakScreen(
      title: _followUpOf != null ? 'Your follow-up' : 'How should the visit happen?',
      subtitle: docName,
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => _followUpOf != null && e is ApiException && e.statusCode == 409
            ? Center(
                child: CharakEmptyState(
                  icon: LucideIcons.calendarX,
                  title: 'Follow-up price not available',
                  message: '${e.message} You can still book a regular consultation.',
                  action: CharakButton(
                    label: 'Book a regular consultation',
                    expand: false,
                    onPressed: () => context.pushReplacement('/book/${widget.doctorId}/channel'),
                  ),
                ),
              )
            : CharakErrorState(
                error: e,
                onRetry: () => ref.invalidate(_optionsProvider((widget.doctorId, _followUpOf)))),
        data: (list) {
          final channels = [
            for (final c in ['online_consult', 'home_visit'])
              if (list.optionsFor(c).isNotEmpty) c,
          ];
          // One choice to make? Make it.
          if (_channel == null && channels.length == 1 && list.optionsFor(channels.first).length == 1) {
            _channel = channels.first;
            _option = list.optionsFor(channels.first).first;
          }
          if (channels.isEmpty) {
            return Center(
              child: CharakEmptyState(
                icon: LucideIcons.calendarX,
                title: list.isFollowUp ? 'No follow-up prices' : 'Not taking bookings',
                message: list.isFollowUp
                    ? "This doctor doesn't offer follow-up prices. You can book a regular consultation."
                    : "This doctor hasn't published prices yet.",
              ),
            );
          }
          final o = _option;
          return Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  if (list.isFollowUp && list.followUpUntil != null) ...[
                    CharakNoteBanner(
                      icon: LucideIcons.calendarClock,
                      leadLabel: 'Follow-up price',
                      message: ' for your earlier consultation. Book a time up to '
                          '${DateFormat('EEE d MMM').format(list.followUpUntil!)}.',
                      tone: CharakStatusTone.primary,
                    ),
                    const SizedBox(height: 14),
                  ],
                  for (final c in channels) ...[
                    _ChannelCard(
                      channel: c,
                      options: list.optionsFor(c),
                      selectedChannel: _channel,
                      selected: _channel == c ? _option : null,
                      radius: radius,
                      onPick: (option) => _pick(c, option),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_isHome) ...[
                    const SizedBox(height: 6),
                    const CharakSectionTitle(label: 'Where should the doctor come?'),
                    const SizedBox(height: 10),
                    AddressPickerSection(
                      selectedId: _addressId,
                      onSelected: (id) => setState(() => _addressId = id),
                    ),
                  ],
                ],
              ),
            ),
            CharakCtaBar(
              header: o == null
                  ? Text('Pick how long the visit is', textAlign: TextAlign.center, style: charakHintStyle)
                  : (_isHome && _addressId == null
                      ? Text('Choose the address for the visit',
                          textAlign: TextAlign.center, style: charakHintStyle)
                      : null),
              children: [
                Expanded(
                  child: CharakButton(
                    label: o == null
                        ? 'Choose a time'
                        : 'Choose a time · ${o.durationMin} min, ${o.priceLabel}',
                    trailingIcon: LucideIcons.arrowRight,
                    onPressed: o != null && (!_isHome || _addressId != null) ? () => _proceed(list) : null,
                  ),
                ),
              ],
            ),
          ]);
        },
      ),
    );
  }
}

// ── Channel card ──────────────────────────────────────────────────────────────

/// A channel: what it is, then one chip per length with its price. The
/// chosen chip, and the card, take the 2px blue outline.
class _ChannelCard extends StatelessWidget {
  final String channel;
  final List<CharakPriceOption> options;
  final String? selectedChannel;
  final CharakPriceOption? selected;
  final Object? radius;
  final ValueChanged<CharakPriceOption> onPick;

  const _ChannelCard({
    required this.channel,
    required this.options,
    required this.selectedChannel,
    required this.selected,
    required this.radius,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final home = channel == 'home_visit';
    final active = selectedChannel == channel;
    final (successBg, _) = charakToneColors(CharakStatusTone.success);
    return AnimatedContainer(
      duration: CharakMotion.standard,
      curve: CharakCurves.standard,
      decoration: BoxDecoration(
        color: CharakColors.card,
        borderRadius: const BorderRadius.all(CharakRadius.card),
        // Selected: a 2px blue outline, no shadow (V2 is flat).
        border: Border.all(color: active ? CharakColors.primary : Colors.transparent, width: 2),
      ),
      padding: const EdgeInsets.all(CharakSpacing.gutter - 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: home ? successBg : CharakColors.primarySoft,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
            ),
            alignment: Alignment.center,
            child: Icon(home ? LucideIcons.house : LucideIcons.video,
                color: home ? CharakColors.success : CharakColors.primaryDeep, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(home ? 'Home visit' : 'Online consult',
                  style: CharakText.titleSmall.copyWith(fontSize: 17, color: CharakColors.ink)),
              const SizedBox(height: 3),
              Text(
                home
                    ? 'The doctor comes to you${radius != null ? ' (within $radius km)' : ''}. '
                        'Procedures, if any, are billed after at fixed rates.'
                    : 'Video call in CHARAK, paid before the call.',
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted, height: 1.5),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in options)
            CharakChip(
              label: '${o.durationMin} min · ${o.priceLabel}',
              numeric: true,
              selected: selected == o,
              onTap: () => onPick(o),
            ),
        ]),
      ]),
    );
  }
}

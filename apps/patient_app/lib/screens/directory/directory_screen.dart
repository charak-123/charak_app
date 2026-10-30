import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../../specialties.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _directoryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, _DirectoryParams>((ref, params) async {
  final qs = <String, String>{};
  if (params.category.isNotEmpty) qs['category'] = params.category;
  if (params.channel.isNotEmpty)  qs['channel']  = params.channel;
  final query = qs.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  final res = await ApiClient.instance.get('/doctors/search${query.isNotEmpty ? '?$query' : ''}');
  return res as Map<String, dynamic>;
});

class _DirectoryParams {
  final String category;
  final String channel;
  const _DirectoryParams({this.category='', this.channel=''});
  @override bool operator ==(o) => o is _DirectoryParams &&
      o.category == category && o.channel == channel;
  @override int get hashCode => Object.hash(category, channel);
}

// ── Filter chips data (matches wireframe: All / Online / Home Visit + sort) ────

const _channelFilters = [
  ('All',            ''),
  ('Online',         'online_consult'),
  ('Home visit',     'home_visit'),
];

// ── DirectoryScreen ───────────────────────────────────────────────────────────

class DirectoryScreen extends ConsumerStatefulWidget {
  final String? initialQuery;

  /// Set when the patient is choosing another doctor after one didn't attend
  /// (help_screen.dart): {replaces_incident_id, budget_paise, exclude_doctor_id,
  /// channel}. Only doctors whose shortest visit fits the budget are listed,
  /// and the choice carries through to booking.
  final Map<String, dynamic>? replacement;
  const DirectoryScreen({super.key, this.initialQuery, this.replacement});
  @override
  ConsumerState<DirectoryScreen> createState() => _State();
}

class _State extends ConsumerState<DirectoryScreen> {
  String _channel  = '';
  late String _category;
  bool _sortByPrice = false;

  @override
  void initState() {
    super.initState();
    // A channel value looks like "online_consult"/"home_visit"; anything else
    // is treated as a specialty category name (or empty = all doctors).
    final r = widget.replacement;
    if (r != null) {
      _channel = r['channel'] as String? ?? '';
      _category = '';
      return;
    }
    if (widget.initialQuery == 'home_visit' || widget.initialQuery == 'online_consult') {
      _channel = widget.initialQuery!;
      _category = '';
    } else {
      _category = widget.initialQuery ?? '';
    }
  }

  _DirectoryParams get _params => _DirectoryParams(category: _category, channel: _channel);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_directoryProvider(_params));
    return CharakScreen(
      title: widget.replacement != null
          ? 'Choose another doctor'
          : (_category.isNotEmpty
              ? specialtyName(_category)
              : switch (_channel) {
                  'home_visit' => 'Home visits',
                  'online_consult' => 'Online consults',
                  _ => 'All doctors',
                }),
      body: Column(children: [
        // Online, home visit or both: the first thing to choose, so it leads
        // the screen, and stays put while the list reloads under it.
        if (widget.replacement == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: CharakSegmented<String>(
              value: _channel,
              onChanged: (v) => setState(() => _channel = v),
              segments: [
                for (final (label, value) in _channelFilters)
                  CharakSegment(value: value, label: label),
              ],
            ),
          ),
        Expanded(child: async.when(
        // `.skel` — doctor cards are avatar rows with a price footer, so the
        // list preset mirrors them directly under the real top bar.
        loading: () => const CharakSkeletonList(
          count: 4,
          padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
        ),
        error: (e, _) => CharakErrorState(error: e, onRetry: () => ref.invalidate(_directoryProvider(_params))),
        data: (data) {
          var items = List<Map<String, dynamic>>.from(data['items'] as List);
          final r = widget.replacement;
          final budget = (r?['budget_paise'] as num?)?.toInt();
          if (r != null) {
            items = items
                .where((d) => d['id'] != r['exclude_doctor_id'] && _cheapestPrice(d) * 100 <= (budget ?? 0))
                .toList();
          }
          if (_sortByPrice) {
            items = [...items]..sort((a, b) => _cheapestPrice(a).compareTo(_cheapestPrice(b)));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              // The count on the left, the sort hard right.
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 0, 14),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      '${items.length} ${items.length == 1 ? 'doctor' : 'doctors'}'
                      '${switch (_channel) {
                        'home_visit' => ' who visit at home',
                        'online_consult' => ' for online consults',
                        _ => '',
                      }}',
                      style: CharakText.label.tabular.copyWith(color: CharakColors.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CharakChip(
                    label: 'Lowest price',
                    icon: LucideIcons.arrowUpDown,
                    selected: _sortByPrice,
                    onTap: () => setState(() => _sortByPrice = !_sortByPrice),
                  ),
                ]),
              ),

              if (r != null) ...[
                CharakNoteBanner(
                  icon: LucideIcons.wallet,
                  leadLabel: 'Covered by your earlier payment',
                  message: ' up to ${CharakFormat.rupees((budget ?? 0) / 100)}. Anything left over is refunded.',
                  tone: CharakStatusTone.primary,
                ),
                const SizedBox(height: 12),
              ],

              if (items.isEmpty)
                CharakEmptyState(
                  icon: LucideIcons.searchX,
                  title: 'No doctors here yet',
                  message: _category.isNotEmpty
                      ? '${specialtyName(_category)} is live but no doctor has opened slots '
                          'nearby. Try another specialty.'
                      : 'No doctors have opened slots nearby yet.',
                  action: CharakButton(
                    label: 'Browse all doctors',
                    variant: CharakButtonVariant.outline,
                    onPressed: () => setState(() { _category = ''; _channel = ''; }),
                  ),
                )
              else
                ...items.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DoctorCard(doctor: d, replacement: widget.replacement, channel: _channel),
                )),
            ],
          );
        },
      )),
      ]),
    );
  }

  /// The lowest first-visit price, on the chosen channel when there is one.
  double _cheapestPrice(Map<String, dynamic> doctor) {
    final pricing = List<Map<String, dynamic>>.from(doctor['doctor_pricing'] as List? ?? [])
        .where((p) => _channel.isEmpty || p['channel'] == _channel)
        .toList();
    if (pricing.isEmpty) return double.infinity;
    return pricing.map((p) => (p['price'] as num).toDouble()).reduce((a, b) => a < b ? a : b);
  }
}

// ── Doctor card ───────────────────────────────────────────────────────────────

/// Doctor card (design-system § Components · Doctor card): rounded-square
/// avatar, wide name, specialty line and a Chandan rating chip; a hairline;
/// then the channels and the fee in narrow tabular figures.
class _DoctorCard extends StatelessWidget {
  final Map<String, dynamic> doctor;
  final Map<String, dynamic>? replacement;

  /// The channel the list is filtered to ('' for all): its price is the one
  /// shown.
  final String channel;
  const _DoctorCard({required this.doctor, this.replacement, this.channel = ''});

  @override
  Widget build(BuildContext context) {
    final name      = CharakFormat.doctor(doctor['name'] as String?);
    final photoUrl  = doctor['photo_url'] as String?;
    final rating    = (doctor['rating_avg'] as num?)?.toDouble() ?? 0;
    final category  = specialtyName((doctor['categories'] as Map?)?['name'] as String?);
    final creds     = doctor['qualifications'] as String? ?? category;
    final pricing   = List<Map<String,dynamic>>.from(doctor['doctor_pricing'] as List? ?? []);
    final online    = doctor['offers_online_consult'] as bool? ?? false;
    final home      = doctor['offers_home_visit'] as bool? ?? false;
    final verified  = doctor['verified'] as bool? ?? true;

    final shown = channel.isEmpty ? pricing : pricing.where((p) => p['channel'] == channel).toList();
    final anyPrice = shown.isEmpty
        ? null
        : shown.reduce((a, b) => (a['price'] as num) <= (b['price'] as num) ? a : b);

    return CharakCard(
      onTap: () => context.push('/doctor/${doctor['id']}', extra: replacement),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // The photo opens full size; the rest of the card opens the profile.
          CharakAvatar(name: name, imageUrl: photoUrl, radius: 26, tone: 2, viewable: true),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // The name gets the whole row (two lines if it must) and the
            // rating sits under it: beside it, a 360dp phone cut every
            // name to "Dr. Meera K…".
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Flexible(
                child: Text(name,
                    style: CharakText.titleSmall.copyWith(fontSize: 19),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              if (verified) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(LucideIcons.badgeCheck, size: 17, color: CharakColors.success),
                ),
              ],
            ]),
            if (creds.isNotEmpty)
              Text(creds,
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            rating > 0
                ? CharakRatingChip(rating: rating.toStringAsFixed(1))
                : const CharakBadge(label: 'New', variant: CharakBadgeVariant.requested),
          ])),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: CharakColors.border))),
          child: Row(children: [
            if (online) const CharakBadge(label: 'Online', variant: CharakBadgeVariant.primary),
            if (online && home) const SizedBox(width: 6),
            if (home) const CharakBadge(label: 'Home visit', variant: CharakBadgeVariant.requested),
            const Spacer(),
            if (anyPrice != null)
              Text.rich(TextSpan(children: [
                if (channel.isEmpty && shown.length > 1)
                  TextSpan(text: 'from ', style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                TextSpan(
                    text: CharakFormat.rupees(anyPrice['price'] as num),
                    style: CharakText.numeric.copyWith(color: CharakColors.ink)),
                TextSpan(
                    text: ' /${(anyPrice['base_duration_min'] as num?)?.toInt() ?? 15} min',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ])),
          ]),
        ),
      ]),
    );
  }
}

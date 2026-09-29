import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

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
  ('Home Visit',     'home_visit'),
];

// ── DirectoryScreen ───────────────────────────────────────────────────────────

class DirectoryScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  const DirectoryScreen({super.key, this.initialQuery});
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
    return Scaffold(
      backgroundColor: CharakColors.ground,
      appBar: CharakTopBar(
        title: _category.isNotEmpty ? _category : 'All doctors',
        trailingIcon: Icons.tune,
        onTrailingTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Filters: radius, price, availability')),
        ),
      ),
      body: async.when(
        // `.skel` — doctor cards are avatar rows with a price footer, so the
        // list preset mirrors them directly under the real top bar.
        loading: () => const CharakSkeletonList(
          count: 4,
          padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          var items = List<Map<String, dynamic>>.from(data['items'] as List);
          if (_sortByPrice) {
            items = [...items]..sort((a, b) => _cheapestPrice(a).compareTo(_cheapestPrice(b)));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${items.length} doctors near you',
                      style: CharakText.label.tabular.copyWith(color: CharakColors.ink)),
                  const Spacer(),
                  Icon(Icons.place_outlined, size: 16, color: CharakColors.inkMuted),
                  const SizedBox(width: 4),
                  Text('Navi Mumbai', style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                ]),
              ),

              // Filters left, sort pushed hard right.
              Row(children: [
                Expanded(
                  child: CharakChipRow(
                    children: _channelFilters
                        .map((f) => CharakChip(
                              label: f.$1,
                              selected: _channel == f.$2,
                              onTap: () => setState(() => _channel = f.$2),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(width: 8),
                CharakChip(
                  label: 'Price',
                  icon: Icons.swap_vert_rounded,
                  selected: _sortByPrice,
                  onTap: () => setState(() => _sortByPrice = !_sortByPrice),
                ),
              ]),
              const SizedBox(height: 14),

              if (items.isEmpty)
                CharakEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No doctors here yet',
                  message: _category.isNotEmpty
                      ? '$_category is live but no doctor has opened slots '
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
                  child: _DoctorCard(doctor: d),
                )),
            ],
          );
        },
      ),
    );
  }

  double _cheapestPrice(Map<String, dynamic> doctor) {
    final pricing = List<Map<String, dynamic>>.from(doctor['doctor_pricing'] as List? ?? []);
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
  const _DoctorCard({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final name      = doctor['name'] as String? ?? 'Doctor';
    final photoUrl  = doctor['photo_url'] as String?;
    final rating    = (doctor['rating_avg'] as num?)?.toDouble() ?? 0;
    final category  = (doctor['categories'] as Map?)?['name'] as String? ?? '';
    final creds     = doctor['qualifications'] as String? ?? category;
    final pricing   = List<Map<String,dynamic>>.from(doctor['doctor_pricing'] as List? ?? []);
    final online    = doctor['offers_online_consult'] as bool? ?? false;
    final home      = doctor['offers_home_visit'] as bool? ?? false;
    final verified  = doctor['verified'] as bool? ?? true;

    final onlinePrice = pricing.where((p) => p['channel'] == 'online_consult').firstOrNull;
    final anyPrice = onlinePrice ?? pricing.firstOrNull;

    return CharakCard(
      onTap: () => context.push('/doctor/${doctor['id']}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CharakAvatar(name: name, imageUrl: photoUrl, radius: 26, tone: 2),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(name,
                    style: CharakText.titleSmall.copyWith(fontSize: 19),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (verified) ...[
                const SizedBox(width: 6),
                Icon(Icons.verified_rounded, size: 17, color: CharakColors.success),
              ],
            ]),
            if (creds.isNotEmpty)
              Text(creds,
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          rating > 0
              ? CharakRatingChip(rating: rating.toStringAsFixed(1))
              : const CharakBadge(label: 'New', variant: CharakBadgeVariant.requested),
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
                TextSpan(
                    text: '₹${(anyPrice['price'] as num).toStringAsFixed(0)}',
                    style: CharakText.numeric.copyWith(color: CharakColors.ink)),
                TextSpan(
                    text: ' /15 min',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ])),
          ]),
        ),
      ]),
    );
  }
}

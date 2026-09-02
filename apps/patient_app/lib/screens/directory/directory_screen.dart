import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _directoryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, _DirectoryParams>((ref, params) async {
  final qs = <String, String>{};
  if (params.q.isNotEmpty)        qs['q']        = params.q;
  if (params.category.isNotEmpty) qs['category'] = params.category;
  if (params.channel.isNotEmpty)  qs['channel']  = params.channel;
  if (params.minRating > 0)       qs['min_rating'] = params.minRating.toString();
  final query = qs.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  final res = await ApiClient.instance.get('/doctors/search${query.isNotEmpty ? '?$query' : ''}');
  return res as Map<String, dynamic>;
});

class _DirectoryParams {
  final String q;
  final String category;
  final String channel;
  final double minRating;
  const _DirectoryParams({this.q='', this.category='', this.channel='', this.minRating=0});
  @override bool operator ==(o) => o is _DirectoryParams &&
      o.q == q && o.category == category && o.channel == channel && o.minRating == minRating;
  @override int get hashCode => Object.hash(q, category, channel, minRating);
}

// ── Filter chips data ─────────────────────────────────────────────────────────

const _channelFilters = [
  ('All',            ''),
  ('Online Consult', 'online_consult'),
  ('Home Visit',     'home_visit'),
];

const _ratingFilters = [
  ('Any Rating', 0.0),
  ('4+ Stars',   4.0),
  ('4.5+ Stars', 4.5),
];

// ── DirectoryScreen ───────────────────────────────────────────────────────────

class DirectoryScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  const DirectoryScreen({super.key, this.initialQuery});
  @override
  ConsumerState<DirectoryScreen> createState() => _State();
}

class _State extends ConsumerState<DirectoryScreen> {
  late final _searchCtrl = TextEditingController(text: widget.initialQuery ?? '');
  String _q         = '';
  String _channel   = '';
  String _category  = '';
  double _minRating = 0;

  @override
  void initState() {
    super.initState();
    _q = widget.initialQuery ?? '';
    // If initialQuery looks like a channel, set filter instead of search text
    if (widget.initialQuery == 'home_visit' || widget.initialQuery == 'online_consult') {
      _channel = widget.initialQuery!;
      _q = '';
      _searchCtrl.text = '';
    } else if (widget.initialQuery != null && !widget.initialQuery!.contains(' ') &&
        widget.initialQuery!.length > 3) {
      // Likely a specialty category name
      _category = widget.initialQuery!;
      _q = '';
      _searchCtrl.text = '';
    }
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  _DirectoryParams get _params => _DirectoryParams(
    q: _q, category: _category, channel: _channel, minRating: _minRating,
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_directoryProvider(_params));
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
        title: TextField(
          controller: _searchCtrl,
          autofocus: _q.isEmpty && _category.isEmpty,
          style: CharakText.body,
          decoration: InputDecoration(
            hintText: 'Search doctors...',
            hintStyle: CharakText.body.copyWith(color: CharakColors.inkMuted),
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) => setState(() { _q = v; _category = ''; }),
        ),
        actions: [
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() { _q = ''; _category = ''; _searchCtrl.clear(); }),
            ),
        ],
      ),
      body: Column(children: [
        // Filter chips
        SizedBox(
          height: 44,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            scrollDirection: Axis.horizontal,
            children: [
              ..._channelFilters.map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f.$1),
                  selected: _channel == f.$2,
                  onSelected: (_) => setState(() => _channel = f.$2),
                  selectedColor: CharakColors.primarySoft,
                  checkmarkColor: CharakColors.primary,
                  labelStyle: CharakText.caption.copyWith(
                    color: _channel == f.$2 ? CharakColors.primary : CharakColors.ink,
                  ),
                ),
              )),
              ..._ratingFilters.skip(1).map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f.$1),
                  selected: _minRating == f.$2,
                  onSelected: (_) => setState(() =>
                    _minRating = _minRating == f.$2 ? 0 : f.$2),
                  selectedColor: CharakColors.primarySoft,
                  checkmarkColor: CharakColors.primary,
                  labelStyle: CharakText.caption.copyWith(
                    color: _minRating == f.$2 ? CharakColors.primary : CharakColors.ink,
                  ),
                ),
              )),
            ],
          ),
        ),

        // Results
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (data) {
              final items = List<Map<String, dynamic>>.from(data['items'] as List);
              if (items.isEmpty) return _EmptyState(query: _q.isNotEmpty ? _q : _category);
              return ListView.separated(
                padding: const EdgeInsets.all(CharakSpacing.base),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _DoctorCard(doctor: items[i]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.search_off, size: 48, color: CharakColors.border),
      const SizedBox(height: 12),
      Text(query.isNotEmpty ? 'No doctors found for "$query"' : 'No doctors found',
          style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
    ]),
  );
}

class _DoctorCard extends StatelessWidget {
  final Map<String, dynamic> doctor;
  const _DoctorCard({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final name      = doctor['name'] as String? ?? 'Doctor';
    final photoUrl  = doctor['photo_url'] as String?;
    final rating    = (doctor['rating_avg'] as num?)?.toDouble() ?? 0;
    final category  = (doctor['categories'] as Map?)?.get('name') ?? '';
    final pricing   = List<Map<String,dynamic>>.from(doctor['doctor_pricing'] as List? ?? []);
    final online    = doctor['offers_online_consult'] as bool? ?? false;
    final home      = doctor['offers_home_visit'] as bool? ?? false;

    final onlinePrice = pricing.where((p) => p['channel'] == 'online_consult').firstOrNull;
    final homePrice   = pricing.where((p) => p['channel'] == 'home_visit').firstOrNull;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(CharakRadius.card),
        side: const BorderSide(color: CharakColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.all(CharakRadius.card),
        onTap: () => context.push('/doctor/${doctor['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Avatar
            CircleAvatar(
              radius: 28,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              backgroundColor: CharakColors.primarySoft,
              child: photoUrl == null
                  ? Text(name[0].toUpperCase(),
                      style: CharakText.h2.copyWith(color: CharakColors.primary))
                  : null,
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: CharakText.bodyMed),
              if (category.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(category, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ],
              const SizedBox(height: 6),

              // Rating
              Row(children: [
                const Icon(Icons.star, size: 14, color: CharakColors.warning),
                const SizedBox(width: 3),
                Text(rating > 0 ? rating.toStringAsFixed(1) : 'New',
                    style: CharakText.caption),
                const SizedBox(width: 12),
                // Channel badges
                if (online) _ChannelBadge(label: 'Online', color: CharakColors.primary),
                if (home) ...[
                  const SizedBox(width: 4),
                  _ChannelBadge(label: 'Home', color: CharakColors.success),
                ],
              ]),

              const SizedBox(height: 6),
              // Pricing
              Row(children: [
                if (onlinePrice != null)
                  Text('₹${(onlinePrice['price'] as num).toStringAsFixed(0)} online',
                      style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                if (onlinePrice != null && homePrice != null)
                  Text(' · ', style: CharakText.caption.copyWith(color: CharakColors.border)),
                if (homePrice != null)
                  Text('₹${(homePrice['price'] as num).toStringAsFixed(0)} home',
                      style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ]),
            ])),

            const Icon(Icons.chevron_right, color: CharakColors.inkMuted),
          ]),
        ),
      ),
    );
  }
}

class _ChannelBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _ChannelBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.all(CharakRadius.pill),
    ),
    child: Text(label, style: CharakText.micro.copyWith(color: color)),
  );
}

extension _MapExt on Map {
  dynamic get(String key) => this[key];
}

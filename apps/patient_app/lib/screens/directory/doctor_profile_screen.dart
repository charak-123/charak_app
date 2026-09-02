import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

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
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (doc) => _Body(doctor: doc),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> doctor;
  const _Body({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final name       = doctor['name'] as String? ?? 'Doctor';
    final photoUrl   = doctor['photo_url'] as String?;
    final bio        = doctor['bio'] as String?;
    final rating     = (doctor['rating_avg'] as num?)?.toDouble() ?? 0;
    final category   = (doctor['categories'] as Map?)?.get('name') ?? '';
    final pricing    = List<Map<String,dynamic>>.from(doctor['doctor_pricing'] as List? ?? []);
    final procedures = List<Map<String,dynamic>>.from(doctor['doctor_procedures'] as List? ?? []);
    final threshold  = doctor['procedure_review_threshold'];
    final online     = doctor['offers_online_consult'] as bool? ?? false;
    final home       = doctor['offers_home_visit'] as bool? ?? false;

    final onlinePricing = pricing.where((p) => p['channel'] == 'online_consult').firstOrNull;
    final homePricing   = pricing.where((p) => p['channel'] == 'home_visit').firstOrNull;

    return CustomScrollView(slivers: [
      SliverAppBar(
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
        floating: true,
        title: Text(name, style: CharakText.bodyMed),
      ),

      SliverToBoxAdapter(
        child: Column(children: [
          // Hero card
          Container(
            color: CharakColors.bg,
            padding: const EdgeInsets.all(CharakSpacing.lg),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                backgroundColor: CharakColors.primarySoft,
                child: photoUrl == null
                    ? Text(name[0].toUpperCase(),
                        style: CharakText.h1.copyWith(color: CharakColors.primary))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: CharakText.h2),
                if (category.isNotEmpty)
                  Text(category, style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.star, size: 14, color: CharakColors.warning),
                  const SizedBox(width: 3),
                  Text(rating > 0 ? rating.toStringAsFixed(1) : 'New',
                      style: CharakText.caption),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: CharakColors.primarySoft,
                      borderRadius: BorderRadius.all(CharakRadius.pill),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.verified, size: 12, color: CharakColors.primary),
                      const SizedBox(width: 3),
                      Text('Verified', style: CharakText.micro.copyWith(color: CharakColors.primary)),
                    ]),
                  ),
                ]),
              ])),
            ]),
          ),

          if (bio != null && bio.isNotEmpty) ...[
            const Divider(height: 1, color: CharakColors.border),
            _Section(
              title: 'About',
              child: Text(bio, style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
            ),
          ],

          const Divider(height: 1, color: CharakColors.border),

          // Pricing
          _Section(
            title: 'Consultation Fees',
            child: Column(children: [
              if (onlinePricing != null)
                _PricingRow(
                  icon: Icons.videocam_outlined,
                  label: 'Online Consult',
                  price: (onlinePricing['price'] as num).toDouble(),
                  extra: (onlinePricing['extra_rate_per_15min'] as num?)?.toDouble() ?? 0,
                ),
              if (onlinePricing != null && homePricing != null)
                const SizedBox(height: 8),
              if (homePricing != null)
                _PricingRow(
                  icon: Icons.home_outlined,
                  label: 'Home Visit',
                  price: (homePricing['price'] as num).toDouble(),
                  extra: (homePricing['extra_rate_per_15min'] as num?)?.toDouble() ?? 0,
                ),
            ]),
          ),

          if (procedures.isNotEmpty) ...[
            const Divider(height: 1, color: CharakColors.border),
            _Section(
              title: 'Procedures',
              child: Column(
                children: procedures.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p['name'] as String, style: CharakText.body),
                      Text('₹${(p['price'] as num).toStringAsFixed(0)}',
                          style: CharakText.bodyMed),
                    ],
                  ),
                )).toList(),
              ),
            ),
            if (threshold != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 0, CharakSpacing.base, 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.all(CharakRadius.card),
                    border: Border.all(color: CharakColors.warning.withOpacity(0.5)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 14, color: CharakColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Procedure bills above ₹${(threshold as num).toStringAsFixed(0)} '
                        'require senior review before payment.',
                        style: CharakText.micro.copyWith(color: CharakColors.warning),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ],

          const SizedBox(height: 100),
        ]),
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    color: CharakColors.bg,
    padding: const EdgeInsets.all(CharakSpacing.base),
    width: double.infinity,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: CharakText.h2),
      const SizedBox(height: 10),
      child,
    ]),
  );
}

class _PricingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double price;
  final double extra;
  const _PricingRow({required this.icon, required this.label, required this.price, required this.extra});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: CharakColors.inkMuted),
    const SizedBox(width: 8),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: CharakText.body),
      if (extra > 0)
        Text('+₹${extra.toStringAsFixed(0)} per extra 15 min',
            style: CharakText.micro.copyWith(color: CharakColors.inkMuted)),
    ])),
    Text('₹${price.toStringAsFixed(0)}', style: CharakText.bodyMed),
  ]);
}

// ── Book CTA (persistent bottom bar) ─────────────────────────────────────────

// Added via a separate Scaffold overlay routed from the same screen
// so the sliver list isn't cut off by a bottomSheet.
// Instead we use a floating FAB-like button pinned via a Stack.

extension _MapExt on Map {
  dynamic get(String key) => this[key];
}

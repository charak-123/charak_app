import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

// ── Specialty data ────────────────────────────────────────────────────────────

const _specialties = [
  ('General Physician', Icons.local_hospital_outlined,  Color(0xFF2F6FED)),
  ('Orthopedic',        Icons.accessibility_outlined,   Color(0xFF1FAA6D)),
  ('Nurse',             Icons.health_and_safety_outlined,Color(0xFFE0930B)),
  ('Cardiology',        Icons.favorite_outline,          Color(0xFFE0473E)),
  ('Dermatology',       Icons.face_outlined,             Color(0xFF9B59B6)),
  ('Gynecology',        Icons.pregnant_woman_outlined,   Color(0xFFE91E8C)),
  ('Pediatrics',        Icons.child_care_outlined,       Color(0xFF2196F3)),
  ('Dentistry',         Icons.sentiment_satisfied_alt,   Color(0xFF00BCD4)),
  ('Physiotherapy',     Icons.fitness_center_outlined,   Color(0xFF4CAF50)),
];

// ── HomeTab ───────────────────────────────────────────────────────────────────

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final name = (user?['name'] as String?)?.split(' ').first ?? 'there';

    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: CharakColors.bg,
          floating: true,
          snap: true,
          elevation: 0,
          expandedHeight: 120,
          flexibleSpace: FlexibleSpaceBar(
            background: Padding(
              padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 52, CharakSpacing.base, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hello, $name 👋', style: CharakText.h2),
                const SizedBox(height: 2),
                Text('How can we help you today?',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ]),
            ),
          ),
        ),

        // Search bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 12, CharakSpacing.base, 0),
            child: GestureDetector(
              onTap: () => context.push('/directory'),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: CharakColors.bg,
                  borderRadius: BorderRadius.all(CharakRadius.pill),
                  border: Border.all(color: CharakColors.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Icon(Icons.search, color: CharakColors.inkMuted, size: 20),
                  const SizedBox(width: 10),
                  Text('Search doctors, specialties...',
                      style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
                ]),
              ),
            ),
          ),
        ),

        // Section: specialties
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(CharakSpacing.base, 24, CharakSpacing.base, 8),
            child: Text('Browse by Specialty', style: CharakText.h2),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: CharakSpacing.base),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _SpecialtyCard(
                label: _specialties[i].$1,
                icon: _specialties[i].$2,
                color: _specialties[i].$3,
              ),
              childCount: _specialties.length,
            ),
          ),
        ),

        // Section: quick actions
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(CharakSpacing.base, 24, CharakSpacing.base, 8),
            child: Text('Quick Actions', style: CharakText.h2),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 0, CharakSpacing.base, 24),
            child: Row(children: [
              Expanded(child: _QuickCard(
                icon: Icons.home_outlined, label: 'Home Visit',
                color: CharakColors.success,
                onTap: () => context.push('/directory', extra: 'home_visit'),
              )),
              const SizedBox(width: 10),
              Expanded(child: _QuickCard(
                icon: Icons.videocam_outlined, label: 'Online Consult',
                color: CharakColors.primary,
                onTap: () => context.push('/directory', extra: 'online_consult'),
              )),
            ]),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ]),
    );
  }
}

class _SpecialtyCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _SpecialtyCard({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/directory', extra: label),
    child: Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(CharakRadius.card),
        side: const BorderSide(color: CharakColors.border),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(label,
              style: CharakText.micro.copyWith(color: CharakColors.ink),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    ),
  );
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 80,
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.all(CharakRadius.card),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(label, style: CharakText.bodyMed.copyWith(color: color)),
      ]),
    ),
  );
}

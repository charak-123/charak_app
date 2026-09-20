import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

const _specialties = [
  ('General Physician', Icons.medical_services_outlined),
  ('Orthopedic',        Icons.accessibility_new_outlined),
  ('Nurse',             Icons.vaccines_outlined),
  ('Cardiology',        Icons.monitor_heart_outlined),
  ('Dermatology',       Icons.water_drop_outlined),
  ('Gynecology',        Icons.child_friendly_outlined),
  ('Pediatrics',        Icons.sentiment_satisfied_outlined),
  ('Physiotherapy',     Icons.fitness_center_outlined),
];

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final firstName = ((user?['name'] as String?) ?? 'there').split(' ').first;

    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          // `.body` — 8/20/24 with the home screen's 12px top override.
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── `.h-greet` ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_greeting(),
                        style: CharakText.caption.copyWith(
                          color: CharakColors.inkMuted,
                          fontWeight: FontWeight.w500,
                        )),
                    const SizedBox(height: 1),
                    Text(firstName,
                        style: CharakText.h1.copyWith(letterSpacing: -0.01 * 22)),
                  ]),
                ),
                // `.iconbtn` with the `.dot` unread marker.
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {},
                      child: Stack(alignment: Alignment.center, children: [
                        const Icon(Icons.notifications_none_rounded,
                            size: 21, color: CharakColors.ink),
                        Positioned(
                          top: 10,
                          right: 11,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: CharakColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),

            // ── `.h-search` ────────────────────────────────────────────────
            GestureDetector(
              onTap: () => context.push('/directory'),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: CharakColors.bg,
                  borderRadius: const BorderRadius.all(CharakRadius.button),
                  border: Border.all(color: CharakColors.border),
                ),
                child: Row(children: [
                  const Icon(Icons.search, size: 18, color: CharakColors.inkMuted),
                  const SizedBox(width: 10),
                  Text('Search doctors or specialties',
                      style: CharakText.body.copyWith(
                        fontSize: 14,
                        color: CharakColors.inkMuted,
                      )),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            const CharakSectionTitle(label: 'Book by specialty'),
            const SizedBox(height: 10),

            // ── `.spec-grid` — two columns, 10px gutters ───────────────────
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 62,
              ),
              itemCount: _specialties.length,
              itemBuilder: (_, i) =>
                  _SpecCard(label: _specialties[i].$1, icon: _specialties[i].$2),
            ),

            // ── `.spec-more` — full-width primary link row ─────────────────
            GestureDetector(
              onTap: () => context.push('/directory'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6 + 10, 4, 6),
                child: Row(children: [
                  const Icon(Icons.add, size: 16, color: CharakColors.primary),
                  const SizedBox(width: 8),
                  Text('All specialties',
                      style: CharakText.bodyMed.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: CharakColors.primary,
                      )),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// `.spec` — bordered tile with a 38px tinted icon chip and a 13.5px/600 name.
class _SpecCard extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SpecCard({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/directory', extra: label),
    child: Container(
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
        border: Border.all(color: CharakColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: CharakColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: CharakColors.primaryDeep, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: CharakColors.ink,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    ),
  );
}

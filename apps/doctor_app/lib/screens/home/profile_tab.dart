import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:charak_core/charak_core.dart';
import 'shell_providers.dart';

final _doctorProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
});

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(_doctorProfileProvider);

    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        bottom: false,
        child: profile.when(
          // `.skel` blocks tracing the identity card, the `.verif-card` and the
          // `.listrow` stack, so nothing shifts when the profile lands.
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: [
              // Identity card — 18px padding, 48px avatar, 14px gap.
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: CharakColors.bg,
                  borderRadius: const BorderRadius.all(CharakRadius.card),
                  border: Border.all(color: CharakColors.border),
                ),
                child: const Row(children: [
                  CharakSkeleton(width: 48, height: 48, radius: 24),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CharakSkeleton(width: 150, height: 16),
                      SizedBox(height: 6),
                      CharakSkeleton(width: 190, height: 13),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              const CharakSkeleton(height: 74, radius: 14),
              const SizedBox(height: 14),
              for (var i = 0; i < 6; i++) const _ListRowSkeleton(),
            ],
          ),
          error: (e, _) => Center(
            child: Text('Failed to load profile',
                style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
          ),
          data: (me) {
            final name    = me['name'] as String? ?? '—';
            final status  = me['verification_status'] as String? ?? 'pending';
            final online  = me['offers_online_consult'] as bool? ?? false;
            final home    = me['offers_home_visit'] as bool? ?? false;
            final radius  = me['service_radius_km'];
            final spec    = (me['categories'] as Map<String, dynamic>?)?['name'] as String?;
            final phone   = me['phone'] as String? ?? '';
            final pricing = List<Map<String, dynamic>>.from(me['doctor_pricing'] as List? ?? []);
            final onlineP = pricing.where((p) => p['channel'] == 'online_consult').firstOrNull;
            final onlinePrice = (onlineP?['price'] as num?)?.toStringAsFixed(0);
            final onlineExtra = (onlineP?['extra_rate_per_15min'] as num?)?.toStringAsFixed(0);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                // Identity card — 18px padding, 14px gap, 17px/600 name.
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: CharakColors.bg,
                    borderRadius: const BorderRadius.all(CharakRadius.card),
                    border: Border.all(color: CharakColors.border),
                  ),
                  child: Row(children: [
                    CharakAvatar(name: name, radius: 24, imageUrl: me['photo_url'] as String?),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: CharakText.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        [if (spec != null) spec, if (phone.isNotEmpty) phone].join(' · '),
                        style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ])),
                  ]),
                ),
                const SizedBox(height: 10),
                _VerifCard(status: status),
                const SizedBox(height: 14),

                CharakListRow(
                  icon: Icons.settings_input_antenna_rounded,
                  title: 'Channels & modes',
                  trailingText: [if (online) 'Online', if (home) 'Home Visit'].join(' · '),
                  onTap: () => context.push('/setup/channels'),
                ),
                CharakListRow(
                  icon: Icons.currency_rupee_rounded,
                  title: 'Pricing & procedures',
                  trailingText: onlinePrice != null ? '₹$onlinePrice/15m · +₹$onlineExtra/15m' : null,
                  onTap: () => context.push('/setup/pricing'),
                ),
                CharakListRow(
                  icon: Icons.place_outlined,
                  title: 'Schedule & radius',
                  trailingText: radius != null ? '$radius km' : null,
                  onTap: () => context.push('/setup/home-visit'),
                ),
                CharakListRow(
                  icon: Icons.calendar_month_outlined,
                  title: 'Slot blocking',
                  onTap: () {
                    ref.read(doctorTabIndexProvider.notifier).state = 1;
                    context.go('/home');
                  },
                ),
                CharakListRow(
                  icon: Icons.support_outlined,
                  title: 'Help',
                  onTap: () => showCharakToast(context,
                      message: 'Help centre — coming in full build'),
                ),
                CharakListRow(
                  icon: Icons.logout,
                  title: 'Logout',
                  titleColor: CharakColors.danger,
                  showChevron: false,
                  last: true,
                  onTap: () async {
                    final confirm = await showShadDialog<bool>(
                      context: context,
                      builder: (ctx) => ShadDialog.alert(
                        title: const Text('Log out?'),
                        actions: [
                          ShadButton.outline(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          ShadButton.destructive(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) context.go('/auth/phone');
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Loading placeholder for one `.listrow`: the 20px leading glyph, the title
/// line and a trailing value, on the row's hairline divider.
class _ListRowSkeleton extends StatelessWidget {
  const _ListRowSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: CharakColors.border)),
    ),
    child: const Row(children: [
      CharakSkeleton(width: 20, height: 20, radius: 6),
      SizedBox(width: 13),
      CharakSkeleton(width: 140, height: 14),
      Spacer(),
      CharakSkeleton(width: 64, height: 12),
    ]),
  );
}

/// `.verif-card` — 14px padding, a 42px circular tone badge, 15px/600 title
/// and a 12.5px muted line. Tones come from the spec's translucent pairs.
class _VerifCard extends StatelessWidget {
  final String status;
  const _VerifCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final verified = status == 'verified';
    final (bg, fg) = charakToneColors(
        verified ? CharakStatusTone.success : CharakStatusTone.warning);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
        border: Border.all(color: CharakColors.border),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(verified ? Icons.verified_user_rounded : Icons.shield_outlined,
              size: 20, color: fg),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(verified ? 'Verified doctor' : 'Verification pending',
              style: CharakText.bodyMed.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 1),
          Text(
            verified
                ? 'License checked · listed in directory'
                : "You'll be listed the moment ops approves",
            style: const TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 12.5,
              height: 1.4,
              color: CharakColors.inkMuted,
            ),
          ),
        ])),
      ]),
    );
  }
}

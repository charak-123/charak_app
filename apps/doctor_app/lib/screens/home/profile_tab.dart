import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

    return CharakLargeTitleScaffold(
      title: 'Profile',
      onRefresh: () => ref.refresh(_doctorProfileProvider.future),
      children: profile.when(
        loading: () => const [
          CharakSkeletonCard(footer: false),
          CharakSkeleton(height: 76, radius: CharakRadii.card),
          SizedBox(height: 24),
          CharakSkeletonList(count: 2, avatar: false, padding: EdgeInsets.zero),
        ],
        error: (e, _) => const [
          CharakEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn\'t load your profile',
            message: 'Pull down to try again.',
          ),
        ],
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

          return [
            CharakCard(
              child: Row(children: [
                CharakAvatar(name: name, radius: 30, imageUrl: me['photo_url'] as String?),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Dr. $name', style: CharakText.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
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
            const SizedBox(height: 24),
            CharakGroupedList(
              label: 'Consultation',
              children: [
                CharakListRow(
                  icon: Icons.videocam_outlined,
                  title: 'Channels & modes',
                  subtitle: [if (online) 'Online', if (home) 'Home visit'].join(' · ').ifEmpty('Off'),
                  onTap: () => context.push('/setup/channels'),
                ),
                CharakListRow(
                  icon: Icons.currency_rupee_rounded,
                  title: 'Pricing & procedures',
                  subtitle: onlinePrice != null ? '₹$onlinePrice per 15 min · +₹$onlineExtra per extra 15' : null,
                  onTap: () => context.push('/setup/pricing'),
                ),
                CharakListRow(
                  icon: Icons.place_outlined,
                  title: 'Home visit hours & radius',
                  subtitle: radius != null ? '$radius km' : null,
                  onTap: () => context.push('/setup/home-visit'),
                ),
                CharakListRow(
                  icon: Icons.block_rounded,
                  title: 'Slot blocking',
                  last: true,
                  onTap: () {
                    ref.read(doctorTabIndexProvider.notifier).state = 1;
                    context.go('/home');
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            CharakGroupedList(
              label: 'Support',
              children: [
                CharakListRow(
                  icon: Icons.support_outlined,
                  title: 'Help',
                  onTap: () => showCharakToast(context, message: 'Help centre — coming in full build'),
                ),
                CharakListRow(
                  icon: Icons.logout_rounded,
                  title: 'Log out',
                  titleColor: CharakColors.danger,
                  showChevron: false,
                  last: true,
                  onTap: () async {
                    final confirm = await showCharakConfirm(
                      context,
                      title: 'Log out?',
                      message: 'You will stop receiving requests on this phone until you log in again.',
                      confirmLabel: 'Log out',
                      destructive: true,
                    );
                    if (confirm && context.mounted) {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) context.go('/auth/phone');
                    }
                  },
                ),
              ],
            ),
          ];
        },
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Verification block: a tinted round badge, title and one line. Verified
/// uses the Confirmed (sage) tone, pending uses Requested (chandan).
class _VerifCard extends StatelessWidget {
  final String status;
  const _VerifCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final verified = status == 'verified';
    final (bg, fg) = charakToneColors(
        verified ? CharakStatusTone.confirmed : CharakStatusTone.requested);
    return CharakCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(verified ? Icons.verified_user_rounded : Icons.shield_outlined, size: 22, color: fg),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(verified ? 'Verified doctor' : 'Verification pending',
              style: CharakText.body.weight(650).copyWith(color: CharakColors.ink)),
          Text(
            verified ? 'License checked · listed in directory' : "You'll be listed the moment ops approves",
            style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
          ),
        ])),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

final _doctorProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
});

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(_doctorProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text(e.toString())),
        data: (me) => ListView(
          padding: const EdgeInsets.all(CharakSpacing.base),
          children: [
            // Profile card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(CharakSpacing.base),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: CharakColors.bgSubtle,
                      backgroundImage: me['photo_url'] != null
                          ? NetworkImage(me['photo_url'] as String)
                          : null,
                      child: me['photo_url'] == null
                          ? const Icon(Icons.person, color: CharakColors.inkMuted)
                          : null,
                    ),
                    const SizedBox(width: CharakSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(me['name'] as String? ?? '—', style: CharakText.h2),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _VerificationBadge(status: me['verification_status'] as String),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: CharakSpacing.base),

            // Menu
            _MenuItem(
              icon: Icons.tune,
              label: 'Channels & Schedule',
              onTap: () => context.push('/setup/channels'),
            ),
            _MenuItem(
              icon: Icons.payments_outlined,
              label: 'Pricing & Procedures',
              onTap: () => context.push('/setup/pricing'),
            ),
            _MenuItem(
              icon: Icons.my_location,
              label: 'Service Radius',
              onTap: () => context.push('/setup/home-visit'),
            ),
            const Divider(height: CharakSpacing.xl),
            _MenuItem(
              icon: Icons.help_outline,
              label: 'Help & Support',
              onTap: () {},
            ),
            _MenuItem(
              icon: Icons.logout,
              label: 'Logout',
              danger: true,
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Log out?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Log out', style: TextStyle(color: CharakColors.danger))),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await ref.read(authProvider.notifier).logout();
                  context.go('/auth/phone');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  final String status;
  const _VerificationBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg; Color fg; String label; IconData icon;
    switch (status) {
      case 'verified':
        bg = const Color(0xFFEAF7F1); fg = CharakColors.success; label = 'Verified'; icon = Icons.verified;
        break;
      case 'rejected':
        bg = const Color(0xFFFEECEB); fg = CharakColors.danger; label = 'Rejected'; icon = Icons.cancel;
        break;
      default:
        bg = const Color(0xFFFFF8EB); fg = CharakColors.warning; label = 'Pending review'; icon = Icons.hourglass_top;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CharakSpacing.sm, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.all(CharakRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label, style: CharakText.micro.copyWith(color: fg)),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _MenuItem({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? CharakColors.danger : CharakColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.all(CharakRadius.button),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CharakSpacing.md, horizontal: CharakSpacing.sm),
        child: Row(
          children: [
            Icon(icon, color: danger ? CharakColors.danger : CharakColors.inkMuted, size: 20),
            const SizedBox(width: CharakSpacing.md),
            Expanded(child: Text(label, style: CharakText.body.copyWith(color: color))),
            Icon(Icons.chevron_right, color: CharakColors.border, size: 20),
          ],
        ),
      ),
    );
  }
}

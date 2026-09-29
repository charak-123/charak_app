import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final name = user?['name'] as String? ?? 'Patient';
    final phone = user?['phone'] as String? ?? '';

    return CharakLargeTitleScaffold(
      title: 'Profile',
      children: [
        // Identity block on the warm surface: Chandan welcomes.
        CharakCard(
          tone: CharakCardTone.warm,
          child: Row(children: [
            CharakAvatar(name: name, radius: 30, tone: 1),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: CharakText.titleMedium),
              const SizedBox(height: 2),
              Text(phone, style: CharakText.body.tabular.copyWith(color: CharakColors.inkMuted)),
            ])),
          ]),
        ),
        const SizedBox(height: 24),
        CharakGroupedList(
          label: 'Account',
          children: [
            CharakListRow(
              icon: Icons.person_outline_rounded,
              title: 'Edit profile',
              onTap: () => _comingSoon(context, 'Edit profile'),
            ),
            CharakListRow(
              icon: Icons.credit_card_outlined,
              title: 'Payment methods',
              subtitle: 'UPI · HDFC •• 4821',
              last: true,
              onTap: () => _comingSoon(context, 'Payment methods'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        CharakGroupedList(
          label: 'Support',
          children: [
            CharakListRow(
              icon: Icons.report_gmailerrorred_outlined,
              title: 'Submit a complaint',
              onTap: () => context.push('/complaint'),
            ),
            CharakListRow(
              icon: Icons.support_outlined,
              title: 'Help',
              last: true,
              onTap: () => _comingSoon(context, 'Help centre'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        CharakGroupedList(
          children: [
            CharakListRow(
              icon: Icons.logout_rounded,
              title: 'Log out',
              titleColor: CharakColors.danger,
              showChevron: false,
              last: true,
              onTap: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/auth/phone');
              },
            ),
          ],
        ),
      ],
    );
  }

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — coming in full build')),
    );
  }
}

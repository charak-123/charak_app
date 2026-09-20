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

    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            // Identity card — 18px padding, 14px gap, 48px avatar.
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: CharakColors.bg,
                border: Border.all(color: CharakColors.border),
                borderRadius: const BorderRadius.all(CharakRadius.card),
              ),
              child: Row(children: [
                CharakAvatar(name: name, radius: 24, tone: 1),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: CharakText.h2),
                  const SizedBox(height: 2),
                  Text(phone,
                      style: CharakText.caption.copyWith(
                        color: CharakColors.inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ])),
              ]),
            ),
            const SizedBox(height: 18),

            // `.listrow` stack — flat rows with hairline separators.
            CharakListRow(
              icon: Icons.person_outline,
              title: 'Edit Profile',
              onTap: () => _comingSoon(context, 'Edit profile'),
            ),
            CharakListRow(
              icon: Icons.credit_card_outlined,
              title: 'Payment Methods',
              trailingText: 'UPI · HDFC •• 4821',
              onTap: () => _comingSoon(context, 'Payment methods'),
            ),
            CharakListRow(
              icon: Icons.report_gmailerrorred_outlined,
              title: 'Submit a Complaint',
              onTap: () => context.push('/complaint'),
            ),
            CharakListRow(
              icon: Icons.support_outlined,
              title: 'Help',
              onTap: () => _comingSoon(context, 'Help centre'),
            ),
            CharakListRow(
              icon: Icons.logout,
              title: 'Logout',
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
      ),
    );
  }

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — coming in full build')),
    );
  }
}

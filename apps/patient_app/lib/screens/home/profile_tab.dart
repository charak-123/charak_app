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
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(CharakSpacing.base),
        children: [
          // Profile card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: CharakColors.bg,
              borderRadius: const BorderRadius.all(CharakRadius.card),
              border: Border.all(color: CharakColors.border),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: CharakColors.primarySoft,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'P',
                  style: CharakText.display.copyWith(color: CharakColors.primary),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: CharakText.h1),
                const SizedBox(height: 4),
                Text(phone, style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),

          // Menu items
          _MenuItem(
            icon: Icons.history_outlined,
            label: 'Booking History',
            onTap: () => context.go('/home', extra: 1),
          ),
          _MenuItem(
            icon: Icons.help_outline,
            label: 'Help & Support',
            onTap: () {},
          ),
          _MenuItem(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            onTap: () {},
          ),
          _MenuItem(
            icon: Icons.description_outlined,
            label: 'Terms of Service',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          _MenuItem(
            icon: Icons.logout,
            label: 'Logout',
            color: CharakColors.danger,
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/auth/phone');
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Charak v1.0.0',
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MenuItem({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      borderRadius: const BorderRadius.all(CharakRadius.card),
      border: Border.all(color: CharakColors.border),
    ),
    child: ListTile(
      leading: Icon(icon, color: color ?? CharakColors.ink),
      title: Text(label,
          style: CharakText.body.copyWith(color: color ?? CharakColors.ink)),
      trailing: Icon(Icons.chevron_right, color: CharakColors.inkMuted),
      onTap: onTap,
    ),
  );
}

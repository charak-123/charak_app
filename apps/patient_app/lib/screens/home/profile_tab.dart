import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              Text(CharakFormat.phone(phone), style: CharakText.body.tabular.copyWith(color: CharakColors.inkMuted)),
            ])),
          ]),
        ),
        const SizedBox(height: 24),
        CharakGroupedList(
          label: 'Account',
          children: [
            CharakListRow(
              icon: LucideIcons.user,
              title: 'Edit profile',
              onTap: () => _editProfile(context, ref, name, phone),
            ),
            CharakListRow(
              icon: LucideIcons.receiptText,
              title: 'Payments & refunds',
              onTap: () => context.push('/payments'),
            ),
            CharakListRow(
              icon: LucideIcons.octagonAlert,
              title: 'Submit a complaint',
              onTap: () => context.push('/complaint'),
            ),
            CharakListRow(
              icon: LucideIcons.lifeBuoy,
              title: 'Help',
              last: true,
              onTap: () => CharakLegal.open(CharakLegal.supportUrl),
            ),
          ],
        ),
        const SizedBox(height: 24),
        CharakGroupedList(
          label: 'Legal',
          children: [
            CharakListRow(
              icon: LucideIcons.fileText,
              title: 'Terms and policies',
              subtitle: 'Read them in full, and see what you signed',
              last: true,
              onTap: () => CharakLegalCenterScreen.open(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        CharakGroupedList(
          children: [
            CharakListRow(
              icon: LucideIcons.logOut,
              title: 'Log out',
              titleColor: CharakColors.danger,
              showChevron: false,
              onTap: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/auth/sign-in');
              },
            ),
            CharakListRow(
              icon: LucideIcons.trash2,
              title: 'Delete account',
              titleColor: CharakColors.danger,
              showChevron: false,
              last: true,
              onTap: () => _deleteAccount(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCharakConfirm(
      context,
      title: 'Delete your account?',
      message:
          'Your personal details, saved addresses and symptom media will be '
          'removed. Your past bookings and payment records are kept, '
          'de-identified, as the law requires. You have 30 days to change your '
          'mind — just sign in again to cancel.',
      confirmLabel: 'Delete account',
      cancelLabel: 'Keep account',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(authProvider.notifier).deleteAccount();
      if (context.mounted) context.go('/auth/sign-in');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete your account: $e')),
        );
      }
    }
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref, String name, String phone) =>
      showCharakSheet<void>(
        context,
        title: 'Edit profile',
        child: _EditProfileForm(name: name, phone: phone),
      );
}

class _EditProfileForm extends ConsumerStatefulWidget {
  final String name;
  final String phone;
  const _EditProfileForm({required this.name, required this.phone});
  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  late final _name = TextEditingController(text: widget.name);
  late final _phone = TextEditingController(text: widget.phone.replaceFirst('+91', ''));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().length >= 2 && _phone.text.length == 10;

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).updateProfile(
            name: _name.text.trim(),
            phone: '+91${_phone.text}',
          );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        CharakField(
          label: 'Full name',
          controller: _name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        CharakField(
          label: 'Mobile number',
          controller: _phone,
          keyboardType: TextInputType.phone,
          tabular: true,
          error: _error,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          prefixBox: CharakField.staticBox('+91'),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 20),
        CharakButton(label: 'Save', isLoading: _saving, onPressed: _valid && !_saving ? _save : null),
      ]);
}

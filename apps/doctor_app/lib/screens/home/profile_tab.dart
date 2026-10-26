import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:image_picker/image_picker.dart';
import 'shell_providers.dart';

final _doctorProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
});

/// The payout destination, or null when none is saved yet (404).
final _payoutAccountProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    return await ApiClient.instance.get('/payouts/me/bank-account') as Map<String, dynamic>;
  } on ApiException catch (e) {
    if (e.statusCode == 404) return null;
    rethrow;
  }
});

/// The doctor's price list (GET /doctors/me/prices).
final _pricesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ApiClient.instance.get('/doctors/me/prices') as Map<String, dynamic>;
});

/// "₹600 / 15 min · ₹1,000 / 30 min · follow-up from ₹300" for one channel.
String? _rateLine(List rules, String channel) {
  final mine = rules.whereType<Map>().where((r) => r['channel'] == channel).toList()
    ..sort((a, b) => (a['duration_min'] as num).compareTo(b['duration_min'] as num));
  String rupees(Map r) => CharakFormat.rupees((r['price_paise'] as num) / 100);
  final first = mine.where((r) => r['visit_category'] == 'initial').toList();
  if (first.isEmpty) return null;
  final follow = mine.where((r) => r['visit_category'] == 'follow_up').toList();
  final cheapestFollow = follow.isEmpty
      ? null
      : follow.reduce((a, b) => (a['price_paise'] as num) <= (b['price_paise'] as num) ? a : b);
  return [
    for (final r in first) '${rupees(r)} / ${r['duration_min']} min',
    if (cheapestFollow != null)
      (cheapestFollow['price_paise'] as num) == 0 ? 'free follow-up' : 'follow-up from ${rupees(cheapestFollow)}',
  ].join(' · ');
}

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(_doctorProfileProvider);
    final payout = ref.watch(_payoutAccountProvider);

    return CharakLargeTitleScaffold(
      title: 'Profile',
      onRefresh: () async {
        ref.invalidate(_payoutAccountProvider);
        ref.invalidate(_doctorProfileProvider);
        await ref.read(_doctorProfileProvider.future);
      },
      children: profile.when(
        loading: () => const [
          CharakSkeletonCard(footer: false),
          CharakSkeleton(height: 76, radius: CharakRadii.card),
          SizedBox(height: 24),
          CharakSkeletonList(count: 2, avatar: false, padding: EdgeInsets.zero),
        ],
        error: (e, _) => const [
          CharakEmptyState(
            icon: LucideIcons.cloudOff,
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
          final rules = (ref.watch(_pricesProvider).valueOrNull?['rules'] as List?) ?? const [];
          final onlineLine = _rateLine(rules, 'online_consult');
          final homeLine   = _rateLine(rules, 'home_visit');
          final acct       = payout.valueOrNull;
          final payoutLine = acct == null
              ? (payout.isLoading ? null : 'Add UPI or bank to get paid')
              : [
                  if (acct['upi_id'] != null) acct['upi_id'] as String,
                  if (acct['account_number'] != null) 'A/c ${acct['account_number']}',
                ].join(' · ');

          return [
            CharakCard(
              child: Row(children: [
                CharakAvatar(name: name, radius: 30, imageUrl: me['photo_url'] as String?),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(CharakFormat.doctor(name), style: CharakText.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [if (spec != null) spec, if (phone.isNotEmpty) CharakFormat.phone(phone)].join(' · '),
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
                  icon: LucideIcons.video,
                  title: 'Channels & modes',
                  subtitle: [if (online) 'Online', if (home) 'Home visit'].join(' · ').ifEmpty('Off'),
                  onTap: () => context.push('/setup/channels'),
                ),
                CharakListRow(
                  icon: LucideIcons.indianRupee,
                  title: 'Pricing & procedures',
                  subtitle: [
                    if (online && onlineLine != null) 'Online $onlineLine',
                    if (home && homeLine != null) 'Home $homeLine',
                  ].join('\n').ifEmpty('Not set'),
                  onTap: () async {
                    await context.push('/setup/pricing');
                    ref.invalidate(_doctorProfileProvider);
                    ref.invalidate(_pricesProvider);
                  },
                ),
                CharakListRow(
                  icon: LucideIcons.mapPin,
                  title: 'Home visit hours & radius',
                  subtitle: radius != null ? '$radius km' : null,
                  onTap: () => context.push('/setup/home-visit'),
                ),
                CharakListRow(
                  icon: LucideIcons.signature,
                  title: 'Prescription signature',
                  subtitle: (me['signature_path'] as String?)?.isNotEmpty == true
                      ? 'Added · printed on your prescriptions'
                      : 'Not added',
                  onTap: () async {
                    if (await uploadSignature(context) && context.mounted) {
                      ref.invalidate(_doctorProfileProvider);
                    }
                  },
                ),
                CharakListRow(
                  icon: LucideIcons.ban,
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
              label: 'Patients',
              children: [
                CharakListRow(
                  icon: LucideIcons.star,
                  title: 'Ratings & reviews',
                  subtitle: (me['rating_count'] as num? ?? 0) >= 5
                      ? '${(me['rating_avg'] as num).toStringAsFixed(1)} · ${me['rating_count']} reviews'
                      : 'New · ${me['rating_count'] ?? 0} reviews',
                  last: true,
                  onTap: () => context.push('/reviews'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            CharakGroupedList(
              label: 'Payouts',
              children: [
                CharakListRow(
                  icon: LucideIcons.landmark,
                  title: 'Payout details',
                  subtitle: payoutLine,
                  last: true,
                  onTap: () async {
                    await context.push('/setup/payout');
                    ref.invalidate(_payoutAccountProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            CharakGroupedList(
              label: 'Support',
              children: [
                CharakListRow(
                  icon: LucideIcons.lifeBuoy,
                  title: 'Help',
                  onTap: () => CharakLegal.open(CharakLegal.supportUrl),
                ),
                CharakListRow(
                  icon: LucideIcons.shieldAlert,
                  title: 'Privacy policy',
                  onTap: () => CharakLegal.open(CharakLegal.privacyUrl),
                ),
                CharakListRow(
                  icon: LucideIcons.fileText,
                  title: 'Terms of service',
                  onTap: () => CharakLegal.open(CharakLegal.termsUrl),
                ),
                CharakListRow(
                  icon: LucideIcons.logOut,
                  title: 'Log out',
                  titleColor: CharakColors.danger,
                  showChevron: false,
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
                      if (context.mounted) context.go('/auth/sign-in');
                    }
                  },
                ),
                CharakListRow(
                  icon: LucideIcons.trash2,
                  title: 'Delete account',
                  titleColor: CharakColors.danger,
                  showChevron: false,
                  last: true,
                  onTap: () async {
                    final confirm = await showCharakConfirm(
                      context,
                      title: 'Request account deletion?',
                      message:
                          'Your account will be locked and our team will close it '
                          'once any pending payouts and upcoming bookings are '
                          'settled. Your personal details are then removed; '
                          'earnings and booking records are kept, de-identified, '
                          'as the law requires.',
                      confirmLabel: 'Request deletion',
                      cancelLabel: 'Keep account',
                      destructive: true,
                    );
                    if (!confirm || !context.mounted) return;
                    try {
                      await ref.read(authProvider.notifier).requestDoctorDeletion();
                      if (context.mounted) context.go('/auth/sign-in');
                    } catch (e) {
                      if (context.mounted) {
                        showCharakToast(context, message: 'Could not submit your request: $e');
                      }
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
          child: Icon(verified ? LucideIcons.shieldCheck : LucideIcons.shield, size: 22, color: fg),
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


/// The signature printed on this doctor's prescription PDFs: a photo of it
/// signed on white paper. Stored privately; prescriptions already sent keep
/// the signature they were made with. Returns whether one was saved.
Future<bool> uploadSignature(BuildContext context) async {
  final ok = await showCharakConfirm(
    context,
    title: 'Add your signature',
    message: 'Sign on plain white paper and take a clear, close photo. '
        'It is printed on the prescriptions you send from now on.',
    confirmLabel: 'Take photo',
  );
  if (!ok) return false;
  final photo = await ImagePicker().pickImage(
      source: ImageSource.camera, imageQuality: 90, maxWidth: 1200);
  if (photo == null) return false;
  try {
    final ext = photo.path.split('.').last.toLowerCase();
    await ApiClient.instance.postFile(
      '/uploads/doctor/signature',
      bytes: await photo.readAsBytes(),
      filename: photo.name,
      contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
    );
    if (context.mounted) showCharakToast(context, message: 'Signature saved');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showCharakToast(context, message: e.message, isError: true);
    return false;
  }
}

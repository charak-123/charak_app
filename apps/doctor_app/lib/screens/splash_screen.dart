import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      context.go('/auth/phone');
      return;
    }

    // Fetch doctor profile to determine where in onboarding we are
    try {
      final me = await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
      if (!mounted) return;

      final status = me['verification_status'] as String?;
      final hasProfile = (me['name'] as String?)?.isNotEmpty == true;
      final hasSubmittedVerification = (me['license_number'] as String?)?.isNotEmpty == true;
      final offersOnline = me['offers_online_consult'] as bool? ?? false;
      final offersHome   = me['offers_home_visit']    as bool? ?? false;

      if (!hasProfile) {
        context.go('/onboarding/profile');
      } else if (!hasSubmittedVerification) {
        context.go('/onboarding/verification');
      } else if (status == null || status == 'pending') {
        context.go('/onboarding/verification-pending');
      } else if (status == 'rejected') {
        context.go('/onboarding/verification');
      } else if (!offersOnline && !offersHome) {
        context.go('/setup/channels');
      } else {
        context.go('/home');
      }
    } catch (_) {
      // New doctor — no profile yet
      context.go('/onboarding/profile');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.bg,
    body: Center(
      child: Padding(
        // `.body.center-col` with `padding-bottom:80px` — the mark sits
        // slightly above the optical centre.
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: CharakColors.ink,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.add, size: 30, color: Colors.white),
            ),
            const SizedBox(height: 18),
            // `.brand-mark` — 26px/700, -0.02em, with the trailing "k" in
            // primary, then the 14px/500 muted "Partner" suffix.
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: CharakText.fontFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.52,
                  height: 1.2,
                  color: CharakColors.ink,
                ),
                children: [
                  const TextSpan(text: 'Chara'),
                  const TextSpan(text: 'k', style: TextStyle(color: CharakColors.primary)),
                  TextSpan(
                    text: '  Partner',
                    style: CharakText.bodyMed.copyWith(
                      fontSize: 14,
                      color: CharakColors.inkMuted,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your practice, your schedule, your price',
              style: TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 13.5,
                height: 1.4,
                color: CharakColors.inkMuted,
              ),
            ),
            const SizedBox(height: 36),
            const SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CharakSkeleton(height: 12),
                  SizedBox(height: 8),
                  CharakSkeleton(width: 160, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

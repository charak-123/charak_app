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
    // The version check runs alongside the splash delay, so it costs nothing
    // on a normal launch. It never blocks on its own failure (CharakAppGate).
    final gate = CharakAppGate.check('doctor');
    await Future.delayed(const Duration(milliseconds: 800));
    final update = await gate;
    if (!mounted) return;
    if (update != null) {
      context.go('/update', extra: update);
      return;
    }

    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      context.go('/auth/sign-in');
      return;
    }

    // Fetch doctor profile to determine where in onboarding we are
    try {
      final me = await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
      if (!mounted) return;

      final status = me['verification_status'] as String?;
      final hasProfile = (me['name'] as String?)?.isNotEmpty == true;
      // Both halves are required — a licence number with no document is not
      // something ops can verify, so a doctor who submitted one before the
      // document became mandatory is sent back to finish the pair.
      final hasSubmittedVerification =
          (me['license_number'] as String?)?.isNotEmpty == true &&
          (me['verification_document_path'] as String?)?.isNotEmpty == true;
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
        // Just approved and hasn't set up channels/pricing yet — whether
        // that's because they're opening the app for the first time since
        // (a push, or just curiosity) or the live poll on the pending screen
        // caught it, this is the one moment ops approval should be visible
        // as a moment, not a silent redirect into a setup form.
        context.go('/onboarding/verified');
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
    backgroundColor: CharakColors.ground,
    body: SafeArea(
      child: Padding(
        // The mark sits slightly above the optical centre.
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CharakLogoMark(height: 140),
              const SizedBox(height: 24),
              const CharakWordmark(size: 30, suffix: 'Partner'),
              const SizedBox(height: 10),
              Text(
                'Your practice, your schedule, your price',
                textAlign: TextAlign.center,
                style: CharakText.body.copyWith(color: CharakColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/onboarding/profile_setup_screen.dart';
import 'screens/onboarding/verification_screen.dart';
import 'screens/onboarding/verification_pending_screen.dart';
import 'screens/setup/channel_setup_screen.dart';
import 'screens/setup/online_consult_setup_screen.dart';
import 'screens/setup/home_visit_setup_screen.dart';
import 'screens/setup/pricing_setup_screen.dart';
import 'screens/home/home_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // Let splash handle routing; only hard-redirect to auth if accessing home without token
      final isAuth = state.matchedLocation.startsWith('/auth');
      final isSplash = state.matchedLocation == '/';
      if (!auth.isAuthenticated && !isAuth && !isSplash) return '/auth/phone';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/auth/phone', builder: (_, __) => const PhoneEntryScreen()),
      GoRoute(
        path: '/auth/otp',
        builder: (_, state) => OtpScreen(phone: state.extra as String),
      ),
      GoRoute(path: '/onboarding/profile', builder: (_, __) => const ProfileSetupScreen()),
      GoRoute(path: '/onboarding/verification', builder: (_, __) => const VerificationScreen()),
      GoRoute(path: '/onboarding/verification-pending', builder: (_, __) => const VerificationPendingScreen()),
      GoRoute(path: '/setup/channels', builder: (_, __) => const ChannelSetupScreen()),
      GoRoute(path: '/setup/online', builder: (_, __) => const OnlineConsultSetupScreen()),
      GoRoute(
        path: '/setup/home-visit',
        builder: (_, state) => HomeVisitSetupScreen(fromSetup: state.extra as bool? ?? false),
      ),
      GoRoute(path: '/setup/pricing', builder: (_, __) => const PricingSetupScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
    ],
  );
});

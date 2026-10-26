import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/onboarding/profile_setup_screen.dart';
import 'screens/onboarding/verification_screen.dart';
import 'screens/onboarding/verification_pending_screen.dart';
import 'screens/onboarding/verified_welcome_screen.dart';
import 'screens/setup/channel_setup_screen.dart';
import 'screens/setup/online_consult_setup_screen.dart';
import 'screens/setup/home_visit_setup_screen.dart';
import 'screens/setup/payout_details_screen.dart';
import 'screens/setup/pricing_setup_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/home/shell_providers.dart';
import 'push_routes.dart';
import 'screens/requests/request_detail_screen.dart';
import 'screens/requests/clarification_call_screen.dart';
import 'screens/requests/active_visit_screen.dart';
import 'screens/requests/prescription_screen.dart';

/// Wraps a screen in the wireframe's 280ms horizontal push
/// (`.scr.entering` / `.scr.leaving`).
CustomTransitionPage<void> _push(Widget child) => CustomTransitionPage<void>(
  child: CharakEntranceScope(child: child),
  transitionDuration: CharakDurations.screenPush,
  reverseTransitionDuration: CharakDurations.screenPush,
  transitionsBuilder: charakPushTransition,
);

/// Rise-and-fade, for surfaces that shouldn't slide in from the side:
/// the splash, the shell, and the full-screen call.
CustomTransitionPage<void> _rise(Widget child) => CustomTransitionPage<void>(
  child: CharakEntranceScope(child: child),
  transitionDuration: CharakDurations.sheetOpen,
  reverseTransitionDuration: CharakDurations.sheetOpen,
  transitionsBuilder: charakRiseTransition,
);

/// "Card → screen": the screen grows out of the card that was tapped
/// (emphasized, 450ms). The origin is taken once per page and kept by its key,
/// so a rebuild of the page — and the pop back into the card — reuse it.
final _cardOrigins = <ValueKey<String>, Rect?>{};
CustomTransitionPage<void> _card(GoRouterState state, Widget child) {
  final key = state.pageKey;
  final origin = _cardOrigins.containsKey(key)
      ? _cardOrigins[key]
      : (_cardOrigins[key] = CharakCardOrigin.take());
  return CustomTransitionPage<void>(
    key: key,
    child: CharakEntranceScope(child: child),
    transitionDuration: CharakMotion.emphasized,
    reverseTransitionDuration: CharakMotion.emphasized,
    transitionsBuilder: charakCardTransition(origin),
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  late final GoRouter router;

  // A rejected token (expired, or signed with a rotated JWT_SECRET) must send
  // the user back to login rather than stranding them on an error.
  ApiClient.onUnauthorized = () {
    ref.read(authProvider.notifier).logout();
    router.go('/auth/sign-in');
  };

  // Deliberately `ref.read`, not `ref.watch`: this provider must build the
  // GoRouter exactly once. Watching authProvider here would rebuild — and
  // hand ShadApp.router a brand-new GoRouter instance — on every auth change,
  // which resets navigation back to initialLocation mid-flow (e.g. right
  // after OTP verify, wiping out the in-flight `context.go('/onboarding/...')`
  // before it lands). `redirect` below reads fresh auth state per navigation
  // instead, which is all GoRouter needs.
  router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final auth     = ref.read(authProvider);
      final isAuth   = state.matchedLocation.startsWith('/auth');
      final isSplash = state.matchedLocation == '/';
      // Reachable signed out: an old build must update before it can sign in.
      final isUpdate = state.matchedLocation == '/update';
      if (!auth.isAuthenticated && !isAuth && !isSplash && !isUpdate) return '/auth/sign-in';
      return null;
    },
    routes: [
      GoRoute(path: '/',                      pageBuilder: (_, __) => _rise(const SplashScreen())),
      GoRoute(path: '/update',
          redirect: (_, s) => s.extra is CharakUpdateInfo ? null : '/',
          pageBuilder: (_, s) => _rise(CharakUpdateRequiredScreen(info: s.extra! as CharakUpdateInfo))),
      GoRoute(path: '/auth/sign-in',          pageBuilder: (_, __) => _push(const SignInScreen())),
      // Phone + OTP: back once DLT approval lets MSG91 deliver SMS.
      GoRoute(path: '/auth/phone',            pageBuilder: (_, __) => _push(const PhoneEntryScreen())),
      GoRoute(path: '/auth/otp',
          pageBuilder: (_, state) => _push(OtpScreen(phone: state.extra as String))),
      GoRoute(path: '/onboarding/profile',    pageBuilder: (_, __) => _push(const ProfileSetupScreen())),
      GoRoute(path: '/onboarding/verification', pageBuilder: (_, __) => _push(const VerificationScreen())),
      GoRoute(path: '/onboarding/verification-pending', pageBuilder: (_, __) => _rise(const VerificationPendingScreen())),
      GoRoute(path: '/onboarding/verified',   pageBuilder: (_, __) => _rise(const VerifiedWelcomeScreen())),
      GoRoute(path: '/setup/channels',        pageBuilder: (_, __) => _push(const ChannelSetupScreen())),
      GoRoute(path: '/setup/online',          pageBuilder: (_, __) => _push(const OnlineConsultSetupScreen())),
      GoRoute(path: '/setup/home-visit',
          pageBuilder: (_, state) => _push(HomeVisitSetupScreen(fromSetup: state.extra as bool? ?? false))),
      GoRoute(path: '/setup/pricing',         pageBuilder: (_, __) => _push(const PricingSetupScreen())),
      GoRoute(path: '/setup/payout',          pageBuilder: (_, __) => _push(const PayoutDetailsScreen())),
      GoRoute(path: '/home',                  pageBuilder: (_, __) => _rise(const HomeShell())),

      // ── Phase 2: Requests & Fulfillment ───────────────────────────────────
      GoRoute(
        path: '/request/:id',
        pageBuilder: (_, state) => _card(state, RequestDetailScreen(bookingId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/call/:bookingId',
        pageBuilder: (_, state) => _rise(ClarificationCallScreen(bookingId: state.pathParameters['bookingId']!)),
      ),
      GoRoute(
        path: '/consult/:bookingId',
        pageBuilder: (_, state) => _rise(ClarificationCallScreen(
            bookingId: state.pathParameters['bookingId']!, consultation: true)),
      ),
      GoRoute(
        path: '/visit/:bookingId',
        pageBuilder: (_, state) => _card(state, ActiveVisitScreen(bookingId: state.pathParameters['bookingId']!)),
      ),
      GoRoute(
        path: '/visit/:bookingId/prescription',
        pageBuilder: (_, state) => _push(PrescriptionScreen(bookingId: state.pathParameters['bookingId']!)),
      ),
    ],
  );

  // A tapped notification should land on the thing it is about, not the last
  // screen the doctor happened to be on. The mapping itself lives in
  // `push_routes.dart` so it can be tested without a GoRouter.
  final pushSub = CharakPush.instance.messages.listen((m) {
    final destination = doctorPushDestination(m);
    if (destination == null) return;
    final tab = destination.tabIndex;
    if (tab != null) ref.read(doctorTabIndexProvider.notifier).state = tab;
    router.go(destination.route);
  });
  ref.onDispose(pushSub.cancel);

  return router;
});

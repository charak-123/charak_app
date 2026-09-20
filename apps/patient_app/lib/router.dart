import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/name_entry_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/directory/directory_screen.dart';
import 'screens/directory/doctor_profile_screen.dart';
import 'screens/booking/slot_selection_screen.dart';
import 'screens/booking/channel_confirm_screen.dart';
import 'screens/booking/intake_screen.dart';
import 'screens/booking/review_confirm_screen.dart';
import 'screens/booking/request_sent_screen.dart';
import 'screens/booking/booking_status_screen.dart';
import 'screens/booking/payment_screen.dart';
import 'screens/booking/booking_confirmed_screen.dart';
import 'screens/booking/active_booking_screen.dart';
import 'screens/booking/video_call_screen.dart';
import 'screens/booking/visit_complete_screen.dart';
import 'screens/booking/procedure_bill_screen.dart';
import 'screens/booking/rate_screen.dart';
import 'screens/booking/history_detail_screen.dart';
import 'screens/booking/complaint_screen.dart';

/// Wraps a screen in the wireframe's 280ms horizontal push
/// (`.scr.entering` / `.scr.leaving`).
CustomTransitionPage<void> _push(Widget child) => CustomTransitionPage<void>(
  child: child,
  transitionDuration: CharakDurations.screenPush,
  reverseTransitionDuration: CharakDurations.screenPush,
  transitionsBuilder: charakPushTransition,
);

/// Rise-and-fade, for surfaces that shouldn't slide in from the side:
/// the splash, the full-screen call, and terminal outcome screens.
CustomTransitionPage<void> _rise(Widget child) => CustomTransitionPage<void>(
  child: child,
  transitionDuration: CharakDurations.sheetOpen,
  reverseTransitionDuration: CharakDurations.sheetOpen,
  transitionsBuilder: charakRiseTransition,
);

final routerProvider = Provider<GoRouter>((ref) {
  late final GoRouter router;

  // A rejected token (expired, or signed with a rotated JWT_SECRET) must send
  // the user back to login rather than stranding them on an error.
  ApiClient.onUnauthorized = () {
    ref.read(authProvider.notifier).logout();
    router.go('/auth/phone');
  };

  // `ref.read`, not `ref.watch` — see apps/doctor_app/lib/router.dart for why:
  // watching authProvider here would recreate the GoRouter (and reset
  // navigation to initialLocation) on every auth change, including the one
  // that fires mid-flow right after OTP verify.
  router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final auth     = ref.read(authProvider);
      final isAuth   = state.matchedLocation.startsWith('/auth');
      final isSplash = state.matchedLocation == '/';
      if (!auth.isAuthenticated && !isAuth && !isSplash) return '/auth/phone';
      return null;
    },
    routes: [
      GoRoute(path: '/',                     pageBuilder: (_, __) => _rise(const SplashScreen())),
      GoRoute(path: '/auth/phone',           pageBuilder: (_, __) => _push(const PhoneEntryScreen())),
      GoRoute(path: '/auth/otp',
          pageBuilder: (_, s) => _push(OtpScreen(phone: s.extra as String))),
      GoRoute(path: '/auth/name',            pageBuilder: (_, __) => _push(const NameEntryScreen())),

      // ── Main shell ───────────────────────────────────────────────────────
      GoRoute(path: '/home',                 pageBuilder: (_, __) => _rise(const HomeShell())),

      // ── Directory ────────────────────────────────────────────────────────
      GoRoute(path: '/directory',
          pageBuilder: (_, s) => _push(DirectoryScreen(initialQuery: s.extra as String?))),
      GoRoute(path: '/doctor/:id',
          pageBuilder: (_, s) => _push(DoctorProfileScreen(doctorId: s.pathParameters['id']!))),

      // ── Booking flow ─────────────────────────────────────────────────────
      GoRoute(path: '/book/:doctorId/slots',
          pageBuilder: (_, s) => _push(SlotSelectionScreen(doctorId: s.pathParameters['doctorId']!))),
      GoRoute(path: '/book/:doctorId/channel',
          pageBuilder: (_, s) => _push(ChannelConfirmScreen(
            doctorId: s.pathParameters['doctorId']!,
            extra: s.extra as Map<String, dynamic>,
          ))),
      GoRoute(path: '/book/:doctorId/intake',
          pageBuilder: (_, s) => _push(IntakeScreen(
            doctorId: s.pathParameters['doctorId']!,
            extra: s.extra as Map<String, dynamic>,
          ))),
      GoRoute(path: '/book/review',
          pageBuilder: (_, s) => _push(ReviewConfirmScreen(booking: s.extra as Map<String, dynamic>))),

      // Outcome screens rise rather than slide — they end a flow.
      GoRoute(path: '/book/sent/:bookingId',
          pageBuilder: (_, s) => _rise(RequestSentScreen(bookingId: s.pathParameters['bookingId']!))),
      GoRoute(path: '/booking/:id/status',
          pageBuilder: (_, s) => _push(BookingStatusScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/pay',
          pageBuilder: (_, s) => _push(PaymentScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/confirmed',
          pageBuilder: (_, s) => _rise(BookingConfirmedScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/active',
          pageBuilder: (_, s) => _push(ActiveBookingScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/call',
          pageBuilder: (_, s) => _rise(VideoCallScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/complete',
          pageBuilder: (_, s) => _rise(VisitCompleteScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/bill',
          pageBuilder: (_, s) => _push(ProcedureBillScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/rate',
          pageBuilder: (_, s) => _push(RateScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/history-detail',
          pageBuilder: (_, s) => _push(HistoryDetailScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/complaint',
          pageBuilder: (_, s) => _push(ComplaintScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/complaint',
          pageBuilder: (_, __) => _push(const ComplaintScreen())),
    ],
  );
  return router;
});

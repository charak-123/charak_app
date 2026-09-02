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

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isAuth   = state.matchedLocation.startsWith('/auth');
      final isSplash = state.matchedLocation == '/';
      if (!auth.isAuthenticated && !isAuth && !isSplash) return '/auth/phone';
      return null;
    },
    routes: [
      GoRoute(path: '/',                     builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/auth/phone',           builder: (_, __) => const PhoneEntryScreen()),
      GoRoute(path: '/auth/otp',
          builder: (_, s) => OtpScreen(phone: s.extra as String)),
      GoRoute(path: '/auth/name',            builder: (_, __) => const NameEntryScreen()),

      // ── Main shell ───────────────────────────────────────────────────────
      GoRoute(path: '/home',                 builder: (_, __) => const HomeShell()),

      // ── Directory ────────────────────────────────────────────────────────
      GoRoute(path: '/directory',            builder: (_, __) => const DirectoryScreen()),
      GoRoute(path: '/directory/search',
          builder: (_, s) => DirectoryScreen(initialQuery: s.extra as String?)),
      GoRoute(path: '/doctor/:id',
          builder: (_, s) => DoctorProfileScreen(doctorId: s.pathParameters['id']!)),

      // ── Booking flow ─────────────────────────────────────────────────────
      GoRoute(path: '/book/:doctorId/slots',
          builder: (_, s) => SlotSelectionScreen(doctorId: s.pathParameters['doctorId']!)),
      GoRoute(path: '/book/:doctorId/channel',
          builder: (_, s) => ChannelConfirmScreen(
            doctorId: s.pathParameters['doctorId']!,
            extra: s.extra as Map<String, dynamic>,
          )),
      GoRoute(path: '/book/:doctorId/intake',
          builder: (_, s) => IntakeScreen(
            doctorId: s.pathParameters['doctorId']!,
            extra: s.extra as Map<String, dynamic>,
          )),
      GoRoute(path: '/book/review',
          builder: (_, s) => ReviewConfirmScreen(booking: s.extra as Map<String, dynamic>)),
      GoRoute(path: '/book/sent/:bookingId',
          builder: (_, s) => RequestSentScreen(bookingId: s.pathParameters['bookingId']!)),
      GoRoute(path: '/booking/:id/status',
          builder: (_, s) => BookingStatusScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(path: '/booking/:id/pay',
          builder: (_, s) => PaymentScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(path: '/booking/:id/confirmed',
          builder: (_, s) => BookingConfirmedScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(path: '/booking/:id/active',
          builder: (_, s) => ActiveBookingScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(path: '/booking/:id/call',
          builder: (_, s) => VideoCallScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(path: '/booking/:id/complete',
          builder: (_, s) => VisitCompleteScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(path: '/booking/:id/bill',
          builder: (_, s) => ProcedureBillScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(path: '/booking/:id/rate',
          builder: (_, s) => RateScreen(bookingId: s.pathParameters['id']!)),
    ],
  );
});

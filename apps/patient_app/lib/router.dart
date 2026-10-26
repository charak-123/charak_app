import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'screens/splash_screen.dart';
import 'push_routes.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/notifications/notifications_screen.dart';
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
  child: CharakEntranceScope(child: child),
  transitionDuration: CharakDurations.screenPush,
  reverseTransitionDuration: CharakDurations.screenPush,
  transitionsBuilder: charakPushTransition,
);

/// Rise-and-fade, for surfaces that shouldn't slide in from the side:
/// the splash, the full-screen call, and terminal outcome screens.
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
      // Reachable signed out: an old build must update before it can sign in.
      final isUpdate = state.matchedLocation == '/update';
      if (!auth.isAuthenticated && !isAuth && !isSplash && !isUpdate) return '/auth/sign-in';
      return null;
    },
    routes: [
      GoRoute(path: '/',                     pageBuilder: (_, __) => _rise(const SplashScreen())),
      GoRoute(path: '/update',
          redirect: (_, s) => s.extra is CharakUpdateInfo ? null : '/',
          pageBuilder: (_, s) => _rise(CharakUpdateRequiredScreen(info: s.extra! as CharakUpdateInfo))),
      GoRoute(path: '/auth/sign-in',          pageBuilder: (_, __) => _push(const SignInScreen())),
      // Phone + OTP: back once DLT approval lets MSG91 deliver SMS.
      GoRoute(path: '/auth/phone',           pageBuilder: (_, __) => _push(const PhoneEntryScreen())),
      GoRoute(path: '/auth/otp',
          // In the query string, not `extra`: `extra` is in-memory only and is
          // null if this route is ever reached any other way (a push
          // notification, a restored app, a deep link) — a bad cast would
          // crash instead of just sending the user back to enter their phone.
          redirect: (_, s) => (s.uri.queryParameters['phone']?.isNotEmpty ?? false)
              ? null : '/auth/phone',
          pageBuilder: (_, s) =>
              _push(OtpScreen(phone: s.uri.queryParameters['phone']!))),
      GoRoute(path: '/auth/name',            pageBuilder: (_, __) => _push(const NameEntryScreen())),

      // ── Main shell ───────────────────────────────────────────────────────
      GoRoute(path: '/home',                 pageBuilder: (_, __) => _rise(const HomeShell())),
      GoRoute(path: '/notifications',        pageBuilder: (_, __) => _push(const NotificationsScreen())),

      // ── Directory ────────────────────────────────────────────────────────
      GoRoute(path: '/directory',
          pageBuilder: (_, s) =>
              _card(s, DirectoryScreen(initialQuery: s.uri.queryParameters['q']))),
      GoRoute(path: '/doctor/:id',
          pageBuilder: (_, s) => _card(s, DoctorProfileScreen(doctorId: s.pathParameters['id']!))),

      // ── Booking flow ─────────────────────────────────────────────────────
      GoRoute(path: '/book/:doctorId/slots',
          pageBuilder: (_, s) => _push(SlotSelectionScreen(doctorId: s.pathParameters['doctorId']!))),
      // These three carry a booking draft built up across the previous steps
      // (selected slot, channel, intake media the patient has already picked)
      // — state that cannot be reconstructed from a URL, unlike the string
      // params above. If this route is ever reached any other way (not a
      // `context.push` from the previous step in the same session — a
      // restored app, a stray deep link), the draft is gone regardless of how
      // the route is written, so the honest fix is to send the patient back
      // to pick up the flow again rather than hand a bad cast to the screen.
      GoRoute(path: '/book/:doctorId/channel',
          redirect: (_, s) => s.extra is Map<String, dynamic>
              ? null : '/doctor/${s.pathParameters['doctorId']}',
          pageBuilder: (_, s) => _push(ChannelConfirmScreen(
            doctorId: s.pathParameters['doctorId']!,
            extra: s.extra as Map<String, dynamic>,
          ))),
      GoRoute(path: '/book/:doctorId/intake',
          redirect: (_, s) => s.extra is Map<String, dynamic>
              ? null : '/doctor/${s.pathParameters['doctorId']}',
          pageBuilder: (_, s) => _push(IntakeScreen(
            doctorId: s.pathParameters['doctorId']!,
            extra: s.extra as Map<String, dynamic>,
          ))),
      GoRoute(path: '/book/review',
          redirect: (_, s) => s.extra is Map<String, dynamic> ? null : '/home',
          pageBuilder: (_, s) => _push(ReviewConfirmScreen(booking: s.extra as Map<String, dynamic>))),

      // Outcome screens rise rather than slide — they end a flow.
      GoRoute(path: '/book/sent/:bookingId',
          pageBuilder: (_, s) => _rise(RequestSentScreen(bookingId: s.pathParameters['bookingId']!))),
      GoRoute(path: '/booking/:id/status',
          pageBuilder: (_, s) => _card(s, BookingStatusScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/pay',
          pageBuilder: (_, s) => _card(s, PaymentScreen(
                bookingId: s.pathParameters['id']!,
                type: s.uri.queryParameters['type'] ?? 'consult_fee',
              ))),
      GoRoute(path: '/booking/:id/confirmed',
          pageBuilder: (_, s) => _rise(BookingConfirmedScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/active',
          pageBuilder: (_, s) => _card(s, ActiveBookingScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/call',
          pageBuilder: (_, s) => _rise(VideoCallScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/complete',
          pageBuilder: (_, s) => _rise(VisitCompleteScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/bill',
          pageBuilder: (_, s) => _push(ProcedureBillScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/rate',
          pageBuilder: (_, s) => _push(RateScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/history-detail',
          pageBuilder: (_, s) => _card(s, HistoryDetailScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/booking/:id/complaint',
          pageBuilder: (_, s) => _push(ComplaintScreen(bookingId: s.pathParameters['id']!))),
      GoRoute(path: '/complaint',
          pageBuilder: (_, __) => _push(const ComplaintScreen())),
    ],
  );

  // A tapped notification should land on the thing it is about — above all
  // `call.incoming`, which is time-critical: the doctor is ringing now. The
  // mapping lives in `push_routes.dart` so it can be tested without a GoRouter.
  final pushSub = CharakPush.instance.messages.listen((m) {
    final route = patientPushRoute(m);
    if (route != null) router.go(route);
  });
  ref.onDispose(pushSub.cancel);

  return router;
});

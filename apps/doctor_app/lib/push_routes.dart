import 'package:charak_core/charak_core.dart';

/// Where a tapped notification should land.
///
/// [tabIndex], when set, is the HomeShell tab to select before navigating —
/// the shell is one route, so "open earnings" is a tab change plus `/home`.
class DoctorPushDestination {
  final String route;
  final int? tabIndex;

  const DoctorPushDestination(this.route, {this.tabIndex});

  @override
  bool operator ==(Object other) =>
      other is DoctorPushDestination &&
      other.route == route &&
      other.tabIndex == tabIndex;

  @override
  int get hashCode => Object.hash(route, tabIndex);

  @override
  String toString() => 'DoctorPushDestination($route, tab: $tabIndex)';
}

/// HomeShell tab order — see `screens/home/home_shell.dart`.
const int kRequestsTab = 0;
const int kScheduleTab = 1;
const int kEarningsTab = 2;
const int kProfileTab  = 3;

/// Maps a push event to where the doctor should be taken, or null to stay put.
///
/// Kept out of `router.dart` so the mapping can be tested without building a
/// GoRouter: a notification that opens the wrong screen is a bug the doctor
/// notices at the worst possible moment.
DoctorPushDestination? doctorPushDestination(CharakPushMessage message) {
  final bookingId = message.bookingId;

  switch (message.event) {
    // Time-critical and booking-specific: go straight to the request.
    case 'booking.requested':
    case 'call.incoming':
      return bookingId == null ? null : DoctorPushDestination('/request/$bookingId');

    // Money. All of it reads in one place.
    case 'payment.received':
    case 'bill.under_review':
    case 'bill.approved':
    case 'payout.paid':
      return const DoctorPushDestination('/home', tabIndex: kEarningsTab);

    // The doctor's own standing changed — the splash gate decides where a
    // newly-verified or newly-rejected doctor now belongs.
    case 'doctor.verified':
    case 'doctor.rejected':
    case 'doctor.suspended':
      return const DoctorPushDestination('/');

    case 'rating.received':
      return const DoctorPushDestination('/home', tabIndex: kProfileTab);

    case 'booking.cancelled':
    case 'booking.hold_expired':
      return const DoctorPushDestination('/home', tabIndex: kRequestsTab);

    default:
      return null;
  }
}

import 'package:charak_core/charak_core.dart';

/// Maps a push event to the route the patient should land on, or null to stay
/// put.
///
/// Kept out of `router.dart` so it can be tested without building a GoRouter.
/// Every destination here is booking-specific, so an event without a booking id
/// routes nowhere rather than to a broken path.
String? patientPushRoute(CharakPushMessage message) {
  final bookingId = message.bookingId;
  if (bookingId == null) return null;

  switch (message.event) {
    // The doctor is ringing right now — nothing else outranks this.
    case 'call.incoming':
      return '/booking/$bookingId/call';

    // Accepted means payment is due, and the slot is only held for a while.
    case 'booking.accepted':
      return '/booking/$bookingId/pay';

    case 'booking.declined':
    case 'booking.cancelled':
    case 'booking.hold_expired':
    case 'payment.confirmed':
    case 'payment.failed':
      return '/booking/$bookingId/status';

    case 'visit.running_late':
      return '/booking/$bookingId/active';

    case 'visit.completed':
    case 'booking.no_show':
      return '/booking/$bookingId/complete';

    case 'bill.approved':
      return '/booking/$bookingId/bill';

    default:
      return null;
  }
}

import 'package:charak_core/charak_core.dart';
import 'package:doctor_app/push_routes.dart';
import 'package:flutter_test/flutter_test.dart';

CharakPushMessage _msg(String event, {String? bookingId}) =>
    CharakPushMessage(event: event, bookingId: bookingId);

/// The event names here are the backend's, from
/// `backend/app/services/notifications.py`. If one is renamed there and not
/// here, the notification silently stops routing — these tests are the thing
/// that catches that.
void main() {
  group('doctorPushDestination', () {
    test('a new request opens that request, not the requests list', () {
      expect(
        doctorPushDestination(_msg('booking.requested', bookingId: 'bk-1')),
        const DoctorPushDestination('/request/bk-1'),
      );
    });

    test('an incoming call opens the request it belongs to', () {
      expect(
        doctorPushDestination(_msg('call.incoming', bookingId: 'bk-9')),
        const DoctorPushDestination('/request/bk-9'),
      );
    });

    test('a booking event with no booking id routes nowhere', () {
      // Better to leave the doctor where they are than to push `/request/null`.
      expect(doctorPushDestination(_msg('booking.requested')), isNull);
    });

    test('every money event lands on the earnings tab', () {
      for (final event in [
        'payment.received',
        'bill.under_review',
        'bill.approved',
        'payout.paid',
      ]) {
        expect(
          doctorPushDestination(_msg(event, bookingId: 'bk-1')),
          const DoctorPushDestination('/home', tabIndex: kEarningsTab),
          reason: '$event should open earnings',
        );
      }
    });

    test('a verification decision re-runs the splash gate', () {
      // Where a newly-verified or newly-rejected doctor belongs is decided in
      // one place; routing straight to /home would skip it.
      for (final event in [
        'doctor.verified',
        'doctor.rejected',
        'doctor.suspended',
      ]) {
        expect(
          doctorPushDestination(_msg(event)),
          const DoctorPushDestination('/'),
          reason: '$event should re-gate',
        );
      }
    });

    test('a new rating opens the profile tab', () {
      expect(
        doctorPushDestination(_msg('rating.received')),
        const DoctorPushDestination('/home', tabIndex: kProfileTab),
      );
    });

    test('a cancellation returns to the requests tab', () {
      expect(
        doctorPushDestination(_msg('booking.cancelled', bookingId: 'bk-1')),
        const DoctorPushDestination('/home', tabIndex: kRequestsTab),
      );
    });

    test('an unknown event is ignored rather than guessed at', () {
      expect(doctorPushDestination(_msg('something.new', bookingId: 'bk-1')), isNull);
      expect(doctorPushDestination(_msg('unknown')), isNull);
    });

    test('patient-only events do not route in the doctor app', () {
      // These are sent to patients; if one reached a doctor's device it must
      // not open a patient route that does not exist here.
      for (final event in [
        'booking.accepted',
        'booking.declined',
        'payment.confirmed',
        'visit.running_late',
      ]) {
        final destination = doctorPushDestination(_msg(event, bookingId: 'bk-1'));
        expect(
          destination?.route,
          anyOf(isNull, startsWith('/home')),
          reason: '$event must not open a patient route',
        );
      }
    });
  });
}

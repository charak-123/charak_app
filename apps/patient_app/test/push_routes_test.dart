import 'package:charak_core/charak_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/push_routes.dart';

CharakPushMessage _msg(String event, {String? bookingId}) =>
    CharakPushMessage(event: event, bookingId: bookingId);

/// The event names here are the backend's, from
/// `backend/app/services/notifications.py`. A rename there that is not made
/// here silently stops the notification routing anywhere.
void main() {
  group('patientPushRoute', () {
    test('an incoming call goes straight to the call screen', () {
      // The doctor is ringing now — this is the one event where landing on the
      // wrong screen loses the call.
      expect(
        patientPushRoute(_msg('call.incoming', bookingId: 'bk-1')),
        '/booking/bk-1/call',
      );
    });

    test('an accepted booking goes to payment', () {
      // Acceptance starts a payment hold; the slot is released if it lapses.
      expect(
        patientPushRoute(_msg('booking.accepted', bookingId: 'bk-1')),
        '/booking/bk-1/pay',
      );
    });

    test('outcome events land on the booking status screen', () {
      for (final event in [
        'booking.declined',
        'booking.cancelled',
        'booking.hold_expired',
        'payment.confirmed',
        'payment.failed',
      ]) {
        expect(
          patientPushRoute(_msg(event, bookingId: 'bk-1')),
          '/booking/bk-1/status',
          reason: '$event should open the status screen',
        );
      }
    });

    test('a running-late notice opens the active booking', () {
      expect(
        patientPushRoute(_msg('visit.running_late', bookingId: 'bk-1')),
        '/booking/bk-1/active',
      );
    });

    test('a completed visit opens the completion screen', () {
      expect(
        patientPushRoute(_msg('visit.completed', bookingId: 'bk-1')),
        '/booking/bk-1/complete',
      );
    });

    test('an approved bill opens the bill', () {
      expect(
        patientPushRoute(_msg('bill.approved', bookingId: 'bk-1')),
        '/booking/bk-1/bill',
      );
    });

    test('no booking id means no route', () {
      // Every patient destination is booking-scoped, so without an id there is
      // nowhere correct to go.
      expect(patientPushRoute(_msg('call.incoming')), isNull);
      expect(patientPushRoute(_msg('booking.accepted')), isNull);
    });

    test('an unknown event is ignored rather than guessed at', () {
      expect(patientPushRoute(_msg('something.new', bookingId: 'bk-1')), isNull);
    });

    test('doctor-only events do not route in the patient app', () {
      for (final event in [
        'booking.requested',
        'payout.paid',
        'doctor.verified',
        'bill.under_review',
      ]) {
        expect(
          patientPushRoute(_msg(event, bookingId: 'bk-1')),
          isNull,
          reason: '$event is addressed to doctors',
        );
      }
    });
  });
}

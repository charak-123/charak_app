import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/screens/booking/active_booking_screen.dart';

void main() {
  group('cancellationMessage says exactly what comes back', () {
    test('nothing paid', () {
      expect(cancellationMessage({'paid_paise': 0, 'refund_paise': 0, 'refund_pct': 100}),
          contains('not been charged'));
    });
    test('full refund', () {
      final m = cancellationMessage({'paid_paise': 80000, 'refund_paise': 80000, 'refund_pct': 100});
      expect(m, contains('full payment of ₹800'));
      expect(m, contains('5–7 working days'));
    });
    test('late: half back, the rest to the doctor', () {
      final m = cancellationMessage(
          {'paid_paise': 80000, 'refund_paise': 40000, 'refund_pct': 50, 'reason': 'late_cancellation'});
      expect(m, contains('₹400 back (50%)'));
      expect(m, contains('rest goes to the doctor'));
    });
    test('doctor already travelling', () {
      final m = cancellationMessage(
          {'paid_paise': 80000, 'refund_paise': 0, 'refund_pct': 0, 'reason': 'journey_started'});
      expect(m, contains('already started travelling'));
      expect(m, contains('₹800 fee'));
    });
    test('odd paise are shown, not rounded away', () {
      final m = cancellationMessage(
          {'paid_paise': 55555, 'refund_paise': 27777, 'refund_pct': 50, 'reason': 'late_cancellation'});
      expect(m, contains('₹277.77'));
    });
  });

  group('freeUntilLine', () {
    final now = DateTime.utc(2026, 11, 2, 6);
    Map<String, dynamic> booking(int? minutes, DateTime start) => {
          'scheduled_start': start.toIso8601String(),
          'cancellation_policy': {'free_cancellation_minutes': minutes},
        };

    test('names the cut-off two hours before a home visit', () {
      final line = freeUntilLine(booking(120, DateTime.utc(2026, 11, 2, 12)), now: now);
      expect(line, startsWith('Free cancellation until '));
    });
    test('says so when the policy has no cut-off', () {
      expect(freeUntilLine(booking(null, DateTime.utc(2026, 11, 2, 12)), now: now),
          'Free cancellation until the appointment starts.');
    });
    test('disappears once the cut-off has passed', () {
      expect(freeUntilLine(booking(120, DateTime.utc(2026, 11, 2, 7)), now: now), isNull);
    });
    test('disappears for a booking with no policy', () {
      expect(freeUntilLine({'scheduled_start': '2026-11-02T12:00:00Z'}, now: now), isNull);
    });
  });
}

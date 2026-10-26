import 'package:charak_core/charak_core.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payment(List<Map<String, dynamic>> refunds) =>
    {'id': 'p', 'status': 'completed', 'refunds': refunds};

void main() {
  group('CharakRefundSummary.fromPayments', () {
    test('null when nothing is being refunded', () {
      expect(CharakRefundSummary.fromPayments([]), isNull);
      expect(CharakRefundSummary.fromPayments([_payment([])]), isNull);
      expect(CharakRefundSummary.fromPayments([{'id': 'p'}]), isNull);
    });

    test('sums every refund on every payment, in paise', () {
      final s = CharakRefundSummary.fromPayments([
        _payment([{'amount_paise': 50000, 'status': 'processed'}]),
        _payment([{'amount_paise': 12550, 'status': 'processed'}]),
      ])!;
      expect(s.amountPaise, 62550);
      expect(s.rupees, 625.5);
      expect(s.state, CharakRefundState.completed);
    });

    test('completed only when Razorpay confirmed every refund', () {
      final s = CharakRefundSummary.fromPayments([
        _payment([
          {'amount_paise': 100, 'status': 'processed'},
          {'amount_paise': 100, 'status': 'pending'},
        ]),
      ])!;
      expect(s.state, CharakRefundState.processing);
    });

    test('one failed refund makes the whole summary delayed', () {
      final s = CharakRefundSummary.fromPayments([
        _payment([
          {'amount_paise': 100, 'status': 'processing'},
          {'amount_paise': 100, 'status': 'failed'},
        ]),
      ])!;
      expect(s.state, CharakRefundState.delayed);
    });

    test('tolerates junk in the list', () {
      final s = CharakRefundSummary.fromPayments([
        'not a map',
        {'refunds': ['also not a map', {'amount_paise': 500, 'status': 'processed'}]},
      ])!;
      expect(s.amountPaise, 500);
    });
  });

  test('messages never claim more than Razorpay confirmed', () {
    const processing = CharakRefundSummary(amountPaise: 50000, state: CharakRefundState.processing);
    const done = CharakRefundSummary(amountPaise: 50000, state: CharakRefundState.completed);
    expect(processing.message, contains('on its way'));
    expect(processing.message, isNot(contains('has been refunded')));
    expect(done.message, startsWith('₹500 has been refunded'));
  });
}

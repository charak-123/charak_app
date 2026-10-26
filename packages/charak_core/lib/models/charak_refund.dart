import '../format/charak_format.dart';

/// Where a booking's refund stands, as far as the patient needs to know.
///
/// Only as good as what Razorpay has confirmed (backend services/refunds.py):
/// [completed] means Razorpay reported the refund processed, never just "we
/// asked for it".
enum CharakRefundState {
  /// Queued or accepted by Razorpay, not yet with the patient's bank.
  processing,

  /// Razorpay confirmed every refund on the booking.
  completed,

  /// Razorpay refused, or retries ran out; ops has it.
  delayed,
}

/// The refunds on one booking, summed. Built from `GET /payments/{booking_id}`,
/// where each payment carries the refunds recorded against it.
class CharakRefundSummary {
  final int amountPaise;
  final CharakRefundState state;

  const CharakRefundSummary({required this.amountPaise, required this.state});

  double get rupees => amountPaise / 100;

  /// Null when nothing on the booking is being refunded. One delayed refund
  /// makes the whole summary delayed; one still open makes it processing.
  static CharakRefundSummary? fromPayments(List<dynamic> payments) {
    var total = 0;
    var anyFailed = false;
    var anyOpen = false;
    for (final payment in payments.whereType<Map>()) {
      for (final refund in (payment['refunds'] as List? ?? const []).whereType<Map>()) {
        total += (refund['amount_paise'] as num?)?.toInt() ?? 0;
        switch (refund['status']) {
          case 'processed':
            break;
          case 'failed':
            anyFailed = true;
          default:
            anyOpen = true;
        }
      }
    }
    if (total <= 0) return null;
    return CharakRefundSummary(
      amountPaise: total,
      state: anyFailed
          ? CharakRefundState.delayed
          : anyOpen
              ? CharakRefundState.processing
              : CharakRefundState.completed,
    );
  }

  /// One sentence for the patient, matching the push they were sent.
  String get message {
    final amount = CharakFormat.rupees(rupees);
    return switch (state) {
      CharakRefundState.processing =>
        '$amount is on its way back to your original payment method. Banks usually take 5–7 working days.',
      CharakRefundState.completed => '$amount has been refunded to your original payment method.',
      CharakRefundState.delayed =>
        "Your $amount refund is taking longer than expected. Our team is on it — you don't need to do anything.",
    };
  }
}

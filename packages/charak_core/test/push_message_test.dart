import 'package:charak_core/charak_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a push read from its data carries the event, booking and whether it was tapped', () {
    final m = CharakPushMessage.fromData(
      {'event': 'booking.accepted', 'booking_id': 'bk-1', 'title': 'Request accepted'},
      opened: true,
    );
    expect(m.event, 'booking.accepted');
    expect(m.bookingId, 'bk-1');
    expect(m.title, 'Request accepted');
    expect(m.opened, isTrue);
  });

  test('a push that only arrived is not a tap', () {
    expect(CharakPushMessage.fromData(const {'event': 'call.incoming'}).opened, isFalse);
  });

  test('a push without an event name is unknown, not a crash', () {
    expect(CharakPushMessage.fromData(const {}).event, 'unknown');
  });
}

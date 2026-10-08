import 'package:charak_core/charak_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CharakFormat.doctor', () {
    test('adds exactly one Dr.', () {
      expect(CharakFormat.doctor('Meera Kulkarni'), 'Dr. Meera Kulkarni');
      expect(CharakFormat.doctor('Dr. Meera Kulkarni'), 'Dr. Meera Kulkarni');
      expect(CharakFormat.doctor('dr Meera'), 'Dr. Meera');
    });
    test('is idempotent', () {
      expect(CharakFormat.doctor(CharakFormat.doctor('Dr. Meera')), 'Dr. Meera');
    });
    test('falls back when unknown', () {
      expect(CharakFormat.doctor(null), 'The doctor');
      expect(CharakFormat.doctor('  '), 'The doctor');
    });
  });

  test('initials ignore honorifics', () {
    expect(CharakFormat.initials('Dr. Meera Kulkarni'), 'MK');
    expect(CharakFormat.initials('Dr. Anjali Rao Patil'), 'AP');
    expect(CharakFormat.initials('Riya'), 'R');
    expect(CharakFormat.initials(''), '?');
  });

  test('rupees use Indian grouping', () {
    expect(CharakFormat.rupees(650), '₹650');
    expect(CharakFormat.rupees(1100), '₹1,100');
    expect(CharakFormat.rupees(125000), '₹1,25,000');
    expect(CharakFormat.rupees(1100.0), '₹1,100');
    expect(CharakFormat.rupees(99.5), '₹99.50');
    expect(CharakFormat.rupees(null), '—');
  });

  test('phone reads in groups', () {
    expect(CharakFormat.phone('+919820011223'), '+91 98200 11223');
    expect(CharakFormat.phone('+999000000001'), '+999000000001');
  });

  test('dayTime says Today and Tomorrow', () {
    final now = DateTime(2026, 10, 7, 9);
    expect(CharakFormat.dayTime(DateTime(2026, 10, 7, 18), now: now), 'Today, 6:00 PM');
    expect(CharakFormat.dayTime(DateTime(2026, 10, 8, 10), now: now), 'Tomorrow, 10:00 AM');
    expect(CharakFormat.dayTime(DateTime(2026, 10, 9, 17, 30), now: now), 'Fri 9 Oct, 5:30 PM');
  });

  test('channel labels are sentence case', () {
    expect(CharakFormat.channel('home_visit'), 'Home visit');
    expect(CharakFormat.channel('online_consult'), 'Online consult');
  });
}

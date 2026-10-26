import 'package:charak_core/charak_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape is backend services/prescriptions.py `public()`.
void main() {
  final json = {
    'id': 'rx-2', 'booking_id': 'bk-1', 'version': 2, 'kind': 'prescription',
    'status': 'submitted', 'patient_age': 34, 'patient_sex': 'female',
    'complaints': ' Fever ', 'diagnosis': '', 'investigations': null, 'advice': 'Rest',
    'tpg_attested': true, 'has_upload': false, 'has_pdf': true,
    'submitted_at': '2026-11-02T10:00:00+00:00', 'first_viewed_at': null,
    'supersedes_id': 'rx-1',
    'items': [
      {'position': 1, 'medicine': 'Paracetamol', 'strength': '500 mg', 'form': 'Tablet',
       'dose': '1 tablet', 'route': 'Oral', 'frequency': '1-0-1', 'duration': '5 days',
       'instructions': 'After food'},
      {'position': 2, 'medicine': 'ORS', 'dose': null, 'frequency': 'SOS'},
    ],
    'follow_up': {'id': 'fu-1', 'recommended_date': '2026-11-09', 'channel': 'home_visit',
                  'note': null, 'status': 'open'},
  };

  test('parses what the backend sends, blanks as null', () {
    final rx = CharakPrescription.fromJson(json);
    expect(rx.isSent, isTrue);
    expect(rx.isCorrection, isTrue);
    expect(rx.complaints, 'Fever');
    expect(rx.diagnosis, isNull);
    expect(rx.submittedAt, isNotNull);
    expect(rx.firstViewedAt, isNull);
    expect(rx.items, hasLength(2));
    expect(rx.followUp!.channelLabel, 'Home visit');
  });

  test('a medicine shows only the parts the doctor filled in', () {
    final rx = CharakPrescription.fromJson(json);
    expect(rx.items[0].title, 'Paracetamol 500 mg');
    expect(rx.items[0].schedule, '1 tablet · 1-0-1 · 5 days');
    expect(rx.items[0].formRoute, 'Tablet · Oral');
    expect(rx.items[1].title, 'ORS');
    expect(rx.items[1].schedule, 'SOS');
    expect(rx.items[1].formRoute, '');
  });

  test('a follow-up is sent as a plain date', () {
    final f = CharakFollowUp(date: DateTime(2026, 3, 7, 18, 30), channel: 'either', note: 'x');
    expect(f.toSubmitJson(), {'date': '2026-03-07', 'channel': 'either', 'note': 'x'});
  });
}

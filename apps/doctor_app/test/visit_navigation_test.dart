import 'package:doctor_app/visit_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('patientMapUri', () {
    test('prefers the pin the patient dropped over the typed address', () {
      // A geocoder routinely gets Indian addresses wrong; the pin does not.
      final uri = patientMapUri({
        'patient_address_lat': 12.9716,
        'patient_address_lng': 77.5946,
        'patient_address': '12 MG Road, Bengaluru',
      })!;

      expect(uri.scheme, 'geo');
      expect(uri.toString(), contains('12.9716,77.5946'));
      expect(uri.toString(), contains('MG%20Road'));
    });

    test('labels the pin generically when there is no address text', () {
      final uri = patientMapUri({
        'patient_address_lat': 12.9716,
        'patient_address_lng': 77.5946,
      })!;

      expect(uri.toString(), contains('(Patient)'));
    });

    test('falls back to a text search when there are no coordinates', () {
      final uri = patientMapUri({
        'patient_address': '12 MG Road, near Trinity, Bengaluru, 560001',
      })!;

      expect(uri.toString(), startsWith('geo:0,0?q='));
      expect(uri.toString(), contains('560001'));
    });

    test('returns null while the address is still withheld', () {
      // Before the doctor accepts, the backend nulls all three fields.
      expect(
        patientMapUri({
          'patient_address': null,
          'patient_address_lat': null,
          'patient_address_lng': null,
          'address_withheld': true,
        }),
        isNull,
      );
    });

    test('an empty address string is not a destination', () {
      expect(patientMapUri({'patient_address': '   '}), isNull);
    });

    test('a half-set coordinate pair is not trusted', () {
      // One of the two missing means the pin is unusable; the address text is
      // the only thing left worth navigating to.
      final uri = patientMapUri({
        'patient_address_lat': 12.9716,
        'patient_address_lng': null,
        'patient_address': '12 MG Road',
      })!;

      expect(uri.toString(), startsWith('geo:0,0?q='));
    });
  });

  group('patientMapWebUri', () {
    test('uses coordinates when present', () {
      expect(
        patientMapWebUri({
          'patient_address_lat': 12.9716,
          'patient_address_lng': 77.5946,
        })!.toString(),
        endsWith('query=12.9716,77.5946'),
      );
    });

    test('uses the address otherwise', () {
      expect(
        patientMapWebUri({'patient_address': '12 MG Road'})!.toString(),
        contains('query=12%20MG%20Road'),
      );
    });

    test('returns null when there is nothing to search for', () {
      expect(patientMapWebUri({}), isNull);
    });
  });
}

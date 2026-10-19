// Fixture backend for the doctor app's screen captures. Shapes follow the
// FastAPI responses; dates are relative to "now".
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();
DateTime _at(int dayOffset, int hour, [int minute = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + dayOffset, hour, minute);
}

const doctorId = 'doc-1';

/// Overrides `verification_status` on `/doctors/me` for one capture.
String? verificationOverride;

final me = <String, dynamic>{
  'accepting_requests': true,
  'id': doctorId,
  'name': 'Dr. Meera Kulkarni',
  'phone': '+919820011223',
  'category_id': 'cat-ped',
  'categories': {'name': 'Pediatrics'},
  'verification_status': 'verified',
  'offers_online_consult': true,
  'offers_home_visit': true,
  'online_consult_mode': 'scheduled',
  'service_radius_km': 3,
  'rating_avg': 4.8,
  'bio': 'Paediatrician with 11 years in Pune.',
  'photo_url': null,
  'procedure_review_threshold': 5000.0,
  'doctor_pricing': [
    {'channel': 'online_consult', 'price': 650.0, 'base_duration_min': 15, 'extra_rate_per_15min': 100.0},
    {'channel': 'home_visit', 'price': 1100.0, 'base_duration_min': 30, 'extra_rate_per_15min': 150.0, 'extra_duration_min': 10},
  ],
};

Map<String, dynamic> _req(String id, String patient, String status, DateTime start,
        {String channel = 'online_consult', double price = 650, String? address, String? issue}) =>
    {
      'id': id,
      'patient_id': 'pat-$id',
      'doctor_id': doctorId,
      'channel': channel,
      'scheduled_start': _iso(start),
      'status': status,
      'price_confirmed': price,
      'created_at': _iso(DateTime.now().subtract(const Duration(minutes: 20))),
      'patient_address': address,
      'distance_km': address != null ? 2.4 : null,
      'users': {'name': patient},
      'issue': issue,
    };

final incoming = <Map<String, dynamic>>[
  _req('rq-1', 'Riya Sharma', 'requested', _at(0, 18), channel: 'home_visit', price: 1100,
      issue: 'Fever for two days, around 101°F, with a mild cough at night. Eating less than usual.'),
  _req('rq-2', 'Kabir Desai', 'requested', _at(1, 10),
      issue: 'Red, itchy rash on both arms since yesterday. No fever.'),
  _req('rq-3', 'Ananya Nair', 'requested', _at(1, 17, 30),
      issue: 'Follow-up on ear infection. Finished the medicines last week.'),
];

final active = <Map<String, dynamic>>[
  _req('ac-1', 'Ishaan Mehta', 'paid', _at(0, 19)),
  _req('ac-2', 'Sara Khan', 'accepted', _at(1, 11), channel: 'home_visit', price: 1100,
      address: 'B-12, Lake View Society, Baner, Pune 411045'),
];

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _day(int offset) {
  final d = _at(offset, 0);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

MockClient doctorBackend() => MockClient((req) async {
      final p = req.url.path.replaceAll(RegExp(r'/$'), '');
      if (p == '/doctors/me') {
        if (verificationOverride == null) return _json(me);
        return _json({
          ...me,
          'verification_status': verificationOverride,
          if (verificationOverride == 'rejected')
            'verification_rejection_reason': 'The registration number does not match the uploaded certificate.',
        });
      }
      if (p == '/payouts/me/bank-account') {
        return _json({
          'account_holder': 'Dr Ananya Rao', 'upi_id': 'ananya@okhdfcbank',
          'account_number': '••••9012', 'ifsc': 'HDFC0001234',
          'bank_name': 'HDFC Bank', 'verified': true,
        });
      }
      if (p == '/doctors/me/procedures') {
        return _json([
          {'id': 'pr-1', 'name': 'Nebulisation', 'price': 400.0},
          {'id': 'pr-2', 'name': 'Wound dressing', 'price': 350.0},
        ]);
      }
      if (p == '/categories') {
        return _json([
          for (final c in ['General Physician', 'Pediatrics', 'Cardiology', 'Dermatology'])
            {'id': 'cat-$c', 'name': c},
        ]);
      }
      if (p == '/bookings/doctor/incoming') return _json(incoming);
      if (p == '/bookings/doctor/active') return _json(active);
      final intake = RegExp(r'^/bookings/([^/]+)/intake$').firstMatch(p);
      if (intake != null) {
        return _json([
          {
            'id': 'in-1',
            'media_type': 'text',
            'transcript_text': 'Fever for two days, around 101°F, with a mild cough at night. Eating less than usual.',
          },
        ]);
      }
      final booking = RegExp(r'^/bookings/([^/]+)$').firstMatch(p);
      if (booking != null) {
        return _json([...incoming, ...active].firstWhere((b) => b['id'] == booking.group(1),
            orElse: () => incoming.first));
      }
      if (p == '/earnings/me') {
        return _json({
          'items': [
            {'patient_name': 'Ishaan Mehta', 'channel': 'online_consult', 'scheduled_start': _iso(_at(-2, 18)), 'consult_fee': 650.0},
            {'patient_name': 'Riya Sharma', 'channel': 'home_visit', 'scheduled_start': _iso(_at(-4, 11)), 'consult_fee': 1100.0,
             'procedure_bill': {'total': 400.0, 'status': 'paid'}},
            {'patient_name': 'Kabir Desai', 'channel': 'online_consult', 'scheduled_start': _iso(_at(-9, 10)), 'consult_fee': 650.0},
          ],
          'consult_total': 2400.0,
          'procedure_total': 400.0,
          'awaiting_payment_total': 0.0,
          'pending_review_total': 0.0,
          'grand_total': 2800.0,
          'period': 'all_time',
        });
      }
      if (p == '/schedules/me/slots') {
        return _json({
          for (var d = 0; d < 7; d++)
            _day(d): [
              for (final t in ['09:00', '09:30', '10:00', '17:00', '17:30', '18:00'])
                {'start': t, 'end': t},
            ],
        });
      }
      if (p == '/slot-blocks/me') return _json([]);
      if (p.startsWith('/push') || p.startsWith('/legal')) return _json({'ok': true});
      return _json({'detail': 'fixture missing for ${req.method} $p'}, 404);
    });

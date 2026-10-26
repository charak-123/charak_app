// Fixture backend for the screen captures: realistic responses, shaped like
// the FastAPI backend's, with dates relative to "now" so Today/Tomorrow labels
// read naturally.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();
DateTime _at(int dayOffset, int hour, [int minute = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + dayOffset, hour, minute);
}

const patientId = 'pat-1';

final doctors = <Map<String, dynamic>>[
  _doctor('doc-1', 'Dr. Meera Kulkarni', 'Pediatrics', 4.8, 650, 1100,
      'Paediatrician with 11 years in Pune. Fevers, rashes, vaccinations and newborn care.', 1.2),
  _doctor('doc-2', 'Dr. Sameer Deshpande', 'General Physician', 4.9, 500, 800,
      'Family medicine and elder care. Regular home-visit practice in Kothrud.', 2.4),
  _doctor('doc-3', 'Dr. Anjali Patil', 'Dermatology', 4.7, 550, null,
      'Skin, hair and allergy consults online.', null),
  _doctor('doc-4', 'Dr. Rahul Joshi', 'Orthopedic', 4.6, 700, 900,
      'Joint pain, sports injuries and post-operative physiotherapy plans.', 3.1),
];

Map<String, dynamic> _doctor(String id, String name, String category, double rating,
        int online, int? home, String bio, double? km) =>
    {
      'id': id,
      'name': name,
      'category_id': 'cat-$category',
      'verification_status': 'verified',
      'offers_online_consult': true,
      'offers_home_visit': home != null,
      'online_consult_mode': 'scheduled',
      'service_radius_km': home != null ? 5 : null,
      'rating_avg': rating,
      'bio': bio,
      'photo_url': null,
      'categories': {'name': category},
      'doctor_pricing': [
        {'channel': 'online_consult', 'price': online.toDouble(), 'base_duration_min': 15, 'extra_rate_per_15min': 100.0},
        if (home != null)
          {'channel': 'home_visit', 'price': home.toDouble(), 'base_duration_min': 30, 'extra_rate_per_15min': 150.0},
      ],
      'distance_km': km,
      'in_service_area': km != null ? true : null,
      'years_experience': 11,
    };

Map<String, dynamic> _booking(String id, String doctorId, String status, DateTime start,
    {String channel = 'online_consult', double? price}) {
  final d = doctors.firstWhere((x) => x['id'] == doctorId);
  return {
    'id': id,
    'patient_id': patientId,
    'doctor_id': doctorId,
    'channel': channel,
    'scheduled_start': _iso(start),
    'status': status,
    'price_confirmed': price,
    'created_at': _iso(DateTime.now().subtract(const Duration(hours: 3))),
    'updated_at': _iso(DateTime.now().subtract(const Duration(hours: 1))),
    'hold_expires_at': status == 'accepted' ? _iso(DateTime.now().add(const Duration(minutes: 8))) : null,
    'payment_attempts': 0,
    'patient_address': channel == 'home_visit' ? 'Flat 4B, Rose Lane, Kothrud, Pune 411038' : null,
    'distance_km': channel == 'home_visit' ? 2.4 : null,
    'doctors': {'name': d['name'], 'photo_url': null, 'categories': d['categories']},
  };
}

final bookings = <Map<String, dynamic>>[
  _booking('bk-accepted', 'doc-2', 'accepted', _at(1, 11), channel: 'home_visit', price: 800),
  _booking('bk-requested', 'doc-1', 'requested', _at(2, 17, 30), price: 650),
  _booking('bk-paid', 'doc-3', 'paid', _at(0, 19), price: 550),
  _booking('bk-done', 'doc-4', 'completed', _at(-6, 10), channel: 'home_visit', price: 900),
  _booking('bk-done2', 'doc-1', 'completed', _at(-20, 18), price: 650),
  _booking('bk-declined', 'doc-3', 'declined', _at(-3, 12), price: 550),
  _booking('bk-cancelled', 'doc-3', 'cancelled', _at(1, 18), price: 550),
  _booking('bk-refunded', 'doc-1', 'cancelled', _at(-9, 17, 30), price: 650),
];

/// Refunds the backend reports per booking (GET /payments/{id} embeds them).
final _refunds = <String, List<Map<String, dynamic>>>{
  'bk-cancelled': [{'id': 'rf-1', 'amount_paise': 55000, 'status': 'processing', 'reason': 'booking_cancelled'}],
  'bk-refunded': [{'id': 'rf-2', 'amount_paise': 65000, 'status': 'processed', 'reason': 'booking_cancelled'}],
};

Map<String, List<Map<String, String>>> _slots() {
  final out = <String, List<Map<String, String>>>{};
  for (var d = 0; d < 6; d++) {
    final day = _at(d, 0);
    final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    out[key] = [
      for (final t in ['10:00', '10:30', '11:00', '16:30', '17:00', '17:30', '18:00', '18:30', '19:00'])
        {'start': t, 'end': t},
    ];
  }
  return out;
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Answers every request the patient app makes.
MockClient patientBackend() => MockClient((req) async {
      final p = req.url.path.replaceAll(RegExp(r'/$'), '');
      final m = req.method;
      if (p == '/users/me') {
        return _json({'id': patientId, 'name': 'Aarav Kulkarni', 'phone': '+919876543210', 'email': 'aarav@example.com'});
      }
      if (p == '/categories') {
        return _json([
          for (final c in ['General Physician', 'Pediatrics', 'Cardiology', 'Dermatology', 'Orthopedic'])
            {'id': 'cat-$c', 'name': c},
        ]);
      }
      if (p == '/doctors/search') {
        return _json({'total': doctors.length, 'items': doctors, 'has_more': false, 'located': true, 'sort': 'rating'});
      }
      final slots = RegExp(r'^/doctors/([^/]+)/slots$').firstMatch(p);
      if (slots != null) return _json(_slots());
      final doc = RegExp(r'^/doctors/([^/]+)$').firstMatch(p);
      if (doc != null) return _json(doctors.firstWhere((d) => d['id'] == doc.group(1), orElse: () => doctors.first));
      if (p == '/bookings/patient/list') return _json(bookings);
      final intake = RegExp(r'^/bookings/([^/]+)/intake$').firstMatch(p);
      if (intake != null) {
        return _json([
          {'id': 'in-1', 'media_type': 'text', 'transcript_text': 'Fever for two days, around 101°F, with a mild cough at night.'},
        ]);
      }
      final bill = RegExp(r'^/bookings/([^/]+)/procedure-bill$').firstMatch(p);
      if (bill != null) return _json(<String, dynamic>{}, 404);
      final rate = RegExp(r'^/bookings/([^/]+)/rate$').firstMatch(p);
      if (rate != null && m == 'GET') return _json(<String, dynamic>{}, 404);
      final booking = RegExp(r'^/bookings/([^/]+)$').firstMatch(p);
      if (booking != null) {
        return _json(bookings.firstWhere((b) => b['id'] == booking.group(1), orElse: () => bookings.first));
      }
      final order = RegExp(r'^/payments/([^/]+)/order$').firstMatch(p);
      if (order != null) {
        final b = bookings.firstWhere((b) => b['id'] == order.group(1), orElse: () => bookings.first);
        return _json({'order_id': 'order_fixture', 'amount': ((b['price_confirmed'] as num? ?? 0) * 100).round(), 'currency': 'INR', 'key_id': 'rzp_test'});
      }
      final pay = RegExp(r'^/payments/([^/]+)$').firstMatch(p);
      if (pay != null) {
        final b = bookings.firstWhere((b) => b['id'] == pay.group(1), orElse: () => bookings.first);
        final refunds = _refunds[b['id']] ?? const <Map<String, dynamic>>[];
        final settled = refunds.isNotEmpty && refunds.every((r) => r['status'] == 'processed');
        return _json([
          {
            'id': 'pay-${b['id']}', 'type': 'consult_fee', 'amount': b['price_confirmed'],
            'status': settled ? 'refunded' : 'completed', 'razorpay_payment_id': 'pay_Nx81fixture',
            'created_at': _iso(_at(-6, 9)), 'refunds': refunds,
          },
        ]);
      }
      if (p == '/addresses') {
        return _json([
          {'id': 'addr-1', 'label': 'Home', 'line1': 'Flat 4B, Rose Lane', 'line2': 'Kothrud', 'city': 'Pune', 'pincode': '411038', 'lat': 18.5, 'lng': 73.8, 'is_default': true},
        ]);
      }
      if (p == '/notifications/unread-count') return _json({'count': 2});
      if (p == '/notifications') {
        return _json([
          {'id': 'n1', 'event': 'booking.accepted', 'booking_id': 'bk-accepted', 'title': 'Dr. Sameer Deshpande accepted', 'body': 'Pay ₹800 to confirm your home visit', 'created_at': _iso(DateTime.now().subtract(const Duration(minutes: 12))), 'read_at': null},
          {'id': 'n2', 'event': 'payment.confirmed', 'booking_id': 'bk-paid', 'title': 'Payment received', 'body': 'Your consult with Dr. Anjali Patil is confirmed', 'created_at': _iso(DateTime.now().subtract(const Duration(hours: 3))), 'read_at': null},
          {'id': 'n3', 'event': 'visit.completed', 'booking_id': 'bk-done', 'title': 'Visit complete', 'body': 'How was Dr. Rahul Joshi? Rate your visit', 'created_at': _iso(DateTime.now().subtract(const Duration(days: 6))), 'read_at': '2026-10-01T10:00:00Z'},
        ]);
      }
      if (p.startsWith('/push') || p.startsWith('/legal')) return _json({'ok': true});
      return _json({'detail': 'fixture missing for $m $p'}, 404);
    });

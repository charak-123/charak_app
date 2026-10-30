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
    'cancellation_policy': _policies[channel],
  };
}

/// Cancellation policies as GET /legal/cancellation-policy serves them (LD-005).
final _policies = <String, Map<String, dynamic>>{
  'home_visit': {
    'channel': 'home_visit', 'version': '2026-10-26', 'free_cancellation_minutes': 120,
    'summary': 'Free cancellation up to 2 hours before your visit. Cancel later and you get 50% '
        "back, as long as the doctor hasn't started travelling. Once the doctor is on the way, "
        "the fee isn't refunded. If the doctor cancels or doesn't come, you get a full refund.",
  },
  'online_consult': {
    'channel': 'online_consult', 'version': '2026-10-26', 'free_cancellation_minutes': null,
    'summary': 'Cancel any time before your consultation starts for a full refund. If the doctor '
        "cancels or doesn't join, you get a full refund.",
  },
};

Map<String, dynamic> _doc(String type, String title, String url, {bool accepted = true}) =>
    {'type': type, 'version': '2026-10-01', 'title': title, 'url': url, 'material': true,
     'accepted': accepted};

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

/// Answers every request the patient app makes. [newPatient]: Terms and
/// Privacy not yet accepted (the sign-up consent step).
MockClient patientBackend({bool newPatient = false, bool doctorOnTheWay = false}) => MockClient((req) async {
      final p = req.url.path.replaceAll(RegExp(r'/$'), '');
      final m = req.method;
      if (p == '/legal/current') {
        final docs = [
          _doc('tos', 'Terms of Use', 'https://www.charak.care/terms', accepted: !newPatient),
          _doc('privacy', 'Privacy Policy', 'https://www.charak.care/privacy', accepted: !newPatient),
          _doc('telemedicine', 'Telemedicine Consent', 'https://www.charak.care/telemedicine',
              accepted: false),
        ];
        return _json({
          'documents': docs,
          'missing': [for (final d in docs) if (d['accepted'] != true && d['type'] != 'telemedicine') d],
        });
      }
      if (p == '/legal/cancellation-policy') {
        return _json(_policies[req.url.queryParameters['channel']] ?? _policies['online_consult']!);
      }
      if (p == '/me/payments') {
        return _json([
          for (final id in ['bk-paid', 'bk-cancelled', 'bk-refunded', 'bk-done'])
            () {
              final b = bookings.firstWhere((b) => b['id'] == id);
              final refunds = _refunds[id] ?? const <Map<String, dynamic>>[];
              return {
                'id': 'pay-$id', 'booking_id': id, 'amount': b['price_confirmed'], 'type': 'consult_fee',
                'status': refunds.isNotEmpty && refunds.every((r) => r['status'] == 'processed')
                    ? 'refunded' : 'completed',
                'paid_at': b['created_at'], 'created_at': b['created_at'], 'refunds': refunds,
                'bookings': {'id': id, 'channel': b['channel'], 'scheduled_start': b['scheduled_start'],
                             'status': b['status'], 'doctors': {'name': (b['doctors'] as Map)['name']}},
              };
            }(),
        ]);
      }
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
      final help = RegExp(r'^/bookings/([^/]+)/help$').firstMatch(p);
      if (help != null) {
        return _json({
          'help_opens_at': _iso(DateTime.now().subtract(const Duration(minutes: 5))),
          'grace_minutes': 10,
          'can_report': ['call_failed', 'other'],
          'incident': {
            'id': 'inc-1', 'case_ref': 'CHK-7F3K2', 'booking_id': help.group(1), 'type': 'doctor_no_show',
            'reported_as': 'doctor_not_joined', 'status': 'reported', 'remedy_eligible': true,
            'remedy': 'pending',
            'remedies': {'available': true, 'refund_paise': 65000, 'replacement_budget_paise': 65000,
                         'channel': 'online_consult', 'exclude_doctor_id': 'doc-1',
                         'default_refund_at': _iso(DateTime.now().add(const Duration(hours: 23)))},
          },
          'reschedule_request': help.group(1) == 'bk-paid' ? null : {
            'id': 'rr-1', 'booking_id': help.group(1), 'cause': 'doctor_device',
            'note': 'My connection dropped, sorry.',
            'options': [_iso(_at(1, 10)), _iso(_at(1, 17, 30))],
            'status': 'proposed', 'expires_at': _iso(DateTime.now().add(const Duration(hours: 22))),
          },
        });
      }
      final docReviews = RegExp(r'^/doctors/([^/]+)/reviews$').firstMatch(p);
      if (docReviews != null) {
        return _json({
          'count': 23, 'overall': 4.6, 'is_new': false, 'min_reviews_shown': 5,
          'dimensions': {'professionalism': 4.8, 'communication': 4.5, 'punctuality': 4.1},
          'explanation': 'The average of up to the last 200 reviews from patients who completed a visit.',
          'reviews': [
            {'id': 'rv1', 'overall': 5, 'comment': 'Explained my daughter\'s fever patiently and followed up the next day.', 'created_at': _iso(_at(-5, 10)), 'edited': false},
            {'id': 'rv2', 'overall': 4, 'comment': 'Arrived about 15 minutes late but was thorough.', 'created_at': _iso(_at(-12, 10)), 'edited': true},
          ],
        });
      }
      final myReview = RegExp(r'^/bookings/([^/]+)/review$').firstMatch(p);
      if (myReview != null) {
        return _json({'review': null, 'can_review': true, 'review_until': _iso(_at(13, 10))});
      }
      final prices = RegExp(r'^/doctors/([^/]+)/prices$').firstMatch(p);
      if (prices != null) {
        final d = doctors.firstWhere((x) => x['id'] == prices.group(1), orElse: () => doctors.first);
        final online = (d['doctor_pricing'] as List).first['price'] as double;
        return _json({
          'channels': {
            'online_consult': [
              {'id': 'r-on-15', 'channel': 'online_consult', 'visit_category': 'initial', 'duration_min': 15, 'price_paise': (online * 100).round()},
              {'id': 'r-on-30', 'channel': 'online_consult', 'visit_category': 'initial', 'duration_min': 30, 'price_paise': (online * 160).round()},
            ],
            if (d['offers_home_visit'] == true)
              'home_visit': [
                {'id': 'r-hv-30', 'channel': 'home_visit', 'visit_category': 'initial', 'duration_min': 30, 'price_paise': 80000},
                {'id': 'r-hv-45', 'channel': 'home_visit', 'visit_category': 'initial', 'duration_min': 45, 'price_paise': 110000},
              ],
          },
          'follow_up_validity_days': 7,
          'offers_follow_up_prices': true,
        });
      }
      final followUp = RegExp(r'^/bookings/([^/]+)/follow-up-options$').firstMatch(p);
      if (followUp != null) {
        return _json({
          'follow_up_of': followUp.group(1), 'doctor_id': 'doc-1',
          'until': _iso(_at(6, 23, 59)),
          'channels': {
            'online_consult': [
              {'id': 'r-fu-10', 'channel': 'online_consult', 'visit_category': 'follow_up', 'duration_min': 10, 'price_paise': 30000},
              {'id': 'r-fu-15', 'channel': 'online_consult', 'visit_category': 'follow_up', 'duration_min': 15, 'price_paise': 0},
            ],
          },
        });
      }
      if (p == '/me/follow-ups') return _json(<dynamic>[]);
      final slots = RegExp(r'^/doctors/([^/]+)/slots$').firstMatch(p);
      if (slots != null) return _json(_slots());
      final doc = RegExp(r'^/doctors/([^/]+)$').firstMatch(p);
      if (doc != null) return _json(doctors.firstWhere((d) => d['id'] == doc.group(1), orElse: () => doctors.first));
      if (p == '/bookings/patient/list') {
        return _json([
          // A paid home visit whose doctor has tapped Start Journey.
          if (doctorOnTheWay)
            {
              ..._booking('bk-on-the-way', 'doc-2', 'paid', _at(0, 18), channel: 'home_visit', price: 800),
              'journey_started_at': _iso(DateTime.now().subtract(const Duration(minutes: 9))),
            },
          ...bookings,
        ]);
      }
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

// Screen captures: every patient screen rendered through the real router with
// the real components, against a fixture backend. Run
//
//   CAPTURE_SCREENS=1 flutter test --update-goldens test/screens/screens_capture_test.dart
//
// and review build/screens/*.png (gitignored) — the design QA pass. Not a
// pixel-diff gate: fixtures use relative dates, so images change daily, and
// the tests are skipped unless CAPTURE_SCREENS is set.
import 'dart:convert';
import 'dart:io';

import 'package:charak_core/charak_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/main.dart';
import 'package:patient_app/router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<void> _font(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

String? _packageDir(String name) {
  final config = File('.dart_tool/package_config.json');
  for (final p in (jsonDecode(config.readAsStringSync())['packages'] as List)) {
    if (p['name'] == name) {
      final root = Uri.parse(p['rootUri'] as String);
      return root.isAbsolute ? root.toFilePath() : config.parent.uri.resolveUri(root).toFilePath();
    }
  }
  return null;
}

/// (file name, route, optional extra)
final _screens = <(String, String, Object?)>[
  ('01_sign_in', '/auth/sign-in', null),
  ('02_profile_step', '/auth/name', null),
  ('03_home', '/home', null),
  ('04_directory', '/directory', null),
  ('05_doctor_profile', '/doctor/doc-1', null),
  ('06_channel_and_length', '/book/doc-2/channel', null),
  ('06b_slots', '/book/doc-1/slots', {
    'doctor_id': 'doc-1', 'channel': 'online_consult', 'price_rule_id': 'r-on-30',
    'duration_min': 30, 'price_paise': 104000, 'visit_category': 'initial',
  }),
  ('06c_follow_up_prices', '/book/doc-1/channel', {'follow_up_of': 'bk-done'}),
  ('07_booking_status_requested', '/booking/bk-requested/status', null),
  ('08_booking_status_accepted', '/booking/bk-accepted/status', null),
  ('09_payment', '/booking/bk-accepted/pay', null),
  ('10_active_booking', '/booking/bk-paid/active', null),
  ('11_history_detail', '/booking/bk-done/history-detail', null),
  ('12_rate', '/booking/bk-done/rate', null),
  ('13_complaint', '/booking/bk-done/complaint', null),
  ('14_notifications', '/notifications', null),
  ('15_booking_status_cancelled_refund', '/booking/bk-cancelled/status', null),
  ('16_history_detail_refunded', '/booking/bk-refunded/history-detail', null),
  ('18_signup_consent', '/auth/name', null),
  ('19_review_confirm_online', '/book/review', {
    'doctor_id': 'doc-1', 'channel': 'online_consult', 'price_rule_id': 'r-on-30',
    'duration_min': 30, 'price_paise': 104000, 'visit_category': 'initial',
    'scheduled_start': DateTime.now().add(const Duration(days: 1, hours: 3)).toUtc().toIso8601String(),
    'text': 'Fever for two days, around 101°F, with a mild cough at night.',
  }),
  ('20_review_confirm_home', '/book/review', {
    'doctor_id': 'doc-2', 'channel': 'home_visit', 'address_id': 'addr-1',
    'scheduled_start': DateTime.now().add(const Duration(days: 1, hours: 3)).toUtc().toIso8601String(),
    'text': 'Knee pain after a fall yesterday.',
  }),
  ('21_payments', '/payments', null),
  ('22_get_help', '/booking/bk-paid/help', null),
  ('23_get_help_reschedule', '/booking/bk-accepted/help', null),
  ('17_update_required', '/update',
      const CharakUpdateInfo(minVersion: '1.2.0', storeUrl: 'https://play.google.com/store/apps/details?id=com.charak.patient_app')),
];

void main() {
  setUpAll(() async {
    final core = _packageDir('charak_core')!;
    await _font(CharakType.family, '$core/fonts/AnekLatin-Variable.ttf');
    await _font(CharakType.familyDevanagari, '$core/fonts/AnekDevanagari-Variable.ttf');
    final lucide = _packageDir('lucide_icons_flutter');
    if (lucide != null) await _font('packages/lucide_icons_flutter/Lucide', '$lucide/assets/lucide.ttf');
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final material = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (material.existsSync()) await _font('MaterialIcons', material.path);
    // Native plugins with no test implementation.
    for (final ch in ['razorpay_flutter', 'flutter.baseflow.com/geolocator', 'flutter.baseflow.com/geocoding']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });

  for (final (name, route, extra) in _screens) {
    testWidgets(name, skip: !Platform.environment.containsKey('CAPTURE_SCREENS'), (tester) async {
      // CAPTURE_SIZE=360x800 for a typical Android phone (default iPhone 390x844);
      // CAPTURE_TEXT_SCALE=1.15 to mimic Samsung's larger default font.
      final size = (Platform.environment['CAPTURE_SIZE'] ?? '390x844').split('x').map(double.parse).toList();
      tester.view.physicalSize = Size(size[0] * 3, size[1] * 3);
      tester.view.devicePixelRatio = 3;
      final textScale = double.tryParse(Platform.environment['CAPTURE_TEXT_SCALE'] ?? '');
      if (textScale != null) tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      addTearDown(tester.view.reset);

      CharakColors.useScheme(CharakScheme.patient);
      ApiClient.debugClient = patientBackend(newPatient: name.contains('consent'));
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'fixture-token'});
      SharedPreferences.setMockInitialValues({'user_id': patientId, 'user_name': 'Aarav Kulkarni'});

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const PatientApp()));
      await tester.pump(const Duration(milliseconds: 100));
      final router = container.read(routerProvider);
      if (route == '/auth/name' || route == '/auth/sign-in') {
        router.go(route, extra: extra);
      } else {
        router.go('/home');
        await tester.pump(const Duration(milliseconds: 500));
        if (route != '/home') router.push(route, extra: extra);
      }
      // Let requests resolve and entrance motion finish (looping animations
      // never settle, so pump a fixed time instead of pumpAndSettle).
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await expectLater(find.byType(PatientApp), matchesGoldenFile('../../build/screens/$name.png'));
    });
  }
}

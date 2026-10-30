// Screen captures: every doctor screen rendered through the real router with
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
import 'package:doctor_app/main.dart';
import 'package:doctor_app/router.dart';
import 'package:doctor_app/screens/home/shell_providers.dart';
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

/// (file name, route, tab index for /home)
final _screens = <(String, String, int?)>[
  ('01_sign_in', '/auth/sign-in', null),
  ('02_requests', '/home', 0),
  ('02b_requests_not_listed', '/home', 0),
  ('03_schedule', '/home', 1),
  ('04_earnings', '/home', 2),
  ('05_profile', '/home', 3),
  ('06_request_detail', '/request/rq-1', null),
  ('07_active_visit', '/visit/ac-2', null),
  ('08_profile_setup', '/onboarding/profile', null),
  ('08a_verification_pending', '/onboarding/verification-pending', null),
  ('08b_verification_rejected', '/onboarding/verification-pending', null),
  ('08c_verified_welcome', '/onboarding/verified', null),
  ('09_channels', '/setup/channels', null),
  ('10_pricing', '/setup/pricing', null),
  ('11_payout', '/setup/payout', null),
  ('12_online_hours', '/setup/online', null),
  ('13_home_visit_settings', '/setup/home-visit', null),
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

  for (final (name, route, tab) in _screens) {
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

      CharakColors.useScheme(CharakScheme.doctor);
      verificationOverride = name.contains('pending') ? 'pending' : name.contains('rejected') ? 'rejected' : null;
      notListedOverride = name.contains('not_listed');
      ApiClient.debugClient = doctorBackend();
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'fixture-token'});
      SharedPreferences.setMockInitialValues({'user_id': doctorId, 'user_name': 'Dr. Meera Kulkarni'});

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DoctorApp()));
      await tester.pump(const Duration(milliseconds: 100));
      final router = container.read(routerProvider);
      if (tab != null) container.read(doctorTabIndexProvider.notifier).state = tab;
      if (route.startsWith('/auth')) {
        router.go(route);
      } else {
        router.go('/home');
        await tester.pump(const Duration(milliseconds: 500));
        if (route != '/home') router.push(route);
      }
      // Let requests resolve and entrance motion finish (looping animations
      // never settle, so pump a fixed time instead of pumpAndSettle).
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await expectLater(find.byType(DoctorApp), matchesGoldenFile('../../build/screens/$name.png'));
    });
  }
}

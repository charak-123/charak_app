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
  ('03_schedule', '/home', 1),
  ('04_earnings', '/home', 2),
  ('05_profile', '/home', 3),
  ('06_request_detail', '/request/rq-1', null),
  ('07_active_visit', '/visit/ac-2', null),
  ('08_profile_setup', '/onboarding/profile', null),
  ('08c_verified_welcome', '/onboarding/verified', null),
  ('09_channels', '/setup/channels', null),
  ('10_pricing', '/setup/pricing', null),
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
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      CharakColors.useScheme(CharakScheme.doctor);
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

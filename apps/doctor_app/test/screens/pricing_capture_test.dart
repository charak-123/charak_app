// Screen capture of the doctor's pricing editor against a fixture backend.
//
//   CAPTURE_SCREENS=1 flutter test --update-goldens test/screens/pricing_capture_test.dart
//
// and review build/screens/*.png (gitignored). Skipped unless CAPTURE_SCREENS is set.
import 'dart:convert';
import 'dart:io';

import 'package:charak_core/charak_core.dart';
import 'package:doctor_app/screens/setup/pricing_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _backend = MockClient((req) async {
  final p = req.url.path;
  if (p == '/doctors/me') {
    return _json({
      'id': 'doc-1', 'name': 'Dr. Meera Kulkarni', 'offers_online_consult': true,
      'offers_home_visit': true, 'procedure_review_threshold': 1500,
      'doctor_procedures': [{'id': 'p1', 'name': 'Dressing', 'price': 250, 'active': true}],
    });
  }
  if (p == '/doctors/me/prices') {
    return _json({
      'rules': [
        {'id': 'r1', 'channel': 'online_consult', 'visit_category': 'initial', 'duration_min': 15, 'price_paise': 60000},
        {'id': 'r2', 'channel': 'online_consult', 'visit_category': 'initial', 'duration_min': 30, 'price_paise': 100000},
        {'id': 'r3', 'channel': 'online_consult', 'visit_category': 'follow_up', 'duration_min': 10, 'price_paise': 0},
        {'id': 'r4', 'channel': 'home_visit', 'visit_category': 'initial', 'duration_min': 30, 'price_paise': 120000},
      ],
      'follow_up_validity_days': 7,
      'durations': [10, 15, 20, 30, 45, 60],
    });
  }
  return http.Response('{}', 404);
});

void main() {
  setUpAll(() async {
    final core = _packageDir('charak_core')!;
    await _font(CharakType.family, '$core/fonts/AnekLatin-Variable.ttf');
    final lucide = _packageDir('lucide_icons_flutter');
    if (lucide != null) await _font('packages/lucide_icons_flutter/Lucide', '$lucide/assets/lucide.ttf');
  });

  testWidgets('pricing_matrix', skip: !Platform.environment.containsKey('CAPTURE_SCREENS'), (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    CharakColors.useScheme(CharakScheme.doctor);
    ApiClient.debugClient = _backend;
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'fixture-token'});
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: charakMaterialTheme(), home: const PricingSetupScreen()),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../build/screens/pricing_matrix.png'));
  });
}

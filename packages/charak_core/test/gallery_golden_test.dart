// Renders the design-system gallery on both schemes with the real Anek font.
//
//   cd packages/charak_core
//   flutter test --update-goldens test/gallery_golden_test.dart   # refresh
//   flutter test test/gallery_golden_test.dart                     # compare
//
// Output: design-system/screenshots/gallery_{patient,doctor}.png. Commit the
// refreshed PNGs with any visual change so reviewers can see it.
import 'dart:io';

import 'package:charak_core/charak_core.dart';
import 'package:charak_core/gallery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont(CharakType.family, 'fonts/AnekLatin-Variable.ttf');
    await _loadFont(CharakType.familyDevanagari, 'fonts/AnekDevanagari-Variable.ttf');
    // Material icons for the glyphs in the gallery.
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) await _loadFont('MaterialIcons', icons.path);
  });

  for (final (name, scheme) in [('patient', CharakScheme.patient), ('doctor', CharakScheme.doctor)]) {
    testWidgets('gallery · $name', (tester) async {
      CharakColors.useScheme(scheme);
      tester.view.physicalSize = const Size(390 * 2, 2300 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ShadApp(
        debugShowCheckedModeBanner: false,
        theme: charakShadTheme(),
        materialThemeBuilder: (_, __) => charakMaterialTheme(),
        home: const CharakGallery(),
      ));
      // Loops (live pulse, shimmer) never settle, so advance past every
      // entrance instead of pumpAndSettle.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await expectLater(
        find.byType(CharakGallery),
        matchesGoldenFile('../../../design-system/screenshots/gallery_$name.png'),
      );
      CharakColors.useScheme(CharakScheme.patient);
    });
  }
}

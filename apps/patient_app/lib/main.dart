import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:charak_core/charak_core.dart';
import 'router.dart';

void main() async {
  // Wraps startup so a crash anywhere — framework or not — reaches
  // Crashlytics instead of just scrolling past in the console. See
  // CharakCrash's doc comment for why both halves of Flutter's error surface
  // need separate handlers.
  await CharakCrash.runGuarded(() {
    // Design System V2: the patient app runs on cream + white surfaces.
    CharakColors.useScheme(CharakScheme.patient);
    return const ProviderScope(child: PatientApp());
  });
}

class PatientApp extends ConsumerWidget {
  const PatientApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShadApp.router(
      title: 'Charak',
      theme: charakShadTheme(),
      materialThemeBuilder: (context, theme) => charakMaterialTheme(),
      routerConfig: ref.watch(routerProvider),
      builder: charakPhoneTextScale,
      scrollBehavior: const CharakScrollBehavior(),
      debugShowCheckedModeBanner: false,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // Design System V2: the doctor app runs on ink surfaces.
    CharakColors.useScheme(CharakScheme.doctor);
    return const ProviderScope(child: DoctorApp());
  });
}

class DoctorApp extends ConsumerWidget {
  const DoctorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShadApp.router(
      title: 'Charak Doctor',
      theme: charakShadTheme(),
      materialThemeBuilder: (context, theme) => charakMaterialTheme(),
      routerConfig: ref.watch(routerProvider),
      builder: charakPhoneTextScale,
      scrollBehavior: const CharakScrollBehavior(),
      debugShowCheckedModeBanner: false,
    );
  }
}

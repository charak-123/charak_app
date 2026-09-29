import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:charak_core/charak_core.dart';
import 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const ProviderScope(child: DoctorApp()));
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
      debugShowCheckedModeBanner: false,
    );
  }
}

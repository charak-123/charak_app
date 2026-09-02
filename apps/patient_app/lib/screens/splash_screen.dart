import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      context.go('/auth/phone');
      return;
    }
    // Check if profile is complete (name set)
    final user = auth.user;
    if (user == null || (user['name'] as String?)?.isEmpty != false) {
      context.go('/auth/name');
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.bg,
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('charak', style: CharakText.display.copyWith(color: CharakColors.primary)),
        const SizedBox(height: 8),
        Text('healthcare at your door',
            style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
      ]),
    ),
  );
}

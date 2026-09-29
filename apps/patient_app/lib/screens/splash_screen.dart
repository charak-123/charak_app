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
    backgroundColor: CharakColors.ground,
    body: SafeArea(
      child: Padding(
        // The mark sits slightly above the optical centre.
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CharakLogoMark(height: 140),
              const SizedBox(height: 24),
              const CharakWordmark(size: 30),
              const SizedBox(height: 10),
              Text(
                'Home visits & online consults',
                textAlign: TextAlign.center,
                style: CharakText.body.copyWith(color: CharakColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

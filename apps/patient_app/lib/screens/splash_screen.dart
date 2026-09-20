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
    body: SafeArea(
      child: Padding(
        // `.body.center-col` with an 80px optical lift off the bottom.
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: CharakColors.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.add, size: 30, color: Colors.white),
            ),
            const SizedBox(height: 18),
            // `.brand-mark` — 26px/700, -0.02em, with the final "k" in primary.
            Text.rich(
              const TextSpan(
                children: [
                  TextSpan(text: 'Chara'),
                  TextSpan(text: 'k', style: TextStyle(color: CharakColors.primary)),
                ],
              ),
              style: CharakText.display.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.02 * 26,
                color: CharakColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Home visits & online consults',
              style: TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 13.5,
                height: 1.4,
                color: CharakColors.inkMuted,
              ),
            ),
            const SizedBox(height: 36),
            const SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CharakSkeleton(height: 12),
                  SizedBox(height: 8),
                  CharakSkeleton(height: 12, width: 160),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

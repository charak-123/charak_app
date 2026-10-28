import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

/// Google Sign-In. Replaces phone + OTP until DLT approval lets MSG91 deliver
/// SMS; the phone number is collected on the next step instead.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _State();
}

class _State extends ConsumerState<SignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _run(Future<bool?> Function() signIn) async {
    setState(() { _loading = true; _error = null; });
    try {
      final isNew = await signIn();
      if (!mounted || isNew == null) return;   // picker closed
      context.go(isNew ? '/onboarding/profile' : '/');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authProvider.notifier);
    return Scaffold(
      backgroundColor: CharakColors.ground,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const CharakLogoMark(height: 72),
                const SizedBox(height: 18),
                GestureDetector(
                  // store-review access (hidden)
                  onLongPress: () => _run(() async { await auth.demoLogin('doctor'); return false; }),
                  child: Text('Welcome, Doctor', style: charakScreenTitleStyle),
                ),
                const SizedBox(height: 5),
                Text(
                  'Sign in with your Google account. No password, ever.',
                  style: charakScreenSubStyle,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
                ],
              ]),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: CharakLegalFooter(
              termsType: 'practitioner_terms',
              termsTitle: 'Practitioner Agreement',
              afterwards: 'You will be asked to sign them before you take bookings.',
            ),
          ),
          CharakCtaBar.single(
            CharakButton(
              label: 'Continue with Google',
              isLoading: _loading,
              onPressed: () => _run(() => auth.signInWithGoogle('doctor')),
            ),
          ),
        ]),
      ),
    );
  }
}

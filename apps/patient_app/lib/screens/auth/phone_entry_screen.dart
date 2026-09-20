import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});
  @override
  ConsumerState<PhoneEntryScreen> createState() => _State();
}

class _State extends ConsumerState<PhoneEntryScreen> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _e164 => '+91${_ctrl.text.trim()}';
  bool get _valid  => _ctrl.text.trim().length == 10;

  Future<void> _send() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).sendOtp(_e164, 'patient');
      if (mounted) context.push('/auth/otp', extra: _e164);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.bg,
    body: SafeArea(
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            // `.body` with the screen's 26px top inset.
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your phone number', style: charakScreenTitleStyle),
              const SizedBox(height: 5),
              const Text(
                "We'll send a one-time code to verify it's you.",
                style: charakScreenSubStyle,
              ),
              const SizedBox(height: 26),
              CharakField(
                label: 'Mobile number',
                controller: _ctrl,
                focusNode: _focus,
                autofocus: true,
                keyboardType: TextInputType.phone,
                tabular: true,
                placeholder: '98765 43210',
                error: _error,
                hint: 'OTP-based signup. No password, ever.',
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                prefixBox: CharakField.staticBox('+91'),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) { if (_valid) _send(); },
              ),
            ]),
          ),
        ),
        CharakCtaBar.single(
          ValueListenableBuilder(
            valueListenable: _ctrl,
            builder: (_, __, ___) => CharakButton(
              label: 'Continue',
              isLoading: _loading,
              onPressed: _valid ? _send : null,
            ),
          ),
        ),
      ]),
    ),
  );
}

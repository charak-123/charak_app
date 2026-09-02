import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

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
      child: Padding(
        padding: const EdgeInsets.all(CharakSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 40),
          Text('Enter your\nmobile number', style: CharakText.display),
          const SizedBox(height: 8),
          Text("We'll send an OTP to verify",
              style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
          const SizedBox(height: 32),
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            style: CharakText.h1,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) { if (_valid) _send(); },
            decoration: InputDecoration(
              prefixText: '+91  ',
              prefixStyle: CharakText.h1.copyWith(color: CharakColors.inkMuted),
              hintText: '9876543210',
              hintStyle: CharakText.h1.copyWith(color: CharakColors.border),
              errorText: _error,
              border: const UnderlineInputBorder(),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: CharakColors.border)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: CharakColors.primary, width: 2)),
              filled: false,
            ),
          ),
          const Spacer(),
          ValueListenableBuilder(
            valueListenable: _ctrl,
            builder: (_, __, ___) => CharakButton(
              label: 'Get OTP',
              isLoading: _loading,
              onPressed: _valid ? _send : null,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('By continuing you agree to our Terms & Privacy Policy',
                style: CharakText.micro.copyWith(color: CharakColors.inkMuted),
                textAlign: TextAlign.center),
          ),
        ]),
      ),
    ),
  );
}

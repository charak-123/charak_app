import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => _ctrl.text.trim().length == 10;

  Future<void> _submit() async {
    final phone = '+91${_ctrl.text.trim()}';
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).sendOtp(phone, 'doctor');
      if (mounted) context.push('/auth/otp', extra: phone);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: CharakSpacing.xl),
              Text('Enter your phone number', style: CharakText.h1.copyWith(color: CharakColors.ink)),
              const SizedBox(height: CharakSpacing.sm),
              Text('We\'ll send a verification code to your phone.', style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.lg),
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                decoration: InputDecoration(
                  hintText: '10-digit mobile number',
                  prefixText: '+91  ',
                  prefixStyle: CharakText.body.copyWith(color: CharakColors.ink),
                  errorText: _error,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) { if (_valid) _submit(); },
              ),
              const Spacer(),
              CharakButton(
                label: 'Continue',
                onPressed: _valid ? _submit : null,
                isLoading: _loading,
              ),
              const SizedBox(height: CharakSpacing.base),
            ],
          ),
        ),
      ),
    );
  }
}

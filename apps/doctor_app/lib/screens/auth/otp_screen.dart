import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _ctrl = TextEditingController();
  bool _loading  = false;
  String? _error;
  int _resendSecs = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendSecs = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSecs == 0) { t.cancel(); return; }
      setState(() => _resendSecs--);
    });
  }

  Future<void> _resend() async {
    try {
      await ref.read(authProvider.notifier).sendOtp(widget.phone, 'doctor');
      _startCountdown();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _verify(String code) async {
    setState(() { _loading = true; _error = null; });
    try {
      final isNew = await ref.read(authProvider.notifier).verifyOtp(widget.phone, code, 'doctor');
      if (!mounted) return;
      context.go(isNew ? '/onboarding/profile' : '/');
    } on ApiException catch (e) {
      setState(() { _error = e.message; _ctrl.clear(); });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 52, height: 56,
      textStyle: CharakText.h1.copyWith(color: CharakColors.ink),
      decoration: BoxDecoration(
        color: CharakColors.bgSubtle,
        borderRadius: BorderRadius.all(CharakRadius.button),
        border: Border.all(color: CharakColors.border),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Verify phone')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: CharakSpacing.lg),
              Text('Enter the 6-digit code sent to\n${widget.phone}',
                  style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.lg),
              Center(
                child: Pinput(
                  controller: _ctrl,
                  length: 6,
                  autofocus: true,
                  defaultTheme: defaultPinTheme,
                  focusedPinTheme: defaultPinTheme.copyWith(
                    decoration: defaultPinTheme.decoration!.copyWith(
                      border: Border.all(color: CharakColors.primary, width: 1.5),
                    ),
                  ),
                  errorPinTheme: defaultPinTheme.copyWith(
                    decoration: defaultPinTheme.decoration!.copyWith(
                      border: Border.all(color: CharakColors.danger),
                    ),
                  ),
                  onCompleted: _loading ? null : _verify,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: CharakSpacing.sm),
                Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
              ],
              const SizedBox(height: CharakSpacing.lg),
              Center(
                child: _resendSecs > 0
                    ? Text('Resend in 0:${_resendSecs.toString().padLeft(2, '0')}',
                        style: CharakText.caption.copyWith(color: CharakColors.inkMuted))
                    : GestureDetector(
                        onTap: _resend,
                        child: Text('Resend OTP',
                            style: CharakText.caption.copyWith(color: CharakColors.primary,
                                decoration: TextDecoration.underline)),
                      ),
              ),
              const Spacer(),
              if (_loading) const Center(child: CircularProgressIndicator()),
              const SizedBox(height: CharakSpacing.base),
            ],
          ),
        ),
      ),
    );
  }
}

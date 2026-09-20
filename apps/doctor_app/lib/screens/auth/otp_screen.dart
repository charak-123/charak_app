import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:charak_core/charak_core.dart';

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
    // `.otp-cell` — 46×54, 1px border on the control radius, 22px/600.
    final defaultPinTheme = PinTheme(
      width: 46,
      height: 54,
      textStyle: const TextStyle(
        fontFamily: CharakText.fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: CharakColors.ink,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.button),
        border: Border.all(color: CharakColors.border),
      ),
    );

    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Enter the code', style: CharakText.h1),
                    const SizedBox(height: 5),
                    Text('Sent to ${widget.phone}',
                        style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted)),
                    // `.otp-row` — margin: 26px 0 14px, 10px gap, centred.
                    const SizedBox(height: 26),
                    Center(
                      child: Pinput(
                        controller: _ctrl,
                        length: 6,
                        autofocus: true,
                        separatorBuilder: (_) => const SizedBox(width: 10),
                        defaultPinTheme: defaultPinTheme,
                        focusedPinTheme: defaultPinTheme.copyWith(
                          decoration: defaultPinTheme.decoration!.copyWith(
                            border: Border.all(color: CharakColors.primary),
                            // `.otp-cell:focus` ring.
                            boxShadow: const [
                              BoxShadow(color: Color(0x1F376CD5), blurRadius: 0, spreadRadius: 3),
                            ],
                          ),
                        ),
                        errorPinTheme: defaultPinTheme.copyWith(
                          decoration: defaultPinTheme.decoration!.copyWith(
                            border: Border.all(color: CharakColors.danger),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onCompleted: _loading ? null : _verify,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // `.countdown` — centred 13px muted, ink/600 tabular value.
                    Center(
                      child: _resendSecs > 0
                          ? Text.rich(
                              TextSpan(
                                style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                                children: [
                                  const TextSpan(text: 'Resend code in '),
                                  TextSpan(
                                    text: '0:${_resendSecs.toString().padLeft(2, '0')}',
                                    style: CharakText.caption.copyWith(
                                      color: CharakColors.ink,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : GestureDetector(
                              onTap: _resend,
                              child: Text('Resend code',
                                  style: CharakText.caption.copyWith(
                                      color: CharakColors.primary, fontWeight: FontWeight.w600)),
                            ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Text(_error!,
                            style: CharakText.caption.copyWith(color: CharakColors.danger)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            CharakCtaBar.single(
              CharakButton(
                label: 'Verify',
                isLoading: _loading,
                onPressed: _ctrl.text.length == 6 && !_loading ? () => _verify(_ctrl.text) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

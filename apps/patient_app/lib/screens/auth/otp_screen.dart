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
  ConsumerState<OtpScreen> createState() => _State();
}

class _State extends ConsumerState<OtpScreen> {
  final _ctrl     = TextEditingController();
  bool  _loading  = false;
  String? _error;
  int   _countdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown == 0) { t.cancel(); return; }
      if (mounted) setState(() => _countdown--);
    });
  }

  Future<void> _verify(String code) async {
    setState(() { _loading = true; _error = null; });
    try {
      final isNew = await ref.read(authProvider.notifier)
          .verifyOtp(widget.phone, code, 'patient');
      if (!mounted) return;
      if (isNew) {
        context.go('/auth/name');
      } else {
        context.go('/home');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authProvider.notifier).sendOtp(widget.phone, 'patient');
      _startTimer();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultTheme = PinTheme(
      width: 52, height: 60,
      textStyle: CharakText.h1,
      decoration: BoxDecoration(
        color: CharakColors.bgSubtle,
        borderRadius: BorderRadius.all(CharakRadius.button),
        border: Border.all(color: CharakColors.border),
      ),
    );
    return Scaffold(
      backgroundColor: CharakColors.bg,
      appBar: AppBar(backgroundColor: CharakColors.bg, elevation: 0,
          leading: BackButton(color: CharakColors.ink)),
      body: Padding(
        padding: const EdgeInsets.all(CharakSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Enter OTP', style: CharakText.display),
          const SizedBox(height: 8),
          Text('Sent to ${widget.phone}',
              style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
          const SizedBox(height: 40),
          Pinput(
            controller: _ctrl,
            length: 6,
            autofocus: true,
            defaultPinTheme: defaultTheme,
            focusedPinTheme: defaultTheme.copyDecorationWith(
              border: Border.all(color: CharakColors.primary, width: 2),
            ),
            errorPinTheme: defaultTheme.copyDecorationWith(
              border: Border.all(color: CharakColors.danger, width: 2),
            ),
            onCompleted: _loading ? null : _verify,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
          ],
          const SizedBox(height: 24),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading)
            Center(
              child: _countdown > 0
                  ? Text('Resend in ${_countdown}s',
                      style: CharakText.caption.copyWith(color: CharakColors.inkMuted))
                  : TextButton(
                      onPressed: _resend,
                      child: const Text('Resend OTP'),
                    ),
            ),
        ]),
      ),
    );
  }
}

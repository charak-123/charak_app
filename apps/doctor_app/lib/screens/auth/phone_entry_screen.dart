import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

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
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                // `.body` — 20px gutters; this screen adds `padding-top:26px`.
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your phone number', style: CharakText.h1),
                    const SizedBox(height: 5),
                    Text(
                      'Same OTP flow as patients — one identity per doctor.',
                      style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted),
                    ),
                    const SizedBox(height: 26),
                    // `.field` — 13px/600 label, 7px gap.
                    Text('Mobile number',
                        style: CharakText.caption.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 7),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // `.input` used as a static 92px country-code box.
                        Container(
                          width: 92,
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            border: Border.all(color: CharakColors.border),
                            borderRadius: const BorderRadius.all(CharakRadius.button),
                          ),
                          child: Text(
                            '+91',
                            style: CharakText.bodyMed.copyWith(color: CharakColors.inkMuted),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PhoneField(
                            controller: _ctrl,
                            error: _error,
                            onChanged: () => setState(() {}),
                            onSubmit: () { if (_valid) _submit(); },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            CharakCtaBar.single(
              CharakButton(
                label: 'Continue',
                onPressed: _valid ? _submit : null,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.input` — 50px tall, 1px border on the 10px control radius, 15px text,
/// focus ring in primary. Tabular figures so the digits don't jitter.
class _PhoneField extends StatefulWidget {
  final TextEditingController controller;
  final String? error;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  const _PhoneField({
    required this.controller,
    required this.error,
    required this.onChanged,
    required this.onSubmit,
  });

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    final focused = _focus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: CharakDurations.buttonPress,
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: CharakColors.bg,
            borderRadius: const BorderRadius.all(CharakRadius.button),
            border: Border.all(
              color: hasError
                  ? CharakColors.danger
                  : (focused ? CharakColors.primary : CharakColors.border),
            ),
            // `.input:focus` — 0 0 0 3px rgba(47,111,237,0.12)
            boxShadow: focused && !hasError
                ? const [BoxShadow(color: Color(0x1F376CD5), blurRadius: 0, spreadRadius: 3)]
                : null,
          ),
          alignment: Alignment.center,
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            autofocus: true,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            style: CharakText.body.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: '98200 11223',
              hintStyle: CharakText.body.copyWith(color: CharakColors.inkMuted),
            ),
            onChanged: (_) => widget.onChanged(),
            onSubmitted: (_) => widget.onSubmit(),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(widget.error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
        ],
      ],
    );
  }
}

import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});
  @override
  ConsumerState<OtpScreen> createState() => _State();
}

class _State extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _ctrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focuses = List.generate(6, (_) => FocusNode());
  bool  _loading  = false;
  String? _error;
  int   _countdown = 60;
  Timer? _timer;
  late final TapGestureRecognizer _changeTap =
      TapGestureRecognizer()..onTap = () => Navigator.of(context).maybePop();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final f in _focuses) {
      f.dispose();
    }
    _timer?.cancel();
    _changeTap.dispose();
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

  String get _code => _ctrls.map((c) => c.text).join();

  void _onDigitEntered(int index, String value) {
    if (value.isEmpty) {
      // Backspace on this cell — move to previous
      if (index > 0) {
        _focuses[index - 1].requestFocus();
        _ctrls[index - 1].clear();
      }
    } else if (value.length == 1 && index < 5) {
      _focuses[index + 1].requestFocus();
    }
    // Auto-verify when all 6 filled
    final code = _code;
    if (code.length == 6 && !_loading) {
      _verify(code);
    }
    setState(() {});
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
      setState(() { _error = e.message; _loading = false; });
      for (final c in _ctrls) {
        c.clear();
      }
      _focuses[0].requestFocus();
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
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
    // The mockup prints the number in full, prefix included.
    final displayPhone =
        widget.phone.startsWith('+91') ? widget.phone : '+91 ${widget.phone}';

    return Scaffold(
      backgroundColor: CharakColors.bg,
      appBar: AppBar(
        backgroundColor: CharakColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const BackButton(color: CharakColors.ink),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Enter the code', style: charakScreenTitleStyle),
              const SizedBox(height: 5),
              // `.screen-sub` with the inline "Change" link.
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Sent to $displayPhone · '),
                  TextSpan(
                    text: 'Change',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CharakColors.primary,
                    ),
                    recognizer: _changeTap,
                  ),
                ]),
                style: charakScreenSubStyle,
              ),

              // `.otp-row` — 26px above, 14px below, 10px gaps, centred.
              Padding(
                padding: const EdgeInsets.only(top: 26, bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 6; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      _OtpCell(
                        controller: _ctrls[i],
                        focusNode: _focuses[i],
                        hasError: _error != null,
                        autofocus: i == 0,
                        onChanged: (v) => _onDigitEntered(i, v),
                      ),
                    ],
                  ],
                ),
              ),

              if (_error != null)
                Center(
                  child: Text(_error!,
                      style: CharakText.caption.copyWith(color: CharakColors.danger)),
                )
              else if (_loading)
                const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Center(
                  // `.countdown` — muted line, the clock itself 600 + tabular.
                  child: _countdown > 0
                      ? Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Resend code in '),
                            TextSpan(
                              text:
                                  '${_countdown ~/ 60}:${(_countdown % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: CharakColors.ink,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ]),
                          style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                        )
                      : GestureDetector(
                          onTap: _resend,
                          child: Text(
                            'Resend code',
                            style: CharakText.caption.copyWith(
                              color: CharakColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
            ]),
          ),
        ),
        CharakCtaBar.single(
          CharakButton(
            label: 'Verify',
            isLoading: _loading,
            onPressed: _code.length == 6 ? () => _verify(_code) : null,
          ),
        ),
      ]),
    );
  }
}

/// `.otp-cell` — 46×54 box, 22px/600 centred digit, primary border plus the
/// 3px `rgba(47,111,237,0.12)` ring while focused.
class _OtpCell extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final bool autofocus;
  final ValueChanged<String> onChanged;

  const _OtpCell({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.autofocus,
    required this.onChanged,
  });

  @override
  State<_OtpCell> createState() => _OtpCellState();
}

class _OtpCellState extends State<_OtpCell> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_sync);
  }

  void _sync() {
    if (widget.focusNode.hasFocus != _focused) {
      setState(() => _focused = widget.focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edge = widget.hasError
        ? CharakColors.danger
        : (_focused ? CharakColors.primary : CharakColors.border);
    return AnimatedContainer(
      duration: CharakDurations.buttonPress,
      width: 46,
      height: 54,
      decoration: BoxDecoration(
        color: CharakColors.bg,
        border: Border.all(color: edge),
        borderRadius: const BorderRadius.all(CharakRadius.button),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: (widget.hasError ? CharakColors.danger : CharakColors.primary)
                      .withValues(alpha: 0.12),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        cursorColor: CharakColors.primary,
        style: const TextStyle(
          fontFamily: CharakText.fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: CharakColors.ink,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        decoration: const InputDecoration(
          counterText: '',
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

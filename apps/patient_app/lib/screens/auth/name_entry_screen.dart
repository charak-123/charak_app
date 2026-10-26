import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

/// The Terms and Privacy versions this new patient still has to accept.
final _requiredDocsProvider = FutureProvider.autoDispose(
    (ref) async => (await CharakLegal.status()).missing);

class NameEntryScreen extends ConsumerStatefulWidget {
  const NameEntryScreen({super.key});
  @override
  ConsumerState<NameEntryScreen> createState() => _State();
}

class _State extends ConsumerState<NameEntryScreen> {
  final _ctrl      = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool  _loading = false;
  bool  _consented = false;
  String? _error;
  String? _phoneError;

  // An account that signed in by OTP already has a verified number.
  late final bool _needsPhone =
      (ref.read(authProvider).user?['phone'] as String?)?.isNotEmpty != true;

  @override
  void dispose() { _ctrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

  List<CharakLegalDocument>? get _docs => ref.read(_requiredDocsProvider).valueOrNull;

  bool get _valid =>
      _ctrl.text.trim().length >= 2 &&
      (!_needsPhone || _phoneCtrl.text.length == 10) &&
      _docs != null &&
      (_docs!.isEmpty || _consented);

  Future<void> _save() async {
    setState(() { _loading = true; _error = null; _phoneError = null; });
    try {
      await ref.read(authProvider.notifier).updateProfile(
        name: _ctrl.text.trim(),
        phone: _needsPhone ? '+91${_phoneCtrl.text}' : null,
      );
      // The boxes the patient just ticked, recorded against the exact versions
      // shown (append-only, DPDP accountability). Not best-effort: without the
      // record there is no consent, so a failure stops here with a message.
      final docs = _docs ?? const [];
      if (docs.isNotEmpty) await CharakLegal.accept(docs, method: 'signup_checkbox');
      if (mounted) context.go('/home');
    } on ApiException catch (e) {
      setState(() {
        if (e.statusCode == 409) {
          _phoneError = e.message;     // number already on another account
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.ground,
    body: SafeArea(
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('What should we call you?', style: charakScreenTitleStyle),
              const SizedBox(height: 5),
              Text('This is how doctors will see you.', style: charakScreenSubStyle),
              const SizedBox(height: 26),
              CharakField(
                label: 'Full name',
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                placeholder: 'Your full name',
                error: _error,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) { if (_valid) _save(); },
              ),
              if (_needsPhone) ...[
                const SizedBox(height: 18),
                CharakField(
                  label: 'Mobile number',
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  tabular: true,
                  placeholder: '98765 43210',
                  error: _phoneError,
                  hint: 'Your doctor uses this to reach you about a visit.',
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  prefixBox: CharakField.staticBox('+91'),
                  onChanged: (_) => setState(() => _phoneError = null),
                  onSubmitted: (_) { if (_valid) _save(); },
                ),
              ],
              const SizedBox(height: 22),
              ref.watch(_requiredDocsProvider).when(
                loading: () => const CharakSkeleton(height: 96, radius: 20),
                error: (e, _) => CharakErrorState(
                  error: e,
                  onRetry: () => ref.invalidate(_requiredDocsProvider),
                ),
                data: (docs) => docs.isEmpty
                    ? const SizedBox.shrink()
                    : CharakConsentChecklist(
                        documents: docs,
                        onAllChecked: (v) => setState(() => _consented = v),
                      ),
              ),
            ]),
          ),
        ),
        CharakCtaBar.single(
          ListenableBuilder(
            // _consented and the documents arrive through setState / the
            // provider, which rebuild this screen anyway.
            listenable: Listenable.merge([_ctrl, _phoneCtrl]),
            builder: (_, __) => CharakButton(
              label: 'Continue',
              isLoading: _loading,
              onPressed: _valid ? _save : null,
            ),
          ),
        ),
      ]),
    ),
  );
}

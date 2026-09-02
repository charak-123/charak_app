import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

class NameEntryScreen extends ConsumerStatefulWidget {
  const NameEntryScreen({super.key});
  @override
  ConsumerState<NameEntryScreen> createState() => _State();
}

class _State extends ConsumerState<NameEntryScreen> {
  final _ctrl    = TextEditingController();
  bool  _loading = false;
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  bool get _valid => _ctrl.text.trim().length >= 2;

  Future<void> _save() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).updateName(_ctrl.text.trim());
      if (mounted) context.go('/home');
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
          Text('What should we\ncall you?', style: CharakText.display),
          const SizedBox(height: 32),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: CharakText.h1,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) { if (_valid) _save(); },
            decoration: InputDecoration(
              hintText: 'Your name',
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
              label: 'Continue',
              isLoading: _loading,
              onPressed: _valid ? _save : null,
            ),
          ),
        ]),
      ),
    ),
  );
}

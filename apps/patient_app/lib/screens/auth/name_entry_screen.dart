import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

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
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('What should we call you?', style: charakScreenTitleStyle),
              const SizedBox(height: 5),
              const Text('This is how doctors will see you.', style: charakScreenSubStyle),
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
            ]),
          ),
        ),
        CharakCtaBar.single(
          ValueListenableBuilder(
            valueListenable: _ctrl,
            builder: (_, __, ___) => CharakButton(
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

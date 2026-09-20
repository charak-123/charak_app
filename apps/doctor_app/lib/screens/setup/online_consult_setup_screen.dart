import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'schedule_editor.dart';

class OnlineConsultSetupScreen extends ConsumerStatefulWidget {
  const OnlineConsultSetupScreen({super.key});

  @override
  ConsumerState<OnlineConsultSetupScreen> createState() => _OnlineConsultSetupScreenState();
}

class _OnlineConsultSetupScreenState extends ConsumerState<OnlineConsultSetupScreen> {
  List<ScheduleBlock> _blocks = [];
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_blocks.isEmpty) {
      setState(() => _error = 'Add at least one time block');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.instance.put('/schedules/me', _blocks.map((b) => b.toJson()).toList());
      if (!mounted) return;
      // Check if home visit is also selected
      final me = await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
      if (!mounted) return;
      if (me['offers_home_visit'] == true) {
        context.go('/setup/home-visit', extra: true);
      } else {
        context.go('/setup/pricing');
      }
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
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Online consult hours', style: CharakText.h1),
                    const SizedBox(height: 5),
                    Text('Weekly template — patients book into these slots.',
                        style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted)),
                    const SizedBox(height: 18),
                    ScheduleEditor(
                      blocks: _blocks,
                      onChanged: (b) => setState(() => _blocks = b),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: CharakSpacing.md),
                      Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
                    ],
                  ],
                ),
              ),
            ),
            CharakCtaBar.single(
              CharakButton(
                label: 'Continue',
                onPressed: _submit,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

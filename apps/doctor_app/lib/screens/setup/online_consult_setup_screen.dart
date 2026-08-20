import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'schedule_editor.dart';
import '../shared/charak_button.dart';

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
      appBar: AppBar(title: const Text('Online Consult Schedule')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set when you\'re available for video calls. Patients book into these time slots.',
                  style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.sm),
              Text('Scheduled slots only in V1 — "Available now" mode is not yet available.',
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.lg),
              ScheduleEditor(
                blocks: _blocks,
                onChanged: (b) => setState(() => _blocks = b),
              ),
              if (_error != null) ...[
                const SizedBox(height: CharakSpacing.sm),
                Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
              ],
              const SizedBox(height: CharakSpacing.lg),
              CharakButton(
                label: 'Continue',
                onPressed: _submit,
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

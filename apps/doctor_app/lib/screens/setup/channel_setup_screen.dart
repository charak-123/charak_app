import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class ChannelSetupScreen extends ConsumerStatefulWidget {
  const ChannelSetupScreen({super.key});

  @override
  ConsumerState<ChannelSetupScreen> createState() => _ChannelSetupScreenState();
}

class _ChannelSetupScreenState extends ConsumerState<ChannelSetupScreen> {
  bool _online = false;
  bool _home   = false;
  bool _touched = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Opens on the channels already chosen, not two blank switches.
  Future<void> _load() async {
    try {
      final me = await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
      // A switch flipped while this loaded is the doctor's answer; keep it.
      if (!mounted || _touched) return;
      setState(() {
        _online = me['offers_online_consult'] as bool? ?? false;
        _home = me['offers_home_visit'] as bool? ?? false;
      });
    } catch (_) {
      // Blank switches are a usable fallback: the doctor sets them anyway.
    }
  }

  Future<void> _submit() async {
    if (!_online && !_home) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one channel')),
      );
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.instance.patch('/doctors/me', {
        'offers_online_consult': _online,
        'offers_home_visit': _home,
      });
      if (!mounted) return;
      if (_online) {
        context.go('/setup/online', extra: true);
      } else {
        context.go('/setup/home-visit', extra: true);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CharakScreen(
      // This screen also serves as a settings re-edit, pushed from the
      // profile tab — without a back affordance there is no way off it on
      // iOS, which has no hardware back button. Blank title: the screen
      // already carries its own big title below.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CharakStepDots(current: 2),
                    const SizedBox(height: 10),
                    const Text('How do you practice?', style: CharakText.titleLarge),
                    const SizedBox(height: 5),
                    Text('Pick one or both. A cardiologist can simply skip Home Visit.',
                        style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted)),
                    const SizedBox(height: 18),
                    CharakToggleCard(
                      icon: LucideIcons.video,
                      title: 'Online consult',
                      subtitle: 'Video consults on your scheduled hours.',
                      value: _online,
                      onChanged: (v) => setState(() { _touched = true; _online = v; }),
                    ),
                    CharakToggleCard(
                      icon: LucideIcons.house,
                      title: 'Home visit',
                      subtitle: 'You travel to the patient, within your radius.',
                      value: _home,
                      onChanged: (v) => setState(() { _touched = true; _home = v; }),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: CharakSpacing.base),
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

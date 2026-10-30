import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'schedule_editor.dart';

class OnlineConsultSetupScreen extends ConsumerStatefulWidget {
  /// True inside first-time setup, which continues to the next step; false
  /// when opened from Profile, which saves and goes back.
  final bool fromSetup;
  const OnlineConsultSetupScreen({super.key, this.fromSetup = false});

  @override
  ConsumerState<OnlineConsultSetupScreen> createState() => _OnlineConsultSetupScreenState();
}

class _OnlineConsultSetupScreenState extends ConsumerState<OnlineConsultSetupScreen> {
  List<ScheduleBlock> _blocks = [];
  bool _loaded = false;
  Object? _loadError;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The hours already saved. The editor used to open on an empty week, so a
  /// doctor changing one block had to re-enter all of them, and saving wiped
  /// whatever they didn't.
  Future<void> _load() async {
    setState(() { _loadError = null; _loaded = false; });
    try {
      final blocks = await loadScheduleBlocks('online_consult');
      if (mounted) setState(() { _blocks = blocks; _loaded = true; });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _submit() async {
    if (_blocks.isEmpty) {
      setState(() => _error = 'Add at least one time block');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.instance.put('/schedules/me', _blocks.map((b) => b.toJson()).toList());
      if (!mounted) return;
      if (!widget.fromSetup) {
        showCharakToast(context, message: 'Online hours saved');
        context.pop(true);
        return;
      }
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
    return CharakScreen(
      // This screen also serves as a settings re-edit, pushed from the
      // profile tab — without a back affordance there is no way off it on
      // iOS, which has no hardware back button. Blank title: the screen
      // already carries its own big title below.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loadError != null
                  ? CharakErrorState(error: _loadError!, onRetry: _load)
                  : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Online consult hours', style: CharakText.titleLarge),
                    const SizedBox(height: 5),
                    Text('Weekly template — patients book into these slots. Tap a time to change it.',
                        style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted)),
                    const SizedBox(height: 18),
                    if (!_loaded)
                      const CharakSkeletonList(count: 4, avatar: false, padding: EdgeInsets.zero)
                    else
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
                label: widget.fromSetup ? 'Continue' : 'Save hours',
                // Never save over hours that didn't load: that would erase them.
                onPressed: _loaded ? _submit : null,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

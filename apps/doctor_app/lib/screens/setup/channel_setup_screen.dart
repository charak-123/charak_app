import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

class ChannelSetupScreen extends ConsumerStatefulWidget {
  const ChannelSetupScreen({super.key});

  @override
  ConsumerState<ChannelSetupScreen> createState() => _ChannelSetupScreenState();
}

class _ChannelSetupScreenState extends ConsumerState<ChannelSetupScreen> {
  bool _online = false;
  bool _home   = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.instance.patch('/doctors/me', {
        'offers_online_consult': _online,
        'offers_home_visit': _home,
      });
      if (!mounted) return;
      if (_online) context.go('/setup/online');
      else context.go('/setup/home-visit', extra: true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How do you want to serve patients?')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Column(
            children: [
              const SizedBox(height: CharakSpacing.lg),
              _ChannelCard(
                icon: Icons.videocam_outlined,
                title: 'Online Consult',
                subtitle: 'Video appointments at scheduled times',
                selected: _online,
                onTap: () => setState(() => _online = !_online),
              ),
              const SizedBox(height: CharakSpacing.md),
              _ChannelCard(
                icon: Icons.home_outlined,
                title: 'Home Visit',
                subtitle: 'Travel to patient\'s home within your service radius',
                selected: _home,
                onTap: () => setState(() => _home = !_home),
              ),
              if (_error != null) ...[
                const SizedBox(height: CharakSpacing.base),
                Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
              ],
              const Spacer(),
              CharakButton(
                label: 'Continue',
                onPressed: (_online || _home) ? _submit : null,
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

class _ChannelCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.icon, required this.title, required this.subtitle,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(CharakSpacing.base),
        decoration: BoxDecoration(
          color: selected ? CharakColors.primarySoft : CharakColors.bg,
          borderRadius: BorderRadius.all(CharakRadius.card),
          border: Border.all(color: selected ? CharakColors.primary : CharakColors.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: selected ? CharakColors.primary : CharakColors.bgSubtle,
                borderRadius: BorderRadius.all(CharakRadius.button),
              ),
              child: Icon(icon, color: selected ? Colors.white : CharakColors.inkMuted, size: 24),
            ),
            const SizedBox(width: CharakSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: CharakText.bodyMed.copyWith(color: CharakColors.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: selected ? CharakColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? CharakColors.primary : CharakColors.border),
              ),
              child: selected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
            ),
          ],
        ),
      ),
    );
  }
}

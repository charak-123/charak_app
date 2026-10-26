import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:charak_core/charak_core.dart';
import 'requests_tab.dart';
import 'schedule_tab.dart';
import 'earnings_tab.dart';
import 'profile_tab.dart';
import 'shell_providers.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _idx = 0;

  static const _tabs = [
    RequestsTab(),
    ScheduleTab(),
    EarningsTab(),
    ProfileTab(),
  ];

  static const _items = [
    CharakNavItem(label: 'Requests', icon: LucideIcons.inbox, activeIcon: LucideIcons.inbox),
    CharakNavItem(label: 'Schedule', icon: LucideIcons.calendarDays, activeIcon: LucideIcons.calendarDays),
    CharakNavItem(label: 'Earnings', icon: LucideIcons.wallet, activeIcon: LucideIcons.wallet),
    CharakNavItem(label: 'Profile', icon: LucideIcons.user, activeIcon: LucideIcons.user),
  ];

  @override
  void initState() {
    super.initState();
    _idx = ref.read(doctorTabIndexProvider);
    // A material update to the Terms or Privacy Policy is asked for here, once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) charakAskForMissingConsent(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(doctorTabIndexProvider, (prev, next) {
      if (next != _idx) setState(() => _idx = next);
    });
    return Scaffold(
      // Tab switch: the new tab rises and fades in (motion.standard).
      body: IndexedStack(
        index: _idx,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            CharakTabTransition(index: i, tabIndex: _idx, child: _tabs[i]),
        ],
      ),
      backgroundColor: CharakColors.ground,
      // Ink bottom bar: the doctor app runs on CharakScheme.doctor.
      bottomNavigationBar: CharakBottomBar(
        currentIndex: _idx,
        onTap: (i) {
          setState(() => _idx = i);
          ref.read(doctorTabIndexProvider.notifier).state = i;
        },
        items: _items,
      ),
    );
  }
}

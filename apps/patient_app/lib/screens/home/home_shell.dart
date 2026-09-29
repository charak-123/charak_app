import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:charak_core/charak_core.dart';
import 'home_tab.dart';
import 'bookings_tab.dart';
import 'history_tab.dart';
import 'profile_tab.dart';
import 'booking_providers.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _State();
}

class _State extends ConsumerState<HomeShell> {
  int _tab = 0;

  static const _tabs = [HomeTab(), BookingsTab(), HistoryTab(), ProfileTab()];

  static const _navItems = [
    CharakNavItem(label: 'Home',     icon: Icons.home_outlined,           activeIcon: Icons.home_rounded),
    CharakNavItem(label: 'Bookings', icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month_rounded),
    CharakNavItem(label: 'History',  icon: Icons.history_rounded),
    CharakNavItem(label: 'Profile',  icon: Icons.person_outline_rounded,  activeIcon: Icons.person_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tab = ref.read(homeTabIndexProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(homeTabIndexProvider, (prev, next) {
      if (next != _tab) setState(() => _tab = next);
    });
    return Scaffold(
      // Tab switch: the new tab rises and fades in (motion.standard).
      body: IndexedStack(
        index: _tab,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            CharakTabTransition(index: i, tabIndex: _tab, child: _tabs[i]),
        ],
      ),
      backgroundColor: CharakColors.ground,
      bottomNavigationBar: CharakBottomBar(
        currentIndex: _tab,
        items: _navItems,
        onTap: (i) {
          setState(() => _tab = i);
          ref.read(homeTabIndexProvider.notifier).state = i;
        },
      ),
    );
  }
}

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
    _NavItem(label: 'Home',     activeIcon: Icons.home_rounded,           inactiveIcon: Icons.home_outlined),
    _NavItem(label: 'Bookings', activeIcon: Icons.calendar_month_rounded,  inactiveIcon: Icons.calendar_month_outlined),
    _NavItem(label: 'History',  activeIcon: Icons.history_rounded,         inactiveIcon: Icons.history_rounded),
    _NavItem(label: 'Profile',  activeIcon: Icons.person_rounded,          inactiveIcon: Icons.person_outline_rounded),
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
      // `.scr.tab-in` — each tab rises 8px and fades as it becomes visible.
      body: IndexedStack(
        index: _tab,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            CharakTabTransition(index: i, tabIndex: _tab, child: _tabs[i]),
        ],
      ),
      bottomNavigationBar: _CharakTabBar(
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

class _NavItem {
  final String label;
  final IconData activeIcon;
  final IconData inactiveIcon;
  const _NavItem({
    required this.label,
    required this.activeIcon,
    required this.inactiveIcon,
  });
}

class _CharakTabBar extends StatelessWidget {
  final int currentIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onTap;

  const _CharakTabBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: CharakColors.bg,
        border: Border(top: BorderSide(color: CharakColors.border, width: 1)),
      ),
      child: SizedBox(
        // `.tabbar` — 56px items over a 4px bottom pad, plus the safe inset.
        height: 60 + bottomPad,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPad + 4),
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final isActive = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isActive ? item.activeIcon : item.inactiveIcon,
                        size: 21,
                        color: isActive ? CharakColors.primary : CharakColors.inkMuted,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isActive ? CharakColors.primary : CharakColors.inkMuted,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

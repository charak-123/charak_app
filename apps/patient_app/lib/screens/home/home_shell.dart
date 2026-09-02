import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'home_tab.dart';
import 'bookings_tab.dart';
import 'profile_tab.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _State();
}

class _State extends ConsumerState<HomeShell> {
  int _tab = 0;

  static const _tabs = [HomeTab(), BookingsTab(), ProfileTab()];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _tab, children: _tabs),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      backgroundColor: CharakColors.bg,
      indicatorColor: CharakColors.primarySoft,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home, color: CharakColors.primary),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_today_outlined),
          selectedIcon: Icon(Icons.calendar_today, color: CharakColors.primary),
          label: 'Bookings',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person, color: CharakColors.primary),
          label: 'Profile',
        ),
      ],
    ),
  );
}

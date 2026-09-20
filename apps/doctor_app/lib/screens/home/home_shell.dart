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
    (Icons.inbox_outlined, Icons.inbox_rounded, 'Requests'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Schedule'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Earnings'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _idx = ref.read(doctorTabIndexProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(doctorTabIndexProvider, (prev, next) {
      if (next != _idx) setState(() => _idx = next);
    });
    return Scaffold(
      // `.scr.tab-in` — each tab rises 8px and fades as it becomes visible.
      body: IndexedStack(
        index: _idx,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            CharakTabTransition(index: i, tabIndex: _idx, child: _tabs[i]),
        ],
      ),
      bottomNavigationBar: _DoctorTabBar(
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

/// Doctor App's dark shell tab bar — sibling, not twin, to the patient app's
/// white bar. Per SKILL.md: ink chrome for the doctor's work-tool identity.
class _DoctorTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> items;
  const _DoctorTabBar({required this.currentIndex, required this.onTap, required this.items});

  /// `.tabbar .tab-item` on the ink shell — rgba(235, 240, 250, 0.5).
  static const _inactive = Color(0x80EBF0FA);

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      color: CharakColors.ink,
      child: SizedBox(
        height: 56 + bottomPad,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPad),
          child: Row(
            children: List.generate(items.length, (i) {
              final (outline, filled, label) = items[i];
              final isActive = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isActive ? filled : outline,
                        size: 21,
                        color: isActive ? Colors.white : _inactive,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: CharakText.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : _inactive,
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

import 'package:charak_core/charak_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 2000);
}

/// The widget types rebuilt while [scroll] runs.
Future<Set<Type>> _rebuiltDuring(Future<void> Function() scroll) async {
  final rebuilt = <Type>{};
  debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget.runtimeType);
  try {
    await scroll();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rebuilt;
}

class _TickerProbe extends StatelessWidget {
  static final enabled = <int, bool>{};
  final int index;
  const _TickerProbe(this.index);

  @override
  Widget build(BuildContext context) {
    enabled[index] = TickerMode.valuesOf(context).enabled;
    return const SizedBox.expand();
  }
}

Future<void> _scrollTo(WidgetTester tester, double offset) async {
  tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(offset);
  await tester.pump();
}

bool _blurOn(WidgetTester tester) => tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled;

void main() {
  group('CharakLargeTitleScaffold', () {
    testWidgets('frosts the bar only once it folds in', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: CharakLargeTitleScaffold(title: 'Home', children: [_Probe()]),
      ));
      expect(_blurOn(tester), isFalse);
      await _scrollTo(tester, CharakMotion.headerFadeStart - 10);
      expect(_blurOn(tester), isFalse);
      await _scrollTo(tester, CharakMotion.headerFadeEnd);
      expect(_blurOn(tester), isTrue);
      await _scrollTo(tester, 0);
      expect(_blurOn(tester), isFalse);
    });

    testWidgets('scrolling rebuilds the header and bar, not the scroll view', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: CharakLargeTitleScaffold(title: 'Home', children: [_Probe()]),
      ));
      final rebuilt = await _rebuiltDuring(() async {
        for (final o in [40.0, 120.0, 200.0, 260.0, 600.0]) {
          await _scrollTo(tester, o);
        }
      });
      expect(rebuilt, contains(ValueListenableBuilder<double>));
      expect(rebuilt, isNot(contains(CustomScrollView)));
      expect(rebuilt, isNot(contains(CharakStaggerIn)));
      expect(rebuilt, isNot(contains(CharakRiseIn)));
    });
  });

  group('CharakScreen', () {
    testWidgets('frosts a titled bar only once it folds in', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: CharakScreen(title: 'Booking', body: SingleChildScrollView(child: _Probe())),
      ));
      expect(_blurOn(tester), isFalse);
      await _scrollTo(tester, 72);
      expect(_blurOn(tester), isTrue);
    });

    testWidgets('never blurs behind an untitled, solid bar', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: CharakScreen(body: SingleChildScrollView(child: _Probe())),
      ));
      await _scrollTo(tester, 300);
      expect(_blurOn(tester), isFalse);
    });

    testWidgets('scrolling rebuilds the header and bar, not the scroll view', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: CharakScreen(title: 'Booking', body: SingleChildScrollView(child: _Probe())),
      ));
      final rebuilt = await _rebuiltDuring(() async {
        for (final o in [10.0, 30.0, 50.0, 72.0]) {
          await _scrollTo(tester, o);
        }
      });
      expect(rebuilt, contains(ValueListenableBuilder<double>));
      expect(rebuilt, isNot(contains(NestedScrollView)));
    });
  });

  testWidgets('CharakTabTransition pauses the animations of hidden tabs', (tester) async {
    Widget shell(int tab) => MaterialApp(
          home: IndexedStack(index: tab, children: [
            for (var i = 0; i < 3; i++)
              CharakTabTransition(index: i, tabIndex: tab, child: _TickerProbe(i)),
          ]),
        );
    await tester.pumpWidget(shell(0));
    expect(_TickerProbe.enabled, {0: true, 1: false, 2: false});
    await tester.pumpWidget(shell(2));
    expect(_TickerProbe.enabled, {0: false, 1: false, 2: true});
  });
}

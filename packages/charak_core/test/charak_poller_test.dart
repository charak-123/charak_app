import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:charak_core/charak_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharakPoller', () {
    test('does not poll before the first interval elapses', () async {
      var calls = 0;
      final p = CharakPoller(
        interval: const Duration(milliseconds: 50),
        onPoll: () async {
          calls++;
          return false;
        },
      )..start();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 0, reason: 'callers load once themselves first');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(calls, 1);
      p.dispose();
    });

    test('stops for good once onPoll reports completion', () async {
      var calls = 0;
      final p = CharakPoller(
        interval: const Duration(milliseconds: 20),
        onPoll: () async {
          calls++;
          return true;
        },
      )..start();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(calls, 1, reason: 'a finished poll must not fire again');
      p.dispose();
    });

    test('backs off, so a long wait does not cost a fixed rate', () async {
      final gaps = <int>[];
      var last = DateTime.now();
      final p = CharakPoller(
        interval: const Duration(milliseconds: 30),
        backoffFactor: 2.0,
        maxInterval: const Duration(seconds: 1),
        onPoll: () async {
          final now = DateTime.now();
          gaps.add(now.difference(last).inMilliseconds);
          last = now;
          return false;
        },
      )..start();

      await Future<void>.delayed(const Duration(milliseconds: 400));
      p.dispose();

      expect(gaps.length, greaterThanOrEqualTo(3));
      // Each gap should be meaningfully longer than the one before it.
      expect(gaps[1], greaterThan(gaps[0]));
      expect(gaps[2], greaterThan(gaps[1]));
    });

    test('honours maxInterval rather than growing without bound', () async {
      final gaps = <int>[];
      var last = DateTime.now();
      final p = CharakPoller(
        interval: const Duration(milliseconds: 20),
        backoffFactor: 10.0,
        maxInterval: const Duration(milliseconds: 60),
        onPoll: () async {
          final now = DateTime.now();
          gaps.add(now.difference(last).inMilliseconds);
          last = now;
          return false;
        },
      )..start();

      await Future<void>.delayed(const Duration(milliseconds: 400));
      p.dispose();

      // 20ms then capped at 60ms, never 200ms.
      expect(gaps.skip(1).every((g) => g < 140), isTrue,
          reason: 'capped gaps were $gaps');
    });

    test('sleeps while the app is backgrounded and wakes on resume', () async {
      var calls = 0;
      final p = CharakPoller(
        interval: const Duration(milliseconds: 30),
        onPoll: () async {
          calls++;
          return false;
        },
      )..start();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final before = calls;
      expect(before, greaterThan(0));

      p.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(calls, before,
          reason: 'a backgrounded screen must not keep polling');

      p.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(calls, greaterThan(before),
          reason: 'resuming should ask immediately, not wait out the backoff');
      p.dispose();
    });

    test('a throwing poll backs off instead of stopping', () async {
      var calls = 0;
      final p = CharakPoller(
        interval: const Duration(milliseconds: 20),
        onPoll: () async {
          calls++;
          throw Exception('network down');
        },
      )..start();

      await Future<void>.delayed(const Duration(milliseconds: 200));
      p.dispose();

      expect(calls, greaterThan(1), reason: 'an error is not an answer');
    });

    test('does not stack requests when a poll outlives its interval', () async {
      var inFlight = 0;
      var maxConcurrent = 0;
      final p = CharakPoller(
        interval: const Duration(milliseconds: 10),
        onPoll: () async {
          inFlight++;
          maxConcurrent = maxConcurrent > inFlight ? maxConcurrent : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 60));
          inFlight--;
          return false;
        },
      )..start();

      await Future<void>.delayed(const Duration(milliseconds: 250));
      p.dispose();

      expect(maxConcurrent, 1);
    });

    test('stop() is idempotent, so dispose() after success is safe', () {
      final p = CharakPoller(onPoll: () async => true)..start();
      p.stop();
      expect(p.stop, returnsNormally);
      expect(p.dispose, returnsNormally);
    });
  });
}

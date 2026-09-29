import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A backing-off poll that sleeps while the app is in the background.
///
/// Every screen that polls is watching for something push already delivers
/// (`booking.accepted`, `payment.confirmed`, `doctor.verified`,
/// `booking.requested`). Polling is the safety net for a dropped or disabled
/// notification, not the primary signal — so it should be cheap, and it should
/// cost nothing at all while nobody is looking at the screen.
///
/// Two things a naive `Timer.periodic` gets wrong:
///
///  * **It keeps running in the background.** Flutter timers keep firing after
///    the app is backgrounded, until the OS eventually suspends the process.
///    A fixed 5s poll left on a backgrounded screen is a battery and mobile
///    data complaint, and the kind of thing Play flags as excessive background
///    activity.
///  * **It never slows down.** A patient waiting an hour for a doctor to
///    accept costs 720 requests at 5s. The first minute is worth polling
///    quickly; the fiftieth is not.
///
/// So this starts at [interval], multiplies the delay by [backoffFactor] after
/// each poll that changed nothing, caps at [maxInterval], and resets to
/// [interval] whenever the app returns to the foreground — the moment a user
/// is actually waiting on an answer again.
class CharakPoller with WidgetsBindingObserver {
  /// The work to do on each tick. Return true when the thing being waited for
  /// has happened; the poller stops and does not fire again.
  final Future<bool> Function() onPoll;

  final Duration interval;
  final Duration maxInterval;
  final double backoffFactor;

  Timer? _timer;
  Duration _current;
  bool _running = false;
  bool _inFlight = false;
  bool _disposed = false;

  CharakPoller({
    required this.onPoll,
    this.interval = const Duration(seconds: 5),
    this.maxInterval = const Duration(minutes: 2),
    this.backoffFactor = 1.6,
  }) : _current = interval;

  /// Begins polling and starts watching the app lifecycle.
  ///
  /// Does not poll immediately — callers normally load once themselves so the
  /// screen has data to paint before the first tick.
  void start() {
    if (_running || _disposed) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  /// Stops polling for good and releases the lifecycle observer. Idempotent,
  /// so a screen can call it from both a success path and dispose().
  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running) return;
    _timer = Timer(_current, _tick);
  }

  Future<void> _tick() async {
    if (!_running || _disposed) return;
    // A slow response must not stack requests behind it.
    if (_inFlight) {
      _schedule();
      return;
    }
    _inFlight = true;
    try {
      final done = await onPoll();
      if (done) {
        stop();
        return;
      }
      // Nothing changed — wait longer before asking again.
      final next = (_current.inMilliseconds * backoffFactor).round();
      _current = Duration(
        milliseconds: math.min(next, maxInterval.inMilliseconds),
      );
    } catch (_) {
      // A failed poll is not an answer. Back off the same way rather than
      // hammering a backend that may be the thing that is struggling.
      final next = (_current.inMilliseconds * backoffFactor).round();
      _current = Duration(
        milliseconds: math.min(next, maxInterval.inMilliseconds),
      );
    } finally {
      _inFlight = false;
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    if (state == AppLifecycleState.resumed) {
      // Someone is looking at this again: answer quickly, and ask now rather
      // than waiting out whatever delay the backoff had reached.
      _current = interval;
      _timer?.cancel();
      _timer = Timer(Duration.zero, _tick);
    } else {
      // paused / inactive / hidden / detached — stop entirely. Push is what
      // wakes a backgrounded app; a timer here only costs battery.
      _timer?.cancel();
      _timer = null;
    }
  }
}

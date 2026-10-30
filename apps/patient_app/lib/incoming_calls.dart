import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:charak_core/charak_core.dart';

/// Asks the backend whether a doctor is ringing, while the app is open.
///
/// Push (`call.incoming`) is how a call normally reaches the phone, but it
/// can be off: a backend without Firebase, notifications denied, a battery
/// saver holding messages back. A call that never reached the patient was
/// the "calling doesn't work" report, so this is the fallback. It asks every
/// [fast] while the patient has a booking a doctor could call about (the
/// backend says how many), every [slow] otherwise, and not at all in the
/// background, where only push can wake the app.
///
/// [onRinging] fires once per ring: a doctor who rings again (a new
/// `rang_at`) rings again here, but a ring the patient declined doesn't
/// come back on the next poll.
class IncomingCallWatcher with WidgetsBindingObserver {
  final void Function(Map<String, dynamic> call) onRinging;
  final Duration fast;
  final Duration slow;

  IncomingCallWatcher({
    required this.onRinging,
    this.fast = const Duration(seconds: 5),
    this.slow = const Duration(seconds: 30),
  });

  Timer? _timer;
  bool _running = false;
  bool _inFlight = false;
  String? _lastRing;

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _schedule(Duration.zero);
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Ask now: a request was just sent, or the app came back to the front.
  void pokeNow() {
    if (_running) _schedule(Duration.zero);
  }

  void _schedule(Duration after) {
    _timer?.cancel();
    if (_running) _timer = Timer(after, _tick);
  }

  Future<void> _tick() async {
    if (!_running || _inFlight) return;
    _inFlight = true;
    var next = slow;
    try {
      final res = await ApiClient.instance.get('/bookings/patient/ringing-call');
      if (res is Map) {
        if ((res['open_requests'] as num? ?? 0) > 0) next = fast;
        final call = res['call'];
        if (call is Map) {
          final ring = '${call['call_id']}@${call['rang_at']}';
          if (ring != _lastRing) {
            _lastRing = ring;
            onRinging(Map<String, dynamic>.from(call));
          }
        }
      }
    } catch (_) {
      // An older backend without the endpoint, or no network: try later.
    } finally {
      _inFlight = false;
    }
    _schedule(next);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    if (state == AppLifecycleState.resumed) {
      _schedule(Duration.zero);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }
}

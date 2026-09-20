import 'package:flutter/material.dart';

import 'tokens.dart';

/// Motion ported from `charak-shared/core.css`. The easing curves are the
/// stylesheet's `--ease-out` / `--ease-in-out` cubic-beziers, and every
/// duration comes from [CharakDurations].
///
/// This library stays router-agnostic: it exposes transition *builders* that
/// each app hands to its own `CustomTransitionPage`, so `charak_core` needs no
/// dependency on go_router.
class CharakCurves {
  CharakCurves._();

  /// `--ease-out: cubic-bezier(0.16, 1, 0.3, 1)` — the decelerating curve used
  /// for screen pushes, sheets and arrivals.
  static const out = Cubic(0.16, 1, 0.3, 1);

  /// `--ease-in-out: cubic-bezier(0.4, 0, 0.2, 1)`
  static const inOut = Cubic(0.4, 0, 0.2, 1);
}

/// True when the platform asks for reduced motion. Transitions then collapse
/// to a plain cross-fade instead of sliding.
bool charakReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The wireframe's screen-push transition, for use as a
/// `CustomTransitionPage.transitionsBuilder`.
///
/// The incoming screen slides in from the right (`.scr.entering` — translateX
/// 100%→0, opacity 0.4→1) while the outgoing one drifts left and dims
/// (`.scr.leaving` — 0→-28%, opacity 1→0.3). Running the same animation in
/// reverse yields `back-in`/`back-out`, so Back mirrors Forward exactly.
Widget charakPushTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (charakReduceMotion(context)) {
    return FadeTransition(opacity: animation, child: child);
  }

  final enter = CurvedAnimation(parent: animation, curve: CharakCurves.out);
  final leave = CurvedAnimation(parent: secondaryAnimation, curve: CharakCurves.out);

  return SlideTransition(
    position: Tween(begin: Offset.zero, end: const Offset(-0.28, 0)).animate(leave),
    child: FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.3).animate(leave),
      child: SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(enter),
        child: FadeTransition(
          opacity: Tween(begin: 0.4, end: 1.0).animate(enter),
          child: child,
        ),
      ),
    ),
  );
}

/// A rise-and-fade transition for full-screen surfaces that shouldn't slide
/// horizontally — call screens and success states.
Widget charakRiseTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final t = CurvedAnimation(parent: animation, curve: CharakCurves.out);
  if (charakReduceMotion(context)) {
    return FadeTransition(opacity: t, child: child);
  }
  return FadeTransition(
    opacity: t,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(t),
      child: child,
    ),
  );
}

/// `.scr.tab-in` — the 200ms rise applied when a tab-root screen becomes
/// visible. Wrap each tab body; it replays whenever [tabIndex] changes to
/// this tab's [index].
class CharakTabTransition extends StatefulWidget {
  final int index;
  final int tabIndex;
  final Widget child;

  const CharakTabTransition({
    super.key,
    required this.index,
    required this.tabIndex,
    required this.child,
  });

  @override
  State<CharakTabTransition> createState() => _CharakTabTransitionState();
}

class _CharakTabTransitionState extends State<CharakTabTransition>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.index == widget.tabIndex ? 1 : 0,
  );
  late final _t = CurvedAnimation(parent: _ctrl, curve: CharakCurves.out);

  @override
  void didUpdateWidget(CharakTabTransition old) {
    super.didUpdateWidget(old);
    if (widget.tabIndex == widget.index && old.tabIndex != widget.index) {
      _ctrl
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (charakReduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      builder: (_, child) => Opacity(
        opacity: _t.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 8 * (1 - _t.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// `.pulse` — flashes `primarySoft` behind its child and fades back to
/// transparent over 600ms whenever [trigger] changes. Used when a booking or
/// request status updates, so the row that changed announces itself.
///
/// It rests fully transparent and never pulses on first build.
class CharakStatusPulse extends StatefulWidget {
  /// Changing this value replays the pulse — pass the status string.
  final Object? trigger;
  final BorderRadius borderRadius;
  final Widget child;

  const CharakStatusPulse({
    super.key,
    required this.trigger,
    required this.child,
    this.borderRadius = const BorderRadius.all(CharakRadius.card),
  });

  @override
  State<CharakStatusPulse> createState() => _CharakStatusPulseState();
}

class _CharakStatusPulseState extends State<CharakStatusPulse>
    with SingleTickerProviderStateMixin {
  // Starts settled at 1 so a row that has never changed paints no tint.
  late final _ctrl = AnimationController(
    vsync: this,
    duration: CharakDurations.statusChange,
    value: 1,
  );

  @override
  void didUpdateWidget(CharakStatusPulse old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) {
      _ctrl
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (charakReduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: CharakColors.primarySoft
              .withValues(alpha: 1 - CharakCurves.out.transform(_ctrl.value)),
          borderRadius: widget.borderRadius,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// `.fade-swap` — cross-fades and lifts its child whenever the child's key
/// changes. Use for text that swaps in place, such as a status label.
class CharakFadeSwap extends StatelessWidget {
  final Widget child;

  const CharakFadeSwap({super.key, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: CharakDurations.statusChange,
    switchInCurve: CharakCurves.out,
    switchOutCurve: CharakCurves.out,
    transitionBuilder: (child, animation) {
      if (charakReduceMotion(context)) {
        return FadeTransition(opacity: animation, child: child);
      }
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
          child: child,
        ),
      );
    },
    child: child,
  );
}

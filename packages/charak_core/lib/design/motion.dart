import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Motion for CHARAK V2: quick out, soft landing (One UI style). Taps feel
/// instant and nothing jerks. Durations and curves come from the generated
/// [CharakMotion] tokens (`design-system/tokens.json` → `motion`).
///
/// Rules (design-system/README.md § Motion):
/// 1. One hero motion per screen; the rest stays quiet.
/// 2. Nothing longer than 450ms.
/// 3. Enter from where it lives: sheets rise, heads-up drops, lists lift 20px.
/// 4. Numbers never animate their value.
/// 5. With Reduce motion on, everything becomes a 150ms fade and loops stop.
///
/// This library stays router-agnostic: it exposes transition *builders* that
/// each app hands to its own `CustomTransitionPage`, so `charak_core` needs no
/// dependency on go_router.
abstract final class CharakCurves {
  /// motion.emphasized — enter, Now Bar, sheets, card → screen.
  static const emphasized = CharakMotion.emphasizedCurve;

  /// motion.standard — tabs, segments, status, colour.
  static const standard = CharakMotion.standardCurve;

  /// motion.exit — dismiss, heads-up out, close.
  static const exit = CharakMotion.exitCurve;

  /// motion.press — buttons, tiles, rows.
  static const press = CharakMotion.pressCurve;

  /// V1 alias for [emphasized].
  static const out = emphasized;

  /// V1 alias for [standard].
  static const inOut = standard;
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
    duration: CharakMotion.standard,
    value: widget.index == widget.tabIndex ? 1 : 0,
  );
  late final _t = CurvedAnimation(parent: _ctrl, curve: CharakCurves.standard);

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

/// Status change — cross-fades its child whenever the child's key changes
/// (motion.standard, 300ms, no slide). Use for text that swaps in place,
/// such as a status label.
class CharakFadeSwap extends StatelessWidget {
  final Widget child;

  const CharakFadeSwap({super.key, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: charakReduceMotion(context) ? CharakMotion.reduced : CharakMotion.standard,
    switchInCurve: CharakCurves.standard,
    switchOutCurve: CharakCurves.standard,
    child: child,
  );
}

/// motion.press — scales its child to 0.96 while held and springs back on
/// release (150ms, press curve). Wrap every tappable tile, card and row.
/// Buttons built on [CharakButton] already include it.
class CharakPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior behavior;

  const CharakPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<CharakPressable> createState() => _CharakPressableState();
}

class _CharakPressableState extends State<CharakPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final scale = (_down && enabled && !charakReduceMotion(context)) ? CharakMotion.pressScale : 1.0;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: AnimatedScale(
        scale: scale,
        duration: CharakMotion.press,
        curve: CharakCurves.press,
        child: widget.child,
      ),
    );
  }
}

/// motion.stagger — screen-enter choreography. Each child rises
/// [CharakMotion.liftOffset] px and fades in on the emphasized curve, 40ms
/// after the previous one. Only the first [CharakMotion.staggerMaxItems]
/// children stagger; the rest arrive with the last of them, so the tail never
/// exceeds 240ms.
class CharakStaggerIn extends StatefulWidget {
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  const CharakStaggerIn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  State<CharakStaggerIn> createState() => _CharakStaggerInState();
}

class _CharakStaggerInState extends State<CharakStaggerIn> with SingleTickerProviderStateMixin {
  static final _tailMs = CharakMotion.stagger.inMilliseconds * (CharakMotion.staggerMaxItems - 1);
  late final _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: CharakMotion.emphasized.inMilliseconds + _tailMs),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = charakReduceMotion(context);
    final total = _ctrl.duration!.inMilliseconds;
    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _item(i, total, reduce),
      ],
    );
  }

  Widget _item(int i, int total, bool reduce) {
    final start = CharakMotion.stagger.inMilliseconds * math.min(i, CharakMotion.staggerMaxItems - 1);
    final end = start + (reduce ? CharakMotion.reduced : CharakMotion.emphasized).inMilliseconds;
    final t = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start / total, math.min(1.0, end / total), curve: CharakCurves.emphasized),
    );
    return AnimatedBuilder(
      animation: t,
      builder: (_, child) => Opacity(
        opacity: t.value.clamp(0.0, 1.0),
        child: reduce
            ? child
            : Transform.translate(offset: Offset(0, CharakMotion.liftOffset * (1 - t.value)), child: child),
      ),
      child: widget.children[i],
    );
  }
}

/// motion.live — a looping 1.6s pulse for anything happening now (a live
/// consult dot, the Now Bar). Stops when Reduce motion is on.
class CharakLivePulse extends StatefulWidget {
  final Color color;
  final double size;

  const CharakLivePulse({super.key, required this.color, this.size = 8});

  @override
  State<CharakLivePulse> createState() => _CharakLivePulseState();
}

class _CharakLivePulseState extends State<CharakLivePulse> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: CharakMotion.live);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (charakReduceMotion(context)) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.5,
      height: s * 2.5,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final v = CharakCurves.standard.transform(_ctrl.value);
          return Stack(alignment: Alignment.center, children: [
            Container(
              width: s + (s * 1.5 * v),
              height: s + (s * 1.5 * v),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.35 * (1 - v)),
              ),
            ),
            Container(
              width: s,
              height: s,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
            ),
          ]);
        },
      ),
    );
  }
}

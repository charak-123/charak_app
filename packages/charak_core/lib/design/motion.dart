import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadScrollBehavior;

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
  final leave =
      CurvedAnimation(parent: secondaryAnimation, curve: CharakCurves.out);

  return SlideTransition(
    position:
        Tween(begin: Offset.zero, end: const Offset(-0.28, 0)).animate(leave),
    child: ScaleTransition(
      scale: Tween(begin: 1.0, end: 0.94).animate(leave),
      child: FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.3).animate(leave),
        child: SlideTransition(
          position:
              Tween(begin: const Offset(1, 0), end: Offset.zero).animate(enter),
          child: FadeTransition(
            opacity: Tween(begin: 0.4, end: 1.0).animate(enter),
            child: child,
          ),
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
      position:
          Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(t),
      child: child,
    ),
  );
}

/// Tab root: replays "Screen enter" (every [CharakRiseIn] cascades in again)
/// whenever [tabIndex] changes to this tab's [index].
///
/// Also pauses the tab's animations while another tab is showing. An
/// [IndexedStack] keeps hidden tabs alive with their tickers running, so a
/// looping pulse (a refund in progress, the Now Bar) or a loading skeleton on
/// a tab nobody can see kept the app drawing every frame.
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

class _CharakTabTransitionState extends State<CharakTabTransition> {
  int _generation = 0;

  @override
  void didUpdateWidget(CharakTabTransition old) {
    super.didUpdateWidget(old);
    // Shown again: replay "Screen enter" so the tab cascades in like a screen.
    if (widget.tabIndex == widget.index && old.tabIndex != widget.index) _generation++;
  }

  @override
  Widget build(BuildContext context) => TickerMode(
        enabled: widget.tabIndex == widget.index,
        child: CharakEntranceScope(generation: _generation, child: widget.child),
      );
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
        duration: charakReduceMotion(context)
            ? CharakMotion.reduced
            : CharakMotion.standard,
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
    if (_down == v) return;
    // A light tick as the finger lands, the way One UI answers a touch. Only
    // for things that actually do something.
    if (v) HapticFeedback.selectionClick();
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final scale = (_down && enabled && !charakReduceMotion(context))
        ? CharakMotion.pressScale
        : 1.0;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap == null
          ? null
          : () {
              CharakCardOrigin.recordFrom(context);
              widget.onTap!();
            },
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

/// motion.stagger — a column whose children each play "Screen enter"
/// ([CharakRiseIn]): they rise [CharakMotion.liftOffset] px and fade in on the
/// emphasized curve, cascading top to bottom.
class CharakStaggerIn extends StatelessWidget {
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  const CharakStaggerIn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Keyed by type so a skeleton swapped for the loaded card is a new
          // block, and rises in rather than appearing.
          for (var i = 0; i < children.length; i++)
            CharakRiseIn(
              key: ValueKey(Object.hash(i, children[i].runtimeType, children[i].key)),
              child: children[i],
            ),
        ],
      );
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

class _CharakLivePulseState extends State<CharakLivePulse>
    with SingleTickerProviderStateMixin {
  late final _ctrl =
      AnimationController(vsync: this, duration: CharakMotion.live);

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
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: widget.color),
            ),
          ]);
        },
      ),
    );
  }
}

/// Elastic overscroll on every scrollable, on every platform, with the Shad
/// scrollbars. Gives lists the rubber-band give One UI has instead of
/// Android's stretch/glow edge.
class CharakScrollBehavior extends ShadScrollBehavior {
  const CharakScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

// ───────────────────── card → screen ───────────────────────────────────────

/// Where the last tapped card sat on screen, so the screen it opens can grow
/// out of it (motion "Card → screen", emphasized 450ms).
///
/// [CharakPressable] records every tap. A route that wants the card transition
/// takes the rect with [take] when its page is built; a rect older than a
/// moment is ignored, so a stale tap never drives an unrelated navigation.
abstract final class CharakCardOrigin {
  static Rect? _rect;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static int _opening = 0;

  /// True while a card → screen transition is running. The page underneath
  /// reads it to stay still instead of sliding away.
  static bool get opening => _opening > 0;

  static void recordFrom(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    _rect = box.localToGlobal(Offset.zero) & box.size;
    _at = DateTime.now();
  }

  /// The rect of a tap made in the last 600ms, once.
  static Rect? take() {
    final r = _rect;
    _rect = null;
    if (r == null ||
        DateTime.now().difference(_at) > const Duration(milliseconds: 600)) {
      return null;
    }
    return r;
  }
}

/// A `transitionsBuilder` that grows the incoming screen out of [origin]: the
/// card's rect expands to the full screen while its corners straighten from
/// the card radius and the screen's content fades up inside it. Closing runs
/// the same motion back into the card. Without an origin (deep link, restored
/// route) or with Reduce motion on, it falls back to [charakPushTransition].
RouteTransitionsBuilder charakCardTransition(Rect? origin) {
  if (origin == null) return charakPushTransition;
  return (context, animation, secondaryAnimation, child) {
    if (charakReduceMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final t = CurvedAnimation(
      parent: animation,
      curve: CharakCurves.emphasized,
      reverseCurve: CharakCurves.emphasized.flipped,
    );
    return _CardGrow(origin: origin, animation: animation, t: t, child: child);
  };
}

class _CardGrow extends StatefulWidget {
  final Rect origin;
  final Animation<double> animation;
  final Animation<double> t;
  final Widget child;
  const _CardGrow(
      {required this.origin,
      required this.animation,
      required this.t,
      required this.child});

  @override
  State<_CardGrow> createState() => _CardGrowState();
}

class _CardGrowState extends State<_CardGrow> {
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_status);
    _status(widget.animation.status);
  }

  void _status(AnimationStatus s) {
    final running =
        s == AnimationStatus.forward || s == AnimationStatus.reverse;
    if (running && !_counted) {
      CharakCardOrigin._opening++;
      _counted = true;
    } else if (!running && _counted) {
      CharakCardOrigin._opening--;
      _counted = false;
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_status);
    if (_counted) CharakCardOrigin._opening--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final full = Offset.zero & size;
    return AnimatedBuilder(
      animation: widget.t,
      child: widget.child,
      builder: (context, child) {
        final v = widget.t.value;
        if (v >= 1) return child!;
        final rect = Rect.lerp(widget.origin, full, v)!;
        final radius = CharakRadii.card * (1 - v);
        // The screen is laid out at full size and scaled to the card's width,
        // so it reads as the card itself opening rather than a reveal.
        final scale = rect.width / size.width;
        // Content arrives once the card has visibly started to grow.
        final reveal = const Interval(0.1, 0.5).transform(v);
        return Stack(children: [
          Positioned.fromRect(
            rect: rect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: ColoredBox(
                color: CharakColors.ground,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: size.width,
                  maxWidth: size.width,
                  minHeight: size.height,
                  maxHeight: size.height,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topLeft,
                    child: Opacity(opacity: reveal, child: child),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

// ───────────────────── screen enter ────────────────────────────────────────

/// Marks when a screen (or a tab) entered, so [CharakRiseIn] blocks inside it
/// know to play the "Screen enter" motion. Each app wraps every route's page
/// in one; [CharakTabTransition] starts a fresh one each time its tab is
/// shown, which replays the entrance like opening the screen.
class CharakEntranceScope extends StatefulWidget {
  final Widget child;

  /// Bump to replay the entrance (a tab becoming visible again).
  final int generation;

  const CharakEntranceScope({super.key, required this.child, this.generation = 0});

  /// How long after a screen enters that newly built blocks still rise in.
  /// Long enough to cover content that arrives from the network.
  static const window = Duration(milliseconds: 2500);

  @override
  State<CharakEntranceScope> createState() => _CharakEntranceScopeState();
}

class _CharakEntranceScopeState extends State<CharakEntranceScope> {
  late DateTime _at = DateTime.now();

  @override
  void didUpdateWidget(CharakEntranceScope old) {
    super.didUpdateWidget(old);
    if (old.generation != widget.generation) _at = DateTime.now();
  }

  @override
  Widget build(BuildContext context) =>
      _EntranceData(at: _at, generation: widget.generation, child: widget.child);
}

class _EntranceData extends InheritedWidget {
  final DateTime at;
  final int generation;
  const _EntranceData({required this.at, required this.generation, required super.child});

  @override
  bool updateShouldNotify(_EntranceData old) => old.at != at;
}

/// "Screen enter · stagger": rises 20px and fades in on motion.emphasized.
/// The stagger comes from where the block sits — the higher on screen, the
/// sooner it moves — so a whole screen cascades top to bottom without anyone
/// counting indices, and content that arrives late from the server still
/// rises instead of popping in. Blocks built outside an entrance window (a
/// list scrolled later) appear as they are. Nested blocks don't double up:
/// only the outermost one moves.
class CharakRiseIn extends StatefulWidget {
  final Widget child;
  const CharakRiseIn({super.key, required this.child});

  /// Spread of the stagger from the top of the screen to the bottom. With
  /// 40ms per block on a phone this is the board's 6-block, 240ms tail.
  static const _spread = 260;

  @override
  State<CharakRiseIn> createState() => _CharakRiseInState();
}

class _RiseMarker extends InheritedWidget {
  const _RiseMarker({required super.child});
  @override
  bool updateShouldNotify(_RiseMarker old) => false;
}

class _CharakRiseInState extends State<CharakRiseIn> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: CharakMotion.emphasized, value: 1);
  DateTime? _seen;
  Timer? _timer;
  bool _nested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nested = context.getInheritedWidgetOfExactType<_RiseMarker>() != null;
    final scope = context.dependOnInheritedWidgetOfExactType<_EntranceData>();
    if (_nested || scope == null || scope.at == _seen) return;
    _seen = scope.at;
    if (DateTime.now().difference(scope.at) > CharakEntranceScope.window) return;
    final reduce = charakReduceMotion(context);
    _ctrl.duration = reduce ? CharakMotion.reduced : CharakMotion.emphasized;
    _ctrl.value = 0;
    _timer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      final h = MediaQuery.sizeOf(context).height;
      var delay = 0;
      if (box is RenderBox && box.hasSize && h > 0) {
        final y = box.localToGlobal(Offset.zero).dy;
        if (y > h) {
          _ctrl.value = 1; // below the fold: nothing to watch
          return;
        }
        delay = reduce ? 0 : (y.clamp(0.0, h) / h * CharakRiseIn._spread).round();
      }
      _timer = Timer(Duration(milliseconds: delay), () {
        if (mounted) _ctrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_nested) return widget.child;
    final reduce = charakReduceMotion(context);
    return _RiseMarker(
      child: AnimatedBuilder(
        animation: _ctrl,
        child: widget.child,
        builder: (_, child) {
          final v = reduce ? _ctrl.value : CharakCurves.emphasized.transform(_ctrl.value);
          if (v >= 1) return child!;
          return Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: reduce
                ? child
                : Transform.translate(offset: Offset(0, CharakMotion.liftOffset * (1 - v)), child: child),
          );
        },
      ),
    );
  }
}

/// The bottom action bar's entrance: it rises from the bottom edge 200ms after
/// the screen enters (the board's price sheet), once per screen.
class CharakBottomRise extends StatefulWidget {
  final Widget child;
  const CharakBottomRise({super.key, required this.child});

  @override
  State<CharakBottomRise> createState() => _CharakBottomRiseState();
}

class _CharakBottomRiseState extends State<CharakBottomRise> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: CharakMotion.emphasized, value: 1);
  Timer? _timer;
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    final scope = context.getInheritedWidgetOfExactType<_EntranceData>();
    if (scope == null || DateTime.now().difference(scope.at) > CharakEntranceScope.window) return;
    if (charakReduceMotion(context)) return;
    _ctrl.value = 0;
    _timer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        child: widget.child,
        builder: (_, child) {
          final v = CharakCurves.emphasized.transform(_ctrl.value);
          if (v >= 1) return child!;
          return FractionalTranslation(translation: Offset(0, 1 - v), child: child);
        },
      );
}

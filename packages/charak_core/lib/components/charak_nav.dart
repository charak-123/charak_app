import 'dart:async';

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

// ───────────────────────── switch ──────────────────────────────────────────

/// One UI switch: 52×32 pill track, white thumb that slides 20px on the
/// emphasized curve (300ms) while the track fades grey ↔ blue.
class CharakSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const CharakSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final reduce = charakReduceMotion(context);
    final d = reduce ? CharakMotion.reduced : CharakMotion.standard;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: d,
          curve: CharakCurves.standard,
          width: 52,
          height: 32,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: value ? CharakColors.primary : CharakColors.borderStrong,
            borderRadius: const BorderRadius.all(CharakRadius.pill),
          ),
          child: AnimatedAlign(
            duration: d,
            curve: CharakCurves.emphasized,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── bottom bar ──────────────────────────────────────

class CharakNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  /// Small count dot (e.g. waiting requests).
  final int badge;

  const CharakNavItem({required this.icon, required this.label, this.activeIcon, this.badge = 0});
}

/// Bottom bar. The active tab gets a 56×32 pill behind its icon that slides
/// between tabs (motion.standard). Patient: card bar, blue-100 pill, blue-700
/// ink. Doctor (ink scheme): ink bar, solid blue pill, white ink.
class CharakBottomBar extends StatelessWidget {
  final List<CharakNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CharakBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = CharakColors.isInk;
    final barColor = ink ? CharakColors.ground : CharakColors.card;
    return Container(
      decoration: BoxDecoration(
        color: barColor,
        border: Border(top: BorderSide(color: ink ? CharakColors.card : CharakColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: CharakSizes.bottomBarHeight,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: _NavButton(item: items[i], active: i == currentIndex, onTap: () => onTap(i))),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final CharakNavItem item;
  final bool active;
  final VoidCallback onTap;
  const _NavButton({required this.item, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ink = CharakColors.isInk;
    final pill = ink ? CharakColors.primary : CharakColors.primaryMid;
    final on = ink ? Colors.white : CharakPalette.blue700;
    final off = ink ? CharakColors.inkMuted : CharakColors.inkMuted;
    final color = active ? on : off;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: CharakPressable(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: CharakMotion.standard,
                  curve: CharakCurves.standard,
                  width: active ? CharakSizes.navPillWidth : 32,
                  height: CharakSizes.navPillHeight,
                  decoration: BoxDecoration(
                    color: active ? pill : pill.withValues(alpha: 0),
                    borderRadius: const BorderRadius.all(CharakRadius.pill),
                  ),
                ),
                Icon(active ? (item.activeIcon ?? item.icon) : item.icon, size: 22, color: color),
                if (item.badge > 0)
                  Positioned(
                    top: -2,
                    right: active ? 8 : 0,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: CharakPalette.chandan400,
                        borderRadius: const BorderRadius.all(CharakRadius.pill),
                        border: Border.all(color: ink ? CharakColors.ground : CharakColors.card, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text('${item.badge}',
                          style: CharakText.overline.tabular.copyWith(fontSize: 9, height: 1, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: CharakMotion.standard,
              style: CharakText.caption.copyWith(
                fontSize: 12,
                color: color,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(item.label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Now Bar ─────────────────────────────────────────

/// The Now Bar: an ink pill that floats above the bottom bar for anything
/// happening now (an upcoming consult, a request awaiting payment).
///
/// It rises 90px on motion.emphasized [delay] after the screen enters. Tap
/// it to expand 60 → 140px and reveal [actionLabel]. The [trailing] value
/// (a countdown) uses tabular figures so it ticks without jitter. With
/// [live] set, the leading dot pulses (motion.live) in Chandan.
class CharakNowBar extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool live;
  final Duration delay;

  const CharakNowBar({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.live = false,
    this.delay = const Duration(milliseconds: 600),
  });

  @override
  State<CharakNowBar> createState() => _CharakNowBarState();
}

class _CharakNowBarState extends State<CharakNowBar> with SingleTickerProviderStateMixin {
  late final _enter = AnimationController(vsync: this, duration: CharakMotion.emphasized);
  late final _t = CurvedAnimation(parent: _enter, curve: CharakCurves.emphasized);
  Timer? _timer;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) _enter.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = charakReduceMotion(context);
    final pillColor = CharakColors.isInk ? CharakPalette.ink700 : CharakColors.chrome;
    final expandable = widget.actionLabel != null;

    final collapsed = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: widget.live ? CharakPalette.chandan900 : CharakColors.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: widget.live
              ? const CharakLivePulse(color: CharakPalette.chandan300, size: 10)
              : Icon(widget.icon, size: 20, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CharakText.label.copyWith(color: Colors.white)),
              if (widget.subtitle != null)
                Text(widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CharakText.caption.copyWith(color: CharakPalette.ink300)),
            ],
          ),
        ),
        if (widget.trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.all(CharakRadius.pill),
            ),
            child: Text(widget.trailing!, style: CharakText.label.tabular.copyWith(color: Colors.white)),
          ),
      ],
    );

    final body = CharakPressable(
      onTap: expandable ? () => setState(() => _expanded = !_expanded) : widget.onAction,
      child: AnimatedContainer(
        duration: reduce ? CharakMotion.reduced : CharakMotion.emphasized,
        curve: CharakCurves.emphasized,
        height: _expanded ? 140 : CharakSizes.nowBarHeight,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: pillColor,
          borderRadius: BorderRadius.circular(_expanded ? CharakRadii.card : CharakRadii.pill),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              SizedBox(height: 40, child: collapsed),
              if (expandable) ...[
                const SizedBox(height: 16),
                Row(children: [
                  if (widget.secondaryLabel != null) ...[
                    Expanded(child: _pillButton(widget.secondaryLabel!, widget.onSecondary, primary: false)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: _pillButton(widget.actionLabel!, widget.onAction, primary: true)),
                ]),
              ],
            ],
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _t,
      builder: (_, child) => Opacity(
        opacity: _t.value.clamp(0.0, 1.0),
        child: reduce ? child : Transform.translate(offset: Offset(0, 90 * (1 - _t.value)), child: child),
      ),
      child: body,
    );
  }

  Widget _pillButton(String label, VoidCallback? onTap, {required bool primary}) => CharakPressable(
    onTap: onTap,
    child: Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary ? CharakColors.primary : Colors.white.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      child: Text(label, style: CharakText.label.copyWith(fontSize: 16, color: Colors.white)),
    ),
  );
}

// ───────────────────────── heads-up ────────────────────────────────────────

/// Heads-up banner: drops from the top on motion.emphasized (450ms) and
/// goes back up on motion.exit (200ms). Blue, with an overline, one line of
/// detail and two actions. Returns true when [primaryLabel] was tapped.
Future<bool> showCharakHeadsUp(
  BuildContext context, {
  required String overline,
  required String message,
  String primaryLabel = 'Review',
  String secondaryLabel = 'Later',
  IconData icon = Icons.inbox_rounded,
  Duration autoDismiss = const Duration(seconds: 8),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final done = Completer<bool>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _HeadsUp(
      overline: overline,
      message: message,
      primaryLabel: primaryLabel,
      secondaryLabel: secondaryLabel,
      icon: icon,
      autoDismiss: autoDismiss,
      onClosed: (result) {
        entry.remove();
        if (!done.isCompleted) done.complete(result);
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

class _HeadsUp extends StatefulWidget {
  final String overline;
  final String message;
  final String primaryLabel;
  final String secondaryLabel;
  final IconData icon;
  final Duration autoDismiss;
  final ValueChanged<bool> onClosed;

  const _HeadsUp({
    required this.overline,
    required this.message,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.icon,
    required this.autoDismiss,
    required this.onClosed,
  });

  @override
  State<_HeadsUp> createState() => _HeadsUpState();
}

class _HeadsUpState extends State<_HeadsUp> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    vsync: this,
    duration: CharakMotion.emphasized,
    reverseDuration: CharakMotion.exit,
  )..forward();
  late final _t = CurvedAnimation(parent: _ctrl, curve: CharakCurves.emphasized, reverseCurve: CharakCurves.exit);
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer(widget.autoDismiss, () => _close(false));
  }

  Future<void> _close(bool result) async {
    _auto?.cancel();
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onClosed(result);
  }

  @override
  void dispose() {
    _auto?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = charakReduceMotion(context);
    return Positioned(
      left: 10,
      right: 10,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: _t,
          builder: (_, child) => Opacity(
            opacity: _t.value.clamp(0.0, 1.0),
            child: reduce ? child : Transform.translate(offset: Offset(0, -120 * (1 - _t.value)), child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: CharakPalette.blue500,
                borderRadius: BorderRadius.all(CharakRadius.card),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      child: Icon(widget.icon, color: CharakPalette.blue600, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.overline.toUpperCase(),
                            style: CharakText.overline.copyWith(color: CharakPalette.blue100)),
                        const SizedBox(height: 2),
                        Text(widget.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: CharakText.label.copyWith(fontSize: 16, color: Colors.white)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _btn(widget.secondaryLabel, false, () => _close(false))),
                    const SizedBox(width: 10),
                    Expanded(child: _btn(widget.primaryLabel, true, () => _close(true))),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, bool primary, VoidCallback onTap) => CharakPressable(
    onTap: onTap,
    child: Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary ? Colors.white : Colors.white.withValues(alpha: 0.16),
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      child: Text(label,
          style: CharakText.label.copyWith(fontSize: 16, color: primary ? CharakPalette.blue700 : Colors.white)),
    ),
  );
}

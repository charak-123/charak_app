import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

import '../design/motion.dart';
import '../design/tokens.dart';

/// Controls for CHARAK Design System V2 (design-system/README.md
/// § Components): pills, blocks and bars. Flat, tonal and rounded, with no
/// drop shadows. Blue marks everything you can tap; Chandan is never a
/// button.

// ─────────────────────────── chip ──────────────────────────────────────────

/// Pill chip (40px). Off: card fill with a 1.5px outline. On: solid blue.
/// Used for slot times, day pickers, directory filters and category rows.
/// A [disabled] chip reads as taken: quiet fill and struck-through label.
class CharakChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool disabled;

  /// Narrow tabular figures, for times and prices.
  final bool numeric;

  const CharakChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.disabled = false,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = disabled
        ? CharakColors.inkFaint
        : (selected ? CharakColors.onPrimary : CharakColors.ink);
    var style = CharakText.label.copyWith(
      color: fg,
      decoration: disabled ? TextDecoration.lineThrough : null,
      decorationColor: fg,
    );
    if (numeric) style = style.tabular;
    return CharakPressable(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: CharakMotion.standard,
        curve: CharakCurves.standard,
        height: CharakSizes.chipHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: disabled
              ? CharakColors.bgSubtle
              : (selected ? CharakColors.primary : CharakColors.card),
          border: Border.all(
            color: (selected || disabled) ? Colors.transparent : CharakColors.borderStrong,
            width: 1.5,
          ),
          borderRadius: const BorderRadius.all(CharakRadius.pill),
        ),
        // No alignment: an aligned Container would stretch to the full width
        // inside a Wrap. The tight 40px height centres the row vertically.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label, style: style),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrolling chip strip: no scrollbar, 8px gaps.
class CharakChipRow extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;

  const CharakChipRow({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: CharakSizes.chipHeight,
    child: ScrollConfiguration(
      behavior: const _NoScrollbar(),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: CharakSpacing.sm),
        itemBuilder: (_, i) => children[i],
      ),
    ),
  );
}

class _NoScrollbar extends ScrollBehavior {
  const _NoScrollbar();
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

// ───────────────────── segmented control ───────────────────────────────────

/// Segmented control (One UI): a pill track with a thumb that *slides*
/// between segments (motion.standard, 300ms, never jumps) while the labels
/// cross-fade their colour.
class CharakSegmented<T> extends StatelessWidget {
  final List<CharakSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  const CharakSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final index = math.max(0, segments.indexWhere((s) => s.value == value));
    final n = segments.length;
    final thumb = CharakColors.isInk ? CharakPalette.ink600 : CharakColors.card;
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CharakColors.isInk ? CharakColors.bgSubtle : CharakColors.warm,
        border: CharakColors.isInk ? null : Border.all(color: CharakPalette.chandan100),
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: charakReduceMotion(context) ? Duration.zero : CharakMotion.standard,
            curve: CharakCurves.standard,
            alignment: Alignment(n == 1 ? 0 : -1 + (2 * index / (n - 1)), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: thumb,
                  borderRadius: const BorderRadius.all(CharakRadius.pill),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: _Segment(
                    segment: segments[i],
                    on: i == index,
                    onTap: () => onChanged(segments[i].value),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CharakSegment<T> {
  final T value;
  final String label;
  final IconData? icon;
  const CharakSegment({required this.value, required this.label, this.icon});
}

class _Segment extends StatelessWidget {
  final CharakSegment segment;
  final bool on;
  final VoidCallback onTap;
  const _Segment({required this.segment, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = on ? CharakColors.ink : CharakColors.inkMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (segment.icon != null) ...[
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: CharakMotion.standard,
                builder: (_, c, __) => Icon(segment.icon, size: 16, color: c),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: AnimatedDefaultTextStyle(
                duration: CharakMotion.standard,
                curve: CharakCurves.standard,
                style: CharakText.label.copyWith(color: color),
                child: Text(segment.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────── status pill ─────────────────────────────────────────

/// Status tones. The V2 lifecycle tones ([requested], [accepted],
/// [confirmed], [active], [review], [declined]) each own one colour; the
/// generic V1 tones map onto them.
enum CharakStatusTone {
  /// = accepted (blue)
  primary,
  /// = confirmed (sage green)
  success,
  /// = review (orange)
  warning,
  /// = declined (red)
  danger,
  /// neutral ink
  muted,
  /// Chandan — the "Requested" moment
  requested,
  accepted,
  confirmed,
  /// Violet — a visit happening now
  active,
  review,
  declined,
}

/// Status chip: sentence case, 13/600, soft fill with its own ink. Every
/// booking state has exactly one colour (design-system/README.md § Status).
class CharakStatusPill extends StatelessWidget {
  final String label;
  final CharakStatusTone tone;
  final IconData? icon;
  /// Replaces the leading icon with a live pulse (for waiting states).
  final bool pulsingDot;

  const CharakStatusPill({
    super.key,
    required this.label,
    this.tone = CharakStatusTone.primary,
    this.icon,
    this.pulsingDot = false,
  });

  /// Booking-lifecycle pill, so every screen labels a status identically.
  /// Pass a [key] of `ValueKey(status)` when placing this inside a
  /// [CharakFadeSwap], so the switcher can see the status actually changed.
  factory CharakStatusPill.forStatus(
    String status, {
    Key? key,
    bool pulsingDot = false,
  }) {
    final (tone, label) = charakStatusFor(status);
    return CharakStatusPill(
      key: key,
      label: label,
      tone: tone,
      pulsingDot: pulsingDot || status == 'requested',
    );
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = charakToneColors(tone);
    final solid = charakToneSolid(tone);
    return Container(
      padding: EdgeInsets.fromLTRB(pulsingDot ? 6 : 12, 5, 12, 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulsingDot) ...[
            CharakLivePulse(color: solid, size: 6),
            const SizedBox(width: 2),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 6),
          ],
          Text(label, style: CharakText.caption.copyWith(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Maps a booking status string to its tone and label.
(CharakStatusTone, String) charakStatusFor(String status) => switch (status) {
  'requested'   => (CharakStatusTone.requested, 'Requested'),
  'accepted'    => (CharakStatusTone.accepted, 'Accepted'),
  'paid'        => (CharakStatusTone.confirmed, 'Paid · Confirmed'),
  'confirmed'   => (CharakStatusTone.confirmed, 'Confirmed'),
  'in_progress' => (CharakStatusTone.active, 'Active visit'),
  'active'      => (CharakStatusTone.active, 'Active visit'),
  'completed'   => (CharakStatusTone.confirmed, 'Completed'),
  'review'      => (CharakStatusTone.review, 'Needs review'),
  'declined'    => (CharakStatusTone.declined, 'Declined'),
  'cancelled'   => (CharakStatusTone.declined, 'Cancelled'),
  'expired'     => (CharakStatusTone.muted, 'Expired'),
  _             => (CharakStatusTone.muted, status),
};

CharakStatusColors _statusColors(CharakStatusTone tone) {
  final s = CharakColors.scheme;
  return switch (tone) {
    CharakStatusTone.primary || CharakStatusTone.accepted => s.accepted,
    CharakStatusTone.success || CharakStatusTone.confirmed => s.confirmed,
    CharakStatusTone.warning || CharakStatusTone.review => s.review,
    CharakStatusTone.danger || CharakStatusTone.declined => s.declined,
    CharakStatusTone.requested => s.requested,
    CharakStatusTone.active => s.active,
    CharakStatusTone.muted => s.neutral,
  };
}

/// (soft background, label ink) for a tone. Shared by badges, pills,
/// banners and strips so they never drift apart.
(Color, Color) charakToneColors(CharakStatusTone tone) {
  final c = _statusColors(tone);
  return (c.soft, c.on);
}

/// The solid status colour, for dots and icons.
Color charakToneSolid(CharakStatusTone tone) => _statusColors(tone).solid;

// ───────────────────── section title ───────────────────────────────────────

/// Overline section label (12/700, tracked, uppercase) above grouped content.
class CharakSectionTitle extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const CharakSectionTitle({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label.toUpperCase(),
      style: CharakText.overline.copyWith(color: CharakColors.inkMuted),
    );
    if (trailing == null) return text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [text, trailing!],
    );
  }
}

// ───────────────────── list row ────────────────────────────────────────────

/// One UI settings row, meant to sit inside a grouped block
/// ([CharakGroupedList] or a card). A tinted icon square, a 16/600 title with
/// an optional caption, and a trailing value/chevron. Divider on the bottom
/// edge unless [last] is set.
class CharakListRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final bool showChevron;
  final bool last;
  final VoidCallback? onTap;
  final Color? titleColor;

  const CharakListRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.showChevron = true,
    this.last = false,
    this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) => CharakPressable(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: CharakColors.border)),
      ),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: titleColor != null ? CharakColors.dangerSoft : CharakColors.tint,
                borderRadius: const BorderRadius.all(Radius.circular(14)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: titleColor ?? CharakColors.primaryDeep),
            ),
          if (leading != null || icon != null) const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CharakText.body.weight(600).copyWith(color: titleColor)),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (trailingText != null)
            Text(trailingText!, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
          if (showChevron && trailing == null) ...[
            if (trailingText != null) const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: CharakColors.inkFaint),
          ],
        ],
      ),
    ),
  );
}

// ───────────────────── pinned CTA bar ──────────────────────────────────────

/// Pinned bottom action area. Actions live in the thumb zone, so this is
/// where Accept, Pay and Send request go. A card-coloured block with 26px
/// top corners and no border; 12/20/16 padding and 10px gaps. Respects the
/// bottom safe area.
class CharakCtaBar extends StatelessWidget {
  final List<Widget> children;

  /// Optional line above the actions (a price, a hint).
  final Widget? header;

  const CharakCtaBar({super.key, required this.children, this.header});

  /// Convenience for the common single-button case.
  factory CharakCtaBar.single(Widget child) => CharakCtaBar(children: [Expanded(child: child)]);

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: CharakColors.card,
      borderRadius: const BorderRadius.vertical(top: CharakRadius.card),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[header!, const SizedBox(height: 12)],
            Row(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  children[i],
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ───────────────────── skeleton ────────────────────────────────────────────

/// Waiting shimmer: a linear 1.4s sweep over the quiet fill. Stops (static
/// fill) when Reduce motion is on.
class CharakSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const CharakSkeleton({super.key, this.width, this.height = 14, this.radius = 8});

  @override
  State<CharakSkeleton> createState() => _CharakSkeletonState();
}

class _CharakSkeletonState extends State<CharakSkeleton> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

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
    final base = CharakColors.bgSubtle;
    final hi = CharakColors.isInk ? CharakPalette.ink600 : CharakColors.card;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => DecoratedBox(
            decoration: BoxDecoration(
              color: base,
              gradient: LinearGradient(
                begin: Alignment(-1 + (_ctrl.value * 2) - 1, 0),
                end: Alignment(1 + (_ctrl.value * 2) - 1, 0),
                colors: [base, hi.withValues(alpha: 0.75), base],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

// ───────────────────── success check ───────────────────────────────────────

/// Payment / booking success: the circle scales in on the emphasized curve
/// and the tick draws itself on over 300ms.
class CharakSuccessCheck extends StatefulWidget {
  final double size;
  const CharakSuccessCheck({super.key, this.size = 88});

  @override
  State<CharakSuccessCheck> createState() => _CharakSuccessCheckState();
}

class _CharakSuccessCheckState extends State<CharakSuccessCheck> with SingleTickerProviderStateMixin {
  static const _drawDelay = Duration(milliseconds: 120);
  static const _total = CharakMotion.emphasized;

  late final _ctrl = AnimationController(vsync: this, duration: _total)..forward();

  static final _drawStart = _drawDelay.inMilliseconds / _total.inMilliseconds;
  static final _drawEnd = (_drawDelay + CharakMotion.standard).inMilliseconds / _total.inMilliseconds;

  late final _pop = Tween(begin: 0.8, end: 1.0)
      .animate(CurvedAnimation(parent: _ctrl, curve: CharakCurves.emphasized));

  late final _draw = CurvedAnimation(
      parent: _ctrl, curve: Interval(_drawStart, math.min(1.0, _drawEnd), curve: CharakCurves.standard));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (charakReduceMotion(context)) {
      return CustomPaint(size: Size.square(widget.size), painter: _CheckPainter(progress: 1));
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.scale(
        scale: _pop.value,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _CheckPainter(progress: _draw.value),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;
  _CheckPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);

    // Solid sage disc (Paid · Confirmed) with a white tick.
    canvas.drawCircle(c, s / 2, Paint()..color = CharakColors.scheme.confirmed.solid);

    final p1 = Offset(s * 0.30, s * 0.52);
    final p2 = Offset(s * 0.44, s * 0.66);
    final p3 = Offset(s * 0.70, s * 0.38);

    final leg1 = (p2 - p1).distance;
    final leg2 = (p3 - p2).distance;
    final drawn = (leg1 + leg2) * progress.clamp(0.0, 1.0);

    final path = Path()..moveTo(p1.dx, p1.dy);
    if (drawn <= leg1) {
      final t = leg1 == 0 ? 0.0 : drawn / leg1;
      path.lineTo(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final t = leg2 == 0 ? 0.0 : ((drawn - leg1) / leg2).clamp(0.0, 1.0);
      path.lineTo(p2.dx + (p3.dx - p2.dx) * t, p2.dy + (p3.dy - p2.dy) * t);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * (4 / 88)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

// ───────────────────── mic waveform ────────────────────────────────────────

/// Seven-bar recording waveform used on the intake screen.
class CharakMicWave extends StatefulWidget {
  final bool active;
  final Color? color;
  const CharakMicWave({super.key, this.active = true, this.color});

  @override
  State<CharakMicWave> createState() => _CharakMicWaveState();
}

class _CharakMicWaveState extends State<CharakMicWave> with SingleTickerProviderStateMixin {
  static const _heights = [12.0, 24.0, 18.0, 28.0, 15.0, 22.0, 11.0];
  static const _delays = [0.0, 0.1, 0.2, 0.3, 0.15, 0.25, 0.05]; // seconds

  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(CharakMicWave old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? CharakColors.primary;
    return SizedBox(
      height: 34,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _heights.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              _bar(_heights[i], _delays[i], color),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bar(double height, double delaySec, Color color) {
    final phase = widget.active ? ((_ctrl.value - (delaySec / 0.9)) % 1.0 + 1.0) % 1.0 : 0.0;
    final scale = widget.active ? 0.6 + 0.4 * math.sin(phase * math.pi) : 0.6;
    return Container(
      width: 3,
      height: height * scale,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
    );
  }
}

// ───────────────────── fee list ────────────────────────────────────────────

/// A single label/amount line inside a [CharakFeeList].
class CharakFeeRow {
  final String label;
  final String value;
  /// Smaller muted style, for secondary lines like "Extra time (per 15 min)".
  final bool muted;
  const CharakFeeRow(this.label, this.value, {this.muted = false});
}

/// Label/amount block for fee breakdowns and procedure prices. A flat card
/// block; amounts use narrow tabular figures so columns line up.
class CharakFeeList extends StatelessWidget {
  final List<CharakFeeRow> rows;

  const CharakFeeList({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      color: CharakColors.card,
      borderRadius: const BorderRadius.all(CharakRadius.tile),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: i == rows.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: CharakColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].label,
                    style: (rows[i].muted ? CharakText.caption : CharakText.body)
                        .copyWith(color: rows[i].muted ? CharakColors.inkMuted : CharakColors.ink),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  rows[i].value,
                  style: (rows[i].muted ? CharakText.caption : CharakText.body.weight(600))
                      .tabular
                      .copyWith(color: rows[i].muted ? CharakColors.inkMuted : CharakColors.ink),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

// ───────────────────── empty state ─────────────────────────────────────────

/// Centred empty state: a tinted rounded-square icon, a wide title, an
/// explanation and an optional action.
class CharakEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const CharakEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: CharakColors.tint,
            borderRadius: const BorderRadius.all(CharakRadius.card),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 34, color: CharakColors.primary),
        ),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: CharakText.titleSmall),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: CharakText.body.copyWith(color: CharakColors.inkMuted),
        ),
        if (action != null) ...[
          const SizedBox(height: 22),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: action!),
        ],
      ],
    ),
  );
}

// ───────────────── outcome states ──────────────────────────────────────────

/// Which visual treatment an outcome screen uses for its icon badge.
enum CharakOutcomeTone {
  /// Animated sage success check.
  success,
  /// Chandan "Requested" moment, for waiting on the doctor.
  waiting,
  /// Neutral, for declined/closed states.
  neutral,
}

/// Full-screen outcome panel used by request-sent / confirmed / declined /
/// visit-complete screens: a large badge, a wide 36px title (title.large),
/// a supporting line and optional content beneath.
class CharakOutcomeState extends StatelessWidget {
  final CharakOutcomeTone tone;
  final IconData? icon;
  final String title;
  final String message;
  final Widget? child;

  const CharakOutcomeState({
    super.key,
    this.tone = CharakOutcomeTone.success,
    this.icon,
    required this.title,
    required this.message,
    this.child,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _badge(),
        const SizedBox(height: 24),
        Text(title, textAlign: TextAlign.center, style: CharakText.titleLarge),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: CharakText.bodyLarge.copyWith(color: CharakColors.inkMuted),
          ),
        ),
        if (child != null) ...[const SizedBox(height: 28), child!],
      ],
    ),
  );

  Widget _badge() => switch (tone) {
    CharakOutcomeTone.success => const CharakSuccessCheck(size: 88),
    CharakOutcomeTone.waiting => _circle(CharakColors.chandanSoft, CharakColors.chandan),
    CharakOutcomeTone.neutral => _circle(CharakColors.bgSubtle, CharakColors.inkMuted),
  };

  Widget _circle(Color bg, Color fg) => Container(
    width: 88,
    height: 88,
    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Icon(icon ?? Icons.schedule_rounded, size: 40, color: fg),
  );
}

// ───────── summary card ────────────────────────────────────────────────────

/// One key/value line inside a [CharakSummaryCard]: muted key on the left,
/// 600-weight value hard right.
class CharakSummaryRow extends StatelessWidget {
  final String label;

  /// Plain text value. Ignored when [child] is supplied.
  final String? value;

  /// Arbitrary trailing content (a pill, a badge) instead of [value].
  final Widget? child;

  /// 400 weight, muted colour.
  final bool muted;

  /// Narrow tabular figures: prices, times, refs.
  final bool tabular;

  const CharakSummaryRow({
    super.key,
    required this.label,
    this.value,
    this.child,
    this.muted = false,
    this.tabular = false,
  });

  @override
  Widget build(BuildContext context) {
    var style = (muted ? CharakText.body : CharakText.body.weight(600))
        .copyWith(color: muted ? CharakColors.inkMuted : CharakColors.ink);
    if (tabular) style = style.tabular;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(label, style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: child ?? Text(value ?? '', textAlign: TextAlign.right, style: style),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hairline rule with 7px breathing room above and below.
class CharakSummaryDivider extends StatelessWidget {
  const CharakSummaryDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: SizedBox(
      height: 1,
      child: ColoredBox(color: CharakColors.border),
    ),
  );
}

/// Flat 26px card block that holds [CharakSummaryRow]s and
/// [CharakSummaryDivider]s. Used by review, request sent, accepted,
/// confirmed, declined, procedure bill and visit details.
class CharakSummaryCard extends StatelessWidget {
  final List<Widget> rows;

  /// Optional overline above the rows.
  final String? title;

  const CharakSummaryCard({super.key, required this.rows, this.title});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(CharakSpacing.gutter),
    decoration: BoxDecoration(
      color: CharakColors.card,
      borderRadius: const BorderRadius.all(CharakRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          CharakSectionTitle(label: title!),
          const SizedBox(height: 8),
        ],
        ...rows,
      ],
    ),
  );
}

// ───────── note banner ─────────────────────────────────────────────────────

/// Tinted explanatory banner in one status tone: 20px radius, a 18px icon
/// and body copy with an optional bold lead-in.
class CharakNoteBanner extends StatelessWidget {
  final IconData icon;

  /// Leading bold run, e.g. "Under senior review".
  final String? leadLabel;

  final String message;
  final CharakStatusTone tone;

  const CharakNoteBanner({
    super.key,
    required this.icon,
    required this.message,
    this.leadLabel,
    this.tone = CharakStatusTone.warning,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, ink) = charakToneColors(tone);
    final base = CharakText.body.copyWith(fontSize: 14, height: 20 / 14, color: ink);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(CharakRadius.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (leadLabel != null)
                    TextSpan(text: '$leadLabel ', style: base.copyWith(fontWeight: FontWeight.w700)),
                  TextSpan(text: message),
                ],
              ),
              style: base,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────── info strip ──────────────────────────────────────────────────────

/// Tinted single-line strip for countdowns, ETAs, in-range notices and
/// bill-approval confirmations. A label and an optional tabular value.
class CharakInfoStrip extends StatelessWidget {
  final String label;

  /// Right-aligned emphasis value (a timer or an ETA). Omit for a plain notice.
  final String? value;

  /// Leading 18px glyph.
  final IconData? icon;

  final CharakStatusTone tone;

  /// Renders [value] with tabular figures. Countdowns need it; ETAs don't.
  final bool tabularValue;

  const CharakInfoStrip({
    super.key,
    required this.label,
    this.value,
    this.icon,
    this.tone = CharakStatusTone.primary,
    this.tabularValue = false,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = charakToneColors(tone);
    var valueStyle = CharakText.numeric.copyWith(color: fg);
    if (!tabularValue) valueStyle = CharakText.titleSmall.copyWith(color: fg, fontSize: 18);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(CharakRadius.tile),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(label, style: CharakText.label.copyWith(color: fg))),
          if (value != null) ...[
            const SizedBox(width: 10),
            Text(value!, style: valueStyle),
          ],
        ],
      ),
    );
  }
}

// ───────── star rating ─────────────────────────────────────────────────────

/// Star row. Ratings are a Chandan moment, so lit stars are Chandan.
/// Interactive when [onChanged] is supplied, otherwise read-only.
class CharakStarRating extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;
  final double gap;

  const CharakStarRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 40,
    this.gap = 10,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: onChanged == null ? MainAxisSize.min : MainAxisSize.max,
    children: [
      for (var i = 1; i <= 5; i++) ...[
        if (i > 1) SizedBox(width: gap),
        _star(i),
      ],
    ],
  );

  Widget _star(int i) {
    final star = AnimatedScale(
      scale: i <= value ? 1 : 0.92,
      duration: CharakMotion.standard,
      curve: CharakCurves.emphasized,
      child: Icon(
        Icons.star_rounded,
        size: size,
        color: i <= value ? CharakPalette.chandan400 : CharakColors.borderStrong,
      ),
    );
    if (onChanged == null) return star;
    return GestureDetector(
      onTap: () => onChanged!(i),
      behavior: HitTestBehavior.opaque,
      child: star,
    );
  }
}

/// Compact "★ 4.8" rating chip: chandan on warm, narrow tabular number.
class CharakRatingChip extends StatelessWidget {
  final String rating;
  const CharakRatingChip({super.key, required this.rating});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: CharakColors.chandanSoft,
      borderRadius: const BorderRadius.all(CharakRadius.pill),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, size: 14, color: CharakColors.chandan),
      const SizedBox(width: 3),
      Text(rating, style: CharakText.caption.weight(700).tabular.copyWith(color: CharakColors.onChandanSoft)),
    ]),
  );
}

// ───────────────────── visit line ──────────────────────────────────────────

/// One line inside a "Visit details" card: an 18px blue icon, then muted
/// text in which the key fact is emphasised to ink/600.
class CharakVisitLine extends StatelessWidget {
  final IconData icon;

  /// The emphasised fragment, rendered ink/600.
  final String value;

  /// Optional muted tail appended after a `·` separator.
  final String? trailing;

  const CharakVisitLine({
    super.key,
    required this.icon,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final muted = CharakText.body.copyWith(fontSize: 15, color: CharakColors.inkMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: CharakColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: muted.copyWith(color: CharakColors.ink, fontWeight: FontWeight.w600),
                  ),
                  if (trailing != null) TextSpan(text: ' · $trailing'),
                ],
              ),
              style: muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────── hint line ───────────────────────────────────────────

/// Small muted explanatory line that trails a block of controls. With
/// [icon] it gets a 16px blue glyph aligned to the first line.
class CharakHintLine extends StatelessWidget {
  final String text;
  final IconData? icon;
  final TextAlign align;

  const CharakHintLine({
    super.key,
    required this.text,
    this.icon,
    this.align = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final style = charakHintStyle;
    if (icon == null) return Text(text, style: style, textAlign: align);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: CharakColors.primary),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

// ───────── field ───────────────────────────────────────────────────────────

/// Text field (V2): a 20px-radius box whose label sits *inside* the box
/// above the value. The outline turns blue (2px) on focus and red on error.
/// 60px tall for a single line.
class CharakField extends StatefulWidget {
  final String? label;
  final String? placeholder;

  /// Muted helper line under the box.
  final String? hint;

  /// Error text; also turns the outline red.
  final String? error;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter> inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Null makes the box grow like a textarea; 1 keeps a single line.
  final int? maxLines;
  final int minLines;

  /// Renders the value with tabular figures (card numbers, OTP, amounts).
  final bool tabular;

  /// Leading box shown to the left at a fixed width, e.g. the "+91" prefix.
  final Widget? prefixBox;

  const CharakField({
    super.key,
    this.label,
    this.placeholder,
    this.hint,
    this.error,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters = const [],
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines = 1,
    this.tabular = false,
    this.prefixBox,
  });

  /// A field-shaped static box, used for the phone screen's "+91" prefix.
  static Widget staticBox(String text, {double width = 92}) => Container(
    width: width,
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: CharakColors.card,
      border: Border.all(color: CharakColors.borderStrong, width: 1.5),
      borderRadius: const BorderRadius.all(CharakRadius.input),
    ),
    child: Text(text, style: CharakText.bodyLarge.tabular.copyWith(color: CharakColors.inkMuted)),
  );

  @override
  State<CharakField> createState() => _CharakFieldState();
}

class _CharakFieldState extends State<CharakField> {
  FocusNode? _owned;
  FocusNode get _node => widget.focusNode ?? (_owned ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_sync);
  }

  void _sync() {
    if (_node.hasFocus != _focused) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_sync);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.maxLines == 1;
    final bad = widget.error != null;
    final edge = bad
        ? CharakColors.danger
        : (_focused ? CharakColors.primary : CharakColors.borderStrong);

    var valueStyle = CharakText.bodyLarge.copyWith(color: CharakColors.ink);
    if (widget.tabular) valueStyle = valueStyle.tabular;

    Widget box = GestureDetector(
      onTap: () => _node.requestFocus(),
      child: AnimatedContainer(
        duration: CharakMotion.standard,
        curve: CharakCurves.standard,
        constraints: BoxConstraints(minHeight: single ? 60 : 96),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: CharakColors.card,
          border: Border.all(color: edge, width: (_focused || bad) ? 2 : 1.5),
          borderRadius: const BorderRadius.all(CharakRadius.input),
        ),
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.label != null)
              AnimatedDefaultTextStyle(
                duration: CharakMotion.standard,
                style: CharakText.caption.weight(600).copyWith(
                  color: bad
                      ? CharakColors.danger
                      : (_focused ? CharakColors.primary : CharakColors.inkMuted),
                ),
                child: Text(widget.label!),
              ),
            TextField(
              controller: widget.controller,
              focusNode: _node,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType ??
                  (single ? TextInputType.text : TextInputType.multiline),
              textInputAction: widget.textInputAction,
              textCapitalization: widget.textCapitalization,
              inputFormatters: widget.inputFormatters,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              maxLines: widget.maxLines,
              minLines: single ? 1 : widget.minLines,
              cursorColor: CharakColors.primary,
              style: valueStyle,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.only(top: 2),
                hintText: widget.placeholder,
                hintStyle: CharakText.bodyLarge.copyWith(color: CharakColors.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.prefixBox != null) {
      box = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.prefixBox!,
          const SizedBox(width: 10),
          Expanded(child: box),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        box,
        if (widget.error != null) ...[
          const SizedBox(height: 8),
          Text(widget.error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
        ] else if (widget.hint != null) ...[
          const SizedBox(height: 8),
          Text(widget.hint!, style: charakHintStyle),
        ],
      ],
    );
  }
}

/// Muted helper copy (caption).
TextStyle get charakHintStyle =>
    CharakText.caption.copyWith(fontWeight: FontWeight.w400, color: CharakColors.inkMuted);

/// Muted line under a screen title (body).
TextStyle get charakScreenSubStyle => CharakText.body.copyWith(color: CharakColors.inkMuted);

/// Screen title on onboarding / auth / outcome screens (title.large, wide).
TextStyle get charakScreenTitleStyle => CharakText.titleLarge.copyWith(color: CharakColors.ink);

// ───────────────────── skeleton presets ────────────────────────────────────

/// Shimmering stand-in for a card in a list (doctor card, booking card,
/// request card). Mirrors the real card's geometry so the swap to loaded
/// content doesn't jump.
class CharakSkeletonCard extends StatelessWidget {
  /// Draws the leading avatar block.
  final bool avatar;

  /// Draws the third, shorter footer line.
  final bool footer;

  const CharakSkeletonCard({super.key, this.avatar = true, this.footer = true});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(CharakSpacing.gutter),
    decoration: BoxDecoration(
      color: CharakColors.card,
      borderRadius: const BorderRadius.all(CharakRadius.card),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (avatar) ...[
          const CharakSkeleton(width: 52, height: 52, radius: CharakRadii.avatar),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CharakSkeleton(width: 160, height: 18),
              const SizedBox(height: 8),
              const CharakSkeleton(width: 100, height: 13),
              if (footer) ...[
                const SizedBox(height: 14),
                const Row(
                  children: [
                    CharakSkeleton(width: 70, height: 13),
                    Spacer(),
                    CharakSkeleton(width: 48, height: 18),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// A short run of [CharakSkeletonCard]s: the standard loading state for any
/// list screen.
class CharakSkeletonList extends StatelessWidget {
  final int count;
  final bool avatar;
  final EdgeInsets padding;

  const CharakSkeletonList({
    super.key,
    this.count = 3,
    this.avatar = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Column(
      children: List.generate(count, (_) => CharakSkeletonCard(avatar: avatar)),
    ),
  );
}

/// Loading state for a detail screen: an identity block followed by stacked
/// content lines.
class CharakSkeletonDetail extends StatelessWidget {
  const CharakSkeletonDetail({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CharakSkeleton(width: 72, height: 72, radius: 22),
        SizedBox(height: 16),
        CharakSkeleton(width: 220, height: 30),
        SizedBox(height: 10),
        CharakSkeleton(width: 150, height: 14),
        SizedBox(height: 24),
        CharakSkeleton(height: 72, radius: CharakRadii.card),
        SizedBox(height: 20),
        CharakSkeleton(width: 90, height: 12),
        SizedBox(height: 10),
        CharakSkeleton(height: 14),
        SizedBox(height: 7),
        CharakSkeleton(height: 14),
        SizedBox(height: 7),
        CharakSkeleton(width: 220, height: 14),
        SizedBox(height: 20),
        CharakSkeleton(height: 96, radius: CharakRadii.card),
      ],
    ),
  );
}

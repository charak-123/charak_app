import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

import '../design/tokens.dart';

/// Controls ported 1:1 from the wireframe's `charak-shared/core.css`.
/// Every metric here (heights, paddings, letter-spacing, alpha values) is
/// taken directly from that stylesheet so the Flutter build and the HTML
/// mockups stay pixel-comparable.

// ─────────────────────────── chip (`.chip` / `.chip.on`) ───────────────────

/// Pill filter chip: 36px tall, `bgSubtle`/`inkMuted` when off, solid `ink`
/// when on. Used for directory filters, slot day pickers, category rows.
class CharakChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  const CharakChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: CharakDurations.buttonPress,
      curve: Curves.easeInOut,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: selected ? CharakColors.ink : CharakColors.bgSubtle,
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: selected ? Colors.white : CharakColors.inkMuted),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 13.5,
              height: 1.2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : CharakColors.inkMuted,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Horizontally scrolling chip strip (`.chip-row`) — no scrollbar, 8px gaps.
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
    height: 36,
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

// ───────────────────── segmented control (`.seg`) ──────────────────────────

/// Segmented control: inset track on `bgSubtle`, 40px tall segments, the
/// active one lifted to white with a soft shadow.
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: CharakColors.bgSubtle,
      borderRadius: const BorderRadius.all(CharakRadius.button),
    ),
    child: Row(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _Segment(segment: segments[i], on: segments[i].value == value, onTap: () => onChanged(segments[i].value))),
        ],
      ],
    ),
  );
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
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: CharakDurations.buttonPress,
      curve: Curves.easeInOut,
      height: 40,
      decoration: BoxDecoration(
        color: on ? Colors.white : Colors.transparent,
        borderRadius: const BorderRadius.all(CharakRadius.pill),
        boxShadow: on
            ? const [BoxShadow(color: Color(0x1A101828), blurRadius: 4, offset: Offset(0, 1))]
            : null,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (segment.icon != null) ...[
            Icon(segment.icon, size: 15, color: on ? CharakColors.ink : CharakColors.inkMuted),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              segment.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: on ? CharakColors.ink : CharakColors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ───────────────────── status pill (`.status-pill`) ────────────────────────

enum CharakStatusTone { primary, success, warning, danger, muted }

/// Uppercase status pill — slightly larger than [CharakBadge] (5×12 padding,
/// 11.5px) and used for booking/request lifecycle states.
class CharakStatusPill extends StatelessWidget {
  final String label;
  final CharakStatusTone tone;
  final IconData? icon;
  /// Replaces the leading icon with an animated pulsing dot (for waiting states).
  final bool pulsingDot;

  const CharakStatusPill({
    super.key,
    required this.label,
    this.tone = CharakStatusTone.primary,
    this.icon,
    this.pulsingDot = false,
  });

  /// Booking-lifecycle pill, matching `Charak.statusPill` in the mockup's
  /// shared `core.js` so every screen labels a status identically.
  /// Pass a [key] of `ValueKey(status)` when placing this inside a
  /// [CharakFadeSwap], so the switcher can see the status actually changed.
  factory CharakStatusPill.forStatus(
    String status, {
    Key? key,
    bool pulsingDot = false,
  }) {
    final (tone, label) = switch (status) {
      'requested' => (CharakStatusTone.warning, 'Pending review'),
      'accepted'  => (CharakStatusTone.primary, 'Accepted'),
      'paid'      => (CharakStatusTone.success, 'Paid & confirmed'),
      'completed' => (CharakStatusTone.success, 'Completed'),
      'declined'  => (CharakStatusTone.danger,  'Declined'),
      'cancelled' => (CharakStatusTone.danger,  'Cancelled'),
      _           => (CharakStatusTone.primary, status),
    };
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulsingDot) ...[
            _PulseDot(color: fg),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
              letterSpacing: 11.5 * 0.04,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Exact tone pairs from `core.css` — the translucent backgrounds are the
/// spec's `rgba(...)` values converted to ARGB.
(Color, Color) charakToneColors(CharakStatusTone tone) => switch (tone) {
  CharakStatusTone.primary => (CharakColors.primarySoft, CharakColors.primaryDeep),
  CharakStatusTone.success => (const Color(0x1F1FAA6D), CharakColors.success),
  CharakStatusTone.warning => (const Color(0x21E0930B), const Color(0xFFB5780A)),
  CharakStatusTone.danger  => (const Color(0x1FE0473E), CharakColors.danger),
  CharakStatusTone.muted   => (CharakColors.bgSubtle, CharakColors.inkMuted),
};

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  // `.wait-dot` — 1.4s ease-in-out, opacity 1→0.35, scale 1→0.8
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);
  late final _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (_, __) => Opacity(
      opacity: 1 - (0.65 * _t.value),
      child: Transform.scale(
        scale: 1 - (0.2 * _t.value),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    ),
  );
}

// ───────────────────── section title (`.sec-title`) ────────────────────────

/// Uppercase, wide-tracked section label that precedes grouped content.
class CharakSectionTitle extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const CharakSectionTitle({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontFamily: CharakText.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 13 * 0.06,
        color: CharakColors.inkMuted,
      ),
    );
    if (trailing == null) return text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [text, trailing!],
    );
  }
}

// ───────────────────── list row (`.listrow`) ───────────────────────────────

/// Borderless settings/menu row with a rounded icon chip, title + optional
/// subtitle, and a trailing chevron. Divider is drawn on the bottom edge
/// unless [last] is set (mirrors `.listrow:last-child { border-bottom: 0 }`).
class CharakListRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? trailingText;
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
    this.showChevron = true,
    this.last = false,
    this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: CharakColors.border)),
      ),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: CharakColors.bgSubtle,
                borderRadius: const BorderRadius.all(CharakRadius.input),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: titleColor ?? CharakColors.ink),
            ),
          if (leading != null || icon != null) const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CharakText.bodyMed.copyWith(color: titleColor)),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontFamily: CharakText.fontFamily,
                      fontSize: 12.5,
                      height: 1.4,
                      color: CharakColors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailingText != null)
            Text(trailingText!, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
          if (showChevron) ...[
            if (trailingText != null) const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: CharakColors.inkMuted),
          ],
        ],
      ),
    ),
  );
}

// ───────────────────── pinned CTA bar (`.cta-bar`) ─────────────────────────

/// Pinned bottom action bar: white, 1px top border, 12/20/16 padding, 10px
/// gap between actions. Respects the bottom safe-area inset.
class CharakCtaBar extends StatelessWidget {
  final List<Widget> children;

  const CharakCtaBar({super.key, required this.children});

  /// Convenience for the common single-button case.
  factory CharakCtaBar.single(Widget child) => CharakCtaBar(children: [Expanded(child: child)]);

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: CharakColors.bg,
      border: Border(top: BorderSide(color: CharakColors.border)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              children[i],
            ],
          ],
        ),
      ),
    ),
  );
}

// ───────────────────── skeleton (`.skel`) ──────────────────────────────────

/// Shimmering placeholder block — 1.4s left-to-right sweep over `bgSubtle`.
class CharakSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const CharakSkeleton({super.key, this.width, this.height = 14, this.radius = 8});

  @override
  State<CharakSkeleton> createState() => _CharakSkeletonState();
}

class _CharakSkeletonState extends State<CharakSkeleton> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.radius),
    child: SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => DecoratedBox(
          decoration: BoxDecoration(
            color: CharakColors.bgSubtle,
            gradient: LinearGradient(
              begin: Alignment(-1 + (_ctrl.value * 2) - 1, 0),
              end: Alignment(1 + (_ctrl.value * 2) - 1, 0),
              colors: const [
                CharakColors.bgSubtle,
                Color(0xBFFFFFFF),
                CharakColors.bgSubtle,
              ],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

// ───────────────────── success check (`.check-circle`) ─────────────────────

/// Animated success mark: the circle springs in (scale 0.7 → 1.04 → 1 over
/// 400ms) while the tick strokes itself on with a 120ms delay.
class CharakSuccessCheck extends StatefulWidget {
  final double size;
  const CharakSuccessCheck({super.key, this.size = 84});

  @override
  State<CharakSuccessCheck> createState() => _CharakSuccessCheckState();
}

class _CharakSuccessCheckState extends State<CharakSuccessCheck> with SingleTickerProviderStateMixin {
  // `.check-circle` pops over `--dur-success` (400ms) while the tick strokes
  // itself on for 380ms starting at 120ms — a 500ms envelope in total.
  static const _drawDelay = Duration(milliseconds: 120);
  static final _total = CharakDurations.successAnim + _drawDelay;

  late final _ctrl = AnimationController(vsync: this, duration: _total)..forward();

  static final _popEnd =
      CharakDurations.successAnim.inMilliseconds / _total.inMilliseconds;
  static final _drawStart = _drawDelay.inMilliseconds / _total.inMilliseconds;

  late final _pop = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.04), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 1.04, end: 1.0), weight: 40),
  ]).animate(CurvedAnimation(parent: _ctrl, curve: Interval(0, _popEnd, curve: Curves.easeOut)));

  late final _draw =
      CurvedAnimation(parent: _ctrl, curve: Interval(_drawStart, 1, curve: Curves.easeOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
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

class _CheckPainter extends CustomPainter {
  final double progress;
  _CheckPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final r = (s / 2) - 2;

    canvas.drawCircle(c, r, Paint()..color = CharakColors.primarySoft);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = CharakColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * (2.5 / 84),
    );

    // tick geometry, proportional to the 84px reference drawing
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
        ..color = CharakColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * (3 / 84)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

// ───────────────────── mic waveform (`.wave`) ──────────────────────────────

/// Seven-bar recording waveform used on the intake screen. Bar heights and
/// per-bar animation delays match the stylesheet exactly.
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
    // CSS: 0%,100% { scaleY(0.6) } 50% { scaleY(1) } over 0.9s, per-bar delay
    final phase = widget.active ? ((_ctrl.value - (delaySec / 0.9)) % 1.0 + 1.0) % 1.0 : 0.0;
    final scale = widget.active ? 0.6 + 0.4 * math.sin(phase * math.pi) : 0.6;
    return Container(
      width: 3,
      height: height * scale,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
    );
  }
}

// ───────────────────── fee list (`.fee-line` / `.fee-row`) ─────────────────

/// A single label/amount line inside a [CharakFeeList].
class CharakFeeRow {
  final String label;
  final String value;
  /// Renders the row in the smaller muted style (`.fee-row.muted`) — used for
  /// secondary lines like "Extra time (per 15 min)".
  final bool muted;
  const CharakFeeRow(this.label, this.value, {this.muted = false});
}

/// Bordered label/amount list used for fee breakdowns and procedure prices.
/// Amounts are rendered with tabular figures so columns line up.
class CharakFeeList extends StatelessWidget {
  final List<CharakFeeRow> rows;

  const CharakFeeList({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: CharakColors.border),
      borderRadius: const BorderRadius.all(CharakRadius.card),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: i == rows.length - 1
                  ? null
                  : const Border(bottom: BorderSide(color: CharakColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].label,
                    style: TextStyle(
                      fontFamily: CharakText.fontFamily,
                      fontSize: rows[i].muted ? 13 : 14,
                      height: 1.4,
                      color: rows[i].muted ? CharakColors.inkMuted : CharakColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  rows[i].value,
                  style: TextStyle(
                    fontFamily: CharakText.fontFamily,
                    fontSize: rows[i].muted ? 13 : 14,
                    fontWeight: rows[i].muted ? FontWeight.w400 : FontWeight.w600,
                    height: 1.4,
                    color: rows[i].muted ? CharakColors.inkMuted : CharakColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

// ───────────────────── empty state (`.empty-state`) ───────────────────────

/// Centred empty state: tinted circular icon, headline, explanation and an
/// optional action. Used when a list has nothing to show.
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
    padding: const EdgeInsets.fromLTRB(24, 52, 24, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(color: CharakColors.primarySoft, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(icon, size: 34, color: CharakColors.primary),
        ),
        const SizedBox(height: 18),
        Text(title,
            textAlign: TextAlign.center,
            style: CharakText.h2.copyWith(fontSize: 17)),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: CharakText.fontFamily,
            fontSize: 13.5,
            height: 1.55,
            color: CharakColors.inkMuted,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 22),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: action!),
        ],
      ],
    ),
  );
}

// ───────────────── outcome states (`.ok-state` / `.wait-state`) ────────────

/// Which visual treatment an outcome screen uses for its icon badge.
enum CharakOutcomeTone {
  /// `.ok-state` with the animated success check.
  success,
  /// `.wait-state` — amber circle, for "waiting on the doctor" states.
  waiting,
  /// `.ok-state .wait-ic` — neutral grey circle, for declined/closed states.
  neutral,
}

/// Full-screen outcome panel used by request-sent / confirmed / declined /
/// visit-complete screens: a large icon badge, a 24px title, a constrained
/// supporting line, and optional content beneath.
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
    padding: EdgeInsets.fromLTRB(24, tone == CharakOutcomeTone.waiting ? 48 : 40, 24, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _badge(),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: CharakText.display.copyWith(fontSize: 24, letterSpacing: -0.24),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 14.5,
              height: 1.6,
              color: CharakColors.inkMuted,
            ),
          ),
        ),
        if (child != null) ...[const SizedBox(height: 26), child!],
      ],
    ),
  );

  Widget _badge() => switch (tone) {
    CharakOutcomeTone.success => const CharakSuccessCheck(size: 84),
    CharakOutcomeTone.waiting => _circle(const Color(0x1FE0930B), CharakColors.warning),
    CharakOutcomeTone.neutral => _circle(CharakColors.bgSubtle, CharakColors.inkMuted),
  };

  Widget _circle(Color bg, Color fg) => Container(
    width: 88,
    height: 88,
    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Icon(icon ?? Icons.schedule, size: 40, color: fg),
  );
}

// ───────── summary card (`.rev-sum` / `.rev-row` / `.rev-div`) ─────────────

/// One key/value line inside a [CharakSummaryCard] — `.rev-row`: 14px text,
/// 7px vertical padding, muted key on the left, 600-weight value hard right.
class CharakSummaryRow extends StatelessWidget {
  final String label;

  /// Plain text value. Ignored when [child] is supplied.
  final String? value;

  /// Arbitrary trailing content (a pill, a badge) instead of [value].
  final Widget? child;

  /// `.rev-row .v.muted` — 400 weight, muted colour.
  final bool muted;

  /// Renders the value with tabular figures (`.tnum`) — prices, times, refs.
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: CharakText.fontFamily,
            fontSize: 14,
            height: 1.4,
            color: CharakColors.inkMuted,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: child ??
                Text(
                  value ?? '',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: CharakText.fontFamily,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                    color: muted ? CharakColors.inkMuted : CharakColors.ink,
                    fontFeatures:
                        tabular ? const [FontFeature.tabularFigures()] : null,
                  ),
                ),
          ),
        ),
      ],
    ),
  );
}

/// `.rev-div` — hairline rule with 7px breathing room above and below.
class CharakSummaryDivider extends StatelessWidget {
  const CharakSummaryDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 7),
    child: SizedBox(
      height: 1,
      child: ColoredBox(color: CharakColors.border),
    ),
  );
}

/// `.card.rev-sum` — the bordered 16px-padded block that holds
/// [CharakSummaryRow]s and [CharakSummaryDivider]s. Used by review, request
/// sent, accepted, confirmed, declined, procedure bill and visit details.
class CharakSummaryCard extends StatelessWidget {
  final List<Widget> rows;

  /// Optional `.sec-title` above the rows (visit-details "Your rating" block).
  final String? title;

  const CharakSummaryCard({super.key, required this.rows, this.title});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(CharakSpacing.base),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      border: Border.all(color: CharakColors.border),
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

// ───────── note banner (`.clarify-banner`) ────────────────────────────────

/// Tinted explanatory banner — `.clarify-banner`: 12/14 padding, card radius,
/// a 16px icon and 13px/1.5 copy, all in one tone. Warning uses the spec's
/// darker `#8A5B08` ink so the copy stays readable on the amber wash.
class CharakNoteBanner extends StatelessWidget {
  final IconData icon;

  /// Leading bold run (`<b>` in the mockup), e.g. "Under senior review".
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

  /// `.clarify-banner` has its own amber pair — a lighter 0.1 wash than the
  /// 0.13 badge tones, under a deeper ink than the pill's `#B5780A`.
  static const _warningBg = Color(0x1AE0930B);
  static const _warningInk = Color(0xFF8A5B08);

  @override
  Widget build(BuildContext context) {
    final isWarning = tone == CharakStatusTone.warning;
    final (toneBg, toneFg) = charakToneColors(tone);
    final bg = isWarning ? _warningBg : toneBg;
    final ink = isWarning ? _warningInk : toneFg;
    final base = TextStyle(
      fontFamily: CharakText.fontFamily,
      fontSize: 13,
      height: 1.5,
      color: ink,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (leadLabel != null)
                    TextSpan(
                      text: '$leadLabel ',
                      style: base.copyWith(fontWeight: FontWeight.w600),
                    ),
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

// ───────── info strip (`.act-timer`) ──────────────────────────────────────

/// Tinted single-line strip used for countdowns, ETAs, in-range notices and
/// bill-approval confirmations — `.act-timer`: 13/16 padding, card radius,
/// a 12.5px/600 label and an optional 17px/600 tabular value.
class CharakInfoStrip extends StatelessWidget {
  final String label;

  /// Right-aligned emphasis value (a timer or an ETA). Omit for a plain notice.
  final String? value;

  /// Leading 16px glyph — shown instead of spreading label and value apart.
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: fg,
              ),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 10),
            Text(
              value!,
              style: TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: fg,
                fontFeatures:
                    tabularValue ? const [FontFeature.tabularFigures()] : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────── star rating (`.stars`) ─────────────────────────────────────────

/// Star row — `.stars`: 40px filled stars, 10px gaps, `border` grey until lit
/// and `warning` once on. Interactive when [onChanged] is supplied, otherwise
/// a read-only display (visit details renders it at 18px).
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
    final star = Icon(
      Icons.star_rounded,
      size: size,
      color: i <= value ? CharakColors.warning : CharakColors.border,
    );
    if (onChanged == null) return star;
    return GestureDetector(
      onTap: () => onChanged!(i),
      behavior: HitTestBehavior.opaque,
      child: star,
    );
  }
}

// ───────────────────── visit line (`.visit-line`) ──────────────────────────

/// One line inside the "Visit details" card: a 15px primary icon, then muted
/// 13.5px text in which the key fact is emphasised to `ink`/600 (the spec's
/// `.visit-line b`). Rows are 9px tall top and bottom.
class CharakVisitLine extends StatelessWidget {
  final IconData icon;

  /// The emphasised fragment (`<b>`) — rendered ink/600.
  final String value;

  /// Optional muted tail appended after a `·` separator.
  final String? trailing;

  const CharakVisitLine({
    super.key,
    required this.icon,
    required this.value,
    this.trailing,
  });

  static const _muted = TextStyle(
    fontFamily: CharakText.fontFamily,
    fontSize: 13.5,
    height: 1.5,
    color: CharakColors.inkMuted,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Icon(icon, size: 15, color: CharakColors.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: _muted.copyWith(
                    color: CharakColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (trailing != null) TextSpan(text: ' · $trailing'),
              ],
            ),
            style: _muted,
          ),
        ),
      ],
    ),
  );
}

// ───────────────────── hint line (`.hint-line`) ────────────────────────────

/// Small muted explanatory line (12.5px) that trails a block of controls.
/// With [icon] it becomes the spec's `.exp-line`: a 15px primary icon aligned
/// to the first line of wrapped text.
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

  static const _style = TextStyle(
    fontFamily: CharakText.fontFamily,
    fontSize: 12.5,
    height: 1.5,
    color: CharakColors.inkMuted,
  );

  @override
  Widget build(BuildContext context) {
    if (icon == null) return Text(text, style: _style, textAlign: align);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: CharakColors.primary),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: _style)),
      ],
    );
  }
}

// ───────── field + input (`.field` / `.input`) ────────────────────────────

/// Spec-exact text field — `.field` label (13px/600 ink, 7px gap) over an
/// `.input` box: 50px tall single line (or 13/14 padding when multiline),
/// 10px control radius, and a 3px `rgba(47,111,237,0.12)` ring on focus.
///
/// This is the plain-Flutter counterpart to [CharakInput]; use it where the
/// stylesheet's exact box metrics matter (auth, intake, complaint, rating).
class CharakField extends StatefulWidget {
  final String? label;
  final String? placeholder;

  /// Muted helper line under the box (`.hint-line`).
  final String? hint;

  /// Error text; also turns the border and ring red.
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

  /// Null makes the box grow like `textarea.input`; 1 keeps the 50px line.
  final int? maxLines;
  final int minLines;

  /// Renders the value with tabular figures (card numbers, OTP, amounts).
  final bool tabular;

  /// Leading box shown to the left at a fixed width — e.g. the "+91" prefix,
  /// which the mockup draws as its own separate `.input`.
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

  /// A `.input`-shaped static box, used for the phone screen's "+91" prefix.
  static Widget staticBox(String text, {double width = 92}) => Container(
    width: width,
    height: 50,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: CharakColors.bg,
      border: Border.all(color: CharakColors.border),
      borderRadius: const BorderRadius.all(CharakRadius.button),
    ),
    child: Text(
      text,
      style: CharakText.bodyMed.copyWith(color: CharakColors.inkMuted),
    ),
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
        : (_focused ? CharakColors.primary : CharakColors.border);

    Widget box = AnimatedContainer(
      duration: CharakDurations.buttonPress,
      height: single ? 50 : null,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: single ? 0 : 13),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        border: Border.all(color: edge),
        borderRadius: const BorderRadius.all(CharakRadius.button),
        // `.input:focus` — 0 0 0 3px rgba(47,111,237,0.12)
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: (bad ? CharakColors.danger : CharakColors.primary)
                      .withValues(alpha: 0.12),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      alignment: single ? Alignment.centerLeft : null,
      child: TextField(
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
        style: CharakText.body.copyWith(
          fontFeatures: widget.tabular ? const [FontFeature.tabularFigures()] : null,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: widget.placeholder,
          hintStyle: CharakText.body.copyWith(color: CharakColors.inkMuted),
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
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: const TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: CharakColors.ink,
            ),
          ),
          const SizedBox(height: 7),
        ],
        box,
        if (widget.error != null) ...[
          const SizedBox(height: 7),
          Text(
            widget.error!,
            style: CharakText.caption.copyWith(color: CharakColors.danger),
          ),
        ] else if (widget.hint != null) ...[
          const SizedBox(height: 10),
          Text(widget.hint!, style: charakHintStyle),
        ],
      ],
    );
  }
}

/// `.hint-line` — 12.5px muted helper copy.
const charakHintStyle = TextStyle(
  fontFamily: CharakText.fontFamily,
  fontSize: 12.5,
  height: 1.45,
  color: CharakColors.inkMuted,
);

/// `.screen-sub` — 14px muted line under a `.screen-title`.
const charakScreenSubStyle = TextStyle(
  fontFamily: CharakText.fontFamily,
  fontSize: 14,
  height: 1.5,
  color: CharakColors.inkMuted,
);

/// `.screen-title` — 22px/600 with the spec's -0.01em optical tightening.
const charakScreenTitleStyle = TextStyle(
  fontFamily: CharakText.fontFamily,
  fontSize: 22,
  fontWeight: FontWeight.w600,
  height: 1.3,
  letterSpacing: -0.01 * 22,
  color: CharakColors.ink,
);

// ───────────────────── skeleton presets ────────────────────────────────────

/// Shimmering stand-in for a card in a list (doctor card, booking card,
/// request card). Mirrors the real card's geometry so the swap to loaded
/// content doesn't jump: 52px avatar, two text lines, a footer row.
class CharakSkeletonCard extends StatelessWidget {
  /// Draws the leading circular avatar block.
  final bool avatar;

  /// Draws the third, shorter footer line.
  final bool footer;

  const CharakSkeletonCard({super.key, this.avatar = true, this.footer = true});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: CharakColors.border),
      borderRadius: const BorderRadius.all(CharakRadius.card),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (avatar) ...[
          const CharakSkeleton(width: 52, height: 52, radius: 26),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CharakSkeleton(width: 148, height: 15),
              const SizedBox(height: 8),
              const CharakSkeleton(width: 96, height: 13),
              if (footer) ...[
                const SizedBox(height: 12),
                Row(
                  children: const [
                    CharakSkeleton(width: 60, height: 13),
                    Spacer(),
                    CharakSkeleton(width: 44, height: 15),
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

/// A short run of [CharakSkeletonCard]s — the standard loading state for any
/// list screen. Three cards reads as "content is coming" without implying a
/// specific result count.
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

/// Loading state for a detail screen: a centred identity block followed by
/// stacked content lines.
class CharakSkeletonDetail extends StatelessWidget {
  const CharakSkeletonDetail({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Center(
          child: Column(
            children: [
              CharakSkeleton(width: 84, height: 84, radius: 42),
              SizedBox(height: 12),
              CharakSkeleton(width: 168, height: 20),
              SizedBox(height: 8),
              CharakSkeleton(width: 120, height: 14),
            ],
          ),
        ),
        SizedBox(height: 24),
        CharakSkeleton(height: 64, radius: 12),
        SizedBox(height: 20),
        CharakSkeleton(width: 90, height: 13),
        SizedBox(height: 10),
        CharakSkeleton(height: 14),
        SizedBox(height: 7),
        CharakSkeleton(height: 14),
        SizedBox(height: 7),
        CharakSkeleton(width: 220, height: 14),
        SizedBox(height: 20),
        CharakSkeleton(width: 90, height: 13),
        SizedBox(height: 10),
        CharakSkeleton(height: 92, radius: 12),
      ],
    ),
  );
}

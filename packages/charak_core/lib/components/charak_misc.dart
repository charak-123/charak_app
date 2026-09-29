import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import 'charak_nav.dart' show CharakSwitch;

/// Pulsing status dot — used inside warning/status pills (e.g. "Under review").
class CharakPulsingDot extends StatefulWidget {
  final Color? color;
  final double size;
  const CharakPulsingDot({super.key, this.color, this.size = 7});

  @override
  State<CharakPulsingDot> createState() => _CharakPulsingDotState();
}

class _CharakPulsingDotState extends State<CharakPulsingDot> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  late final _anim = Tween(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: widget.size, height: widget.size,
      decoration: BoxDecoration(color: widget.color ?? CharakColors.warning, shape: BoxShape.circle),
    ),
  );
}

/// 3-dot onboarding step progress (wireframe's `.step-dots`).
class CharakStepDots extends StatelessWidget {
  final int total;
  final int current; // 0-indexed
  const CharakStepDots({super.key, this.total = 3, required this.current});

  // `.step-dots` — 26×4 bars, 6px gap, centred; filled bars use primary.
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < total; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Container(
          width: 26,
          height: 4,
          decoration: BoxDecoration(
            color: i <= current ? CharakColors.primary : CharakColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    ],
  );
}

/// Toggle card (One UI settings row as its own block): a tinted icon
/// square, title + caption, and a [CharakSwitch]. Flat card; only the icon
/// square and caption colour change with the value.
class CharakToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const CharakToggleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => CharakPressable(
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: CharakMotion.standard,
      curve: CharakCurves.standard,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(CharakSpacing.gutter),
      decoration: BoxDecoration(
        color: CharakColors.card,
        borderRadius: const BorderRadius.all(CharakRadius.card),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        AnimatedContainer(
          duration: CharakMotion.standard,
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: value ? CharakColors.primarySoft : CharakColors.bgSubtle,
            borderRadius: const BorderRadius.all(Radius.circular(14)),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: value ? CharakColors.primaryDeep : CharakColors.inkMuted, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: CharakText.body.weight(650).copyWith(fontSize: 17, color: CharakColors.ink)),
          const SizedBox(height: 2),
          Text(subtitle, style: CharakText.caption.copyWith(
              color: value ? CharakColors.primary : CharakColors.inkMuted)),
        ])),
        const SizedBox(width: 8),
        CharakSwitch(value: value, onChanged: onChanged),
      ]),
    ),
  );
}

/// Upload tile — dashed border + icon + label; turns solid + primarySoft +
/// checkmark once a file is attached. Matches `.upload-tile`/`.upload-tile.has`.
class CharakUploadTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? doneLabel;
  final bool done;
  final VoidCallback onTap;
  const CharakUploadTile({
    super.key,
    required this.icon,
    required this.label,
    this.doneLabel,
    required this.done,
    required this.onTap,
  });

  // 96px tall, 1.5px dashed outline that turns solid blue once attached.
  @override
  Widget build(BuildContext context) => CharakPressable(
    onTap: onTap,
    child: CustomPaint(
      painter: CharakDashedBorderPainter(
        color: done ? CharakColors.primary : CharakColors.borderStrong,
        dashed: !done,
        radius: CharakRadii.tile,
      ),
      child: Container(
        width: double.infinity,
        height: 96,
        decoration: BoxDecoration(
          color: done ? CharakColors.primarySoft : CharakColors.card,
          borderRadius: const BorderRadius.all(CharakRadius.tile),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(done ? Icons.check_circle_rounded : icon,
                color: done ? CharakColors.primaryDeep : CharakColors.primary, size: 22),
            const SizedBox(height: 7),
            Text(
              done ? (doneLabel ?? 'Attached') : label,
              style: CharakText.caption.copyWith(
                color: done ? CharakColors.primaryDeep : CharakColors.inkMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Draws a rounded rectangle outline, dashed or solid. Flutter has no dashed
/// `BorderSide`, so `.upload-tile` / `.attach-tile` need this.
class CharakDashedBorderPainter extends CustomPainter {
  final Color color;
  final bool dashed;
  final double radius;
  final double strokeWidth;

  CharakDashedBorderPainter({
    required this.color,
    required this.dashed,
    required this.radius,
    this.strokeWidth = 1.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
          size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );

    if (!dashed) {
      canvas.drawRRect(rrect, paint);
      return;
    }

    const dash = 5.0, gap = 4.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var pos = 0.0;
      while (pos < metric.length) {
        canvas.drawPath(
          metric.extractPath(pos, (pos + dash).clamp(0.0, metric.length)),
          paint,
        );
        pos += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(CharakDashedBorderPainter old) =>
      old.color != color || old.dashed != dashed || old.radius != radius;
}

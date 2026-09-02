import 'package:flutter/material.dart';
import 'package:charak_core/charak_core.dart';

class CharakButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool outlined;
  const CharakButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.outlined = false,
  });
  @override
  State<CharakButton> createState() => _State();
}

class _State extends State<CharakButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: CharakDurations.buttonPress,
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.97)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    return GestureDetector(
      onTapDown: enabled ? (_) => _ctrl.forward() : null,
      onTapUp:   enabled ? (_) { _ctrl.reverse(); widget.onPressed?.call(); } : null,
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: widget.outlined
            ? OutlinedButton(
                onPressed: enabled ? widget.onPressed : null,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: CharakColors.primary),
                  minimumSize: const Size(double.infinity, 52),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(CharakRadius.button)),
                ),
                child: _label(),
              )
            : FilledButton(
                onPressed: enabled ? widget.onPressed : null,
                child: _label(),
              ),
      ),
    );
  }

  Widget _label() => widget.isLoading
      ? const SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
      : Text(widget.label);
}

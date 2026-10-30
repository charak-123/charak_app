import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// A button in the photo viewer's top bar, e.g. the doctor's own "Change
/// photo". [onPressed] runs with the viewer still open; pop it yourself if
/// the action replaces the photo.
class CharakPhotoAction {
  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext viewerContext) onPressed;

  const CharakPhotoAction({required this.icon, required this.label, required this.onPressed});
}

/// Opens a photo full screen, the way tapping a profile photo does in
/// WhatsApp: it grows out of the avatar that was tapped ([heroTag]) onto a
/// dark ground with the name above it. Pinch or double-tap to zoom; drag it
/// down, tap ×, or press Back to close.
Future<void> showCharakPhoto(
  BuildContext context, {
  required String imageUrl,
  String? title,
  Object? heroTag,
  List<CharakPhotoAction> actions = const [],
}) {
  final reduce = charakReduceMotion(context);
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: reduce ? CharakMotion.reduced : CharakMotion.standard,
    reverseTransitionDuration: reduce ? CharakMotion.reduced : CharakMotion.exit,
    pageBuilder: (_, __, ___) => _CharakPhotoViewer(
      imageUrl: imageUrl,
      title: title,
      heroTag: heroTag,
      actions: actions,
    ),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: CharakCurves.standard, reverseCurve: CharakCurves.exit),
      child: child,
    ),
  ));
}

class _CharakPhotoViewer extends StatefulWidget {
  final String imageUrl;
  final String? title;
  final Object? heroTag;
  final List<CharakPhotoAction> actions;

  const _CharakPhotoViewer({
    required this.imageUrl,
    required this.title,
    required this.heroTag,
    required this.actions,
  });

  @override
  State<_CharakPhotoViewer> createState() => _CharakPhotoViewerState();
}

class _CharakPhotoViewerState extends State<_CharakPhotoViewer> with SingleTickerProviderStateMixin {
  static const _ground = CharakPalette.ink900;
  static const _onGround = CharakPalette.ink50;
  static const _zoomed = 2.5;
  static const _dismissDistance = 120.0;

  final _zoom = TransformationController();
  late final AnimationController _settle = AnimationController(vsync: this, duration: CharakMotion.standard);
  Animation<Matrix4>? _zoomAnim;
  Offset? _doubleTapAt;
  double _drag = 0;
  bool _busy = false;

  bool get _isZoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      final a = _zoomAnim;
      if (a != null) _zoom.value = a.value;
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final at = _doubleTapAt ?? Offset.zero;
    final Matrix4 target;
    if (_isZoomed) {
      target = Matrix4.identity();
    } else {
      // Zoom in around the point that was tapped.
      target = Matrix4.identity()
        ..translateByDouble(-at.dx * (_zoomed - 1), -at.dy * (_zoomed - 1), 0, 1)
        ..scaleByDouble(_zoomed, _zoomed, 1, 1);
    }
    if (charakReduceMotion(context)) {
      _zoom.value = target;
      return;
    }
    _zoomAnim = Matrix4Tween(begin: _zoom.value, end: target)
        .animate(CurvedAnimation(parent: _settle, curve: CharakCurves.standard));
    _settle.forward(from: 0);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_isZoomed) return;
    setState(() => _drag = math.max(0, _drag + d.delta.dy));
  }

  void _onDragEnd(DragEndDetails d) {
    if (_isZoomed) return;
    if (_drag > _dismissDistance || (d.primaryVelocity ?? 0) > 900) {
      Navigator.of(context).pop();
    } else {
      setState(() => _drag = 0);
    }
  }

  Future<void> _run(CharakPhotoAction a) async {
    setState(() => _busy = true);
    try {
      await a.onPressed(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fade = (1 - _drag / (_dismissDistance * 2.5)).clamp(0.3, 1.0);
    Widget photo = Image.network(
      widget.imageUrl,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: _onGround),
              ),
            ),
      errorBuilder: (_, __, ___) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(LucideIcons.imageOff, size: 32, color: _onGround),
          const SizedBox(height: 10),
          Text("Couldn't load the photo", style: CharakText.body.copyWith(color: _onGround)),
        ]),
      ),
    );
    if (widget.heroTag != null) photo = Hero(tag: widget.heroTag!, child: photo);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: _ground.withValues(alpha: fade),
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
              onDoubleTap: _toggleZoom,
              child: AnimatedContainer(
                duration: _drag == 0 ? CharakMotion.standard : Duration.zero,
                curve: CharakCurves.standard,
                transform: Matrix4.translationValues(0, _drag, 0),
                child: InteractiveViewer(
                  transformationController: _zoom,
                  minScale: 1,
                  maxScale: 4,
                  child: Center(child: photo),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Opacity(
              opacity: fade,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_ground.withValues(alpha: 0.85), _ground.withValues(alpha: 0)],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 16),
                    child: Row(children: [
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x, color: _onGround),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CharakText.titleSmall.copyWith(color: _onGround),
                        ),
                      ),
                      for (final a in widget.actions)
                        _busy
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: _onGround),
                                ),
                              )
                            : IconButton(
                                tooltip: a.label,
                                onPressed: () => _run(a),
                                icon: Icon(a.icon, color: _onGround),
                              ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

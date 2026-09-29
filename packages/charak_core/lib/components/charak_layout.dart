import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import 'charak_controls.dart';
import 'charak_screen_header.dart';
import 'charak_topbar.dart';

// ───────────────────── large title → app bar ───────────────────────────────

/// The main-screen layout: "Look up top, reach down low".
///
/// A big header ([CharakScreenHeader]) fills the top third. As you scroll it
/// fades and drifts up at 0.35× speed, and between 170 and 230px a slim bar
/// fades in with the small title on frosted glass (motion.header, linear and
/// tied to scroll). Content below enters with the stagger (lift 20px, 40ms
/// apart, max 6).
///
/// Every tab-root screen in both apps uses this.
class CharakLargeTitleScaffold extends StatefulWidget {
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Color? subtitleColor;
  final bool display;

  /// Small title for the collapsed bar; defaults to [title].
  final String? barTitle;

  /// Round actions at the top right (bell, avatar).
  final List<Widget> actions;

  /// Show a back button in the bar (pushed screens that want a big header).
  final bool showBack;

  /// Body content, laid out in a column with the screen gutter and staggered in.
  final List<Widget> children;

  /// Use instead of [children] for long, lazily built lists.
  final List<Widget>? slivers;

  final Future<void> Function()? onRefresh;

  /// Floats above the bottom edge (the Now Bar).
  final Widget? floating;

  /// Pinned under the content (a [CharakCtaBar]).
  final Widget? bottom;

  final EdgeInsets padding;

  const CharakLargeTitleScaffold({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.subtitleColor,
    this.display = false,
    this.barTitle,
    this.actions = const [],
    this.showBack = false,
    this.children = const [],
    this.slivers,
    this.onRefresh,
    this.floating,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(CharakSpacing.gutter, 0, CharakSpacing.gutter, 120),
  });

  @override
  State<CharakLargeTitleScaffold> createState() => _CharakLargeTitleScaffoldState();
}

class _CharakLargeTitleScaffoldState extends State<CharakLargeTitleScaffold> {
  final _scroll = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final o = _scroll.hasClients ? _scroll.offset : 0.0;
      if ((o - _offset).abs() > 0.5) setState(() => _offset = o);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const barH = 56.0;
    final bar = ((_offset - CharakMotion.headerFadeStart) /
            (CharakMotion.headerFadeEnd - CharakMotion.headerFadeStart))
        .clamp(0.0, 1.0);
    final headerFade = (1 - _offset / CharakMotion.headerFadeEnd).clamp(0.0, 1.0);

    final header = Opacity(
      opacity: headerFade,
      child: Transform.translate(
        offset: Offset(0, -_offset.clamp(0.0, 400.0) * CharakMotion.headerParallax),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 36, CharakSpacing.gutter, 20),
          child: CharakScreenHeader(
            title: widget.title,
            eyebrow: widget.eyebrow,
            subtitle: widget.subtitle,
            subtitleColor: widget.subtitleColor,
            display: widget.display,
          ),
        ),
      ),
    );

    Widget scroll = CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top + barH)),
        SliverToBoxAdapter(child: header),
        if (widget.slivers != null)
          ...widget.slivers!
        else
          SliverPadding(
            padding: widget.padding,
            sliver: SliverToBoxAdapter(child: CharakStaggerIn(children: widget.children)),
          ),
      ],
    );
    if (widget.onRefresh != null) {
      scroll = RefreshIndicator(
        onRefresh: widget.onRefresh!,
        color: CharakColors.primary,
        backgroundColor: CharakColors.card,
        edgeOffset: top + barH,
        child: scroll,
      );
    }

    final topBar = ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20 * bar, sigmaY: 20 * bar),
        child: Container(
          height: top + barH,
          padding: EdgeInsets.fromLTRB(12, top, 12, 0),
          color: CharakColors.ground.withValues(alpha: 0.85 * bar),
          child: Row(
            children: [
              if (widget.showBack)
                CharakRoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  semanticLabel: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Opacity(
                  opacity: bar,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - bar)),
                    child: Text(
                      widget.barTitle ?? widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CharakText.titleSmall.copyWith(fontSize: 18, color: CharakColors.ink),
                    ),
                  ),
                ),
              ),
              for (final a in widget.actions) ...[const SizedBox(width: 8), a],
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: CharakColors.ground,
      body: Stack(
        children: [
          Positioned.fill(child: scroll),
          Positioned(left: 0, right: 0, top: 0, child: topBar),
          if (widget.floating != null)
            Positioned(left: 12, right: 12, bottom: 12, child: widget.floating!),
        ],
      ),
      bottomNavigationBar: widget.bottom,
    );
  }
}

// ───────────────────── grouped list ────────────────────────────────────────

/// One UI grouped list: an overline label, then its rows inside one flat
/// 26px block. Put [CharakListRow]s (mark the final one `last: true`) or
/// switch rows inside.
class CharakGroupedList extends StatelessWidget {
  final String? label;
  final List<Widget> children;

  const CharakGroupedList({super.key, this.label, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: CharakSectionTitle(label: label!),
        ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: CharakSpacing.gutter),
        decoration: BoxDecoration(
          color: CharakColors.card,
          borderRadius: const BorderRadius.all(CharakRadius.card),
        ),
        child: Column(children: children),
      ),
    ],
  );
}

// ───────────────────── section header ──────────────────────────────────────

/// "Find care ········ See all": a wide title.small with an optional blue
/// text action.
class CharakSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const CharakSectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: Text(title, style: CharakText.titleSmall.copyWith(fontSize: 22, color: CharakColors.ink))),
      if (actionLabel != null)
        CharakPressable(
          onTap: onAction,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Text(actionLabel!, style: CharakText.label.copyWith(fontSize: 16, color: CharakColors.primary)),
          ),
        ),
    ],
  );
}

// ───────────────────── specialty tile ──────────────────────────────────────

/// Specialty tile: a 20px-radius tonal block with an icon top-left and the
/// name bottom-left. [toneIndex] picks from [CharakTileTones] (general,
/// paediatrics, cardiology, ayurveda, skin, ortho).
class CharakSpecialtyTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final int toneIndex;
  final VoidCallback? onTap;
  final double height;

  const CharakSpecialtyTile({
    super.key,
    required this.label,
    required this.icon,
    this.toneIndex = 0,
    this.onTap,
    this.height = 96,
  });

  static (Color, Color) toneFor(int i) {
    final (bg, fg) = CharakTileTones.all[i % CharakTileTones.all.length];
    if (!CharakColors.isInk) return (bg, fg);
    return (CharakColors.card, fg == CharakTileTones.ortho.$2 ? CharakColors.ink : bg);
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneFor(toneIndex);
    return CharakPressable(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(CharakRadius.tile)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 24, color: fg),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CharakText.label.copyWith(fontSize: 15, color: fg)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────── search bar ──────────────────────────────────────────

/// Pill search field (56px) on a card surface, with an optional round voice
/// button. Tapping it when [onTap] is set opens search instead of focusing.
class CharakSearchBar extends StatelessWidget {
  final String placeholder;
  final VoidCallback? onTap;
  final VoidCallback? onVoice;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  const CharakSearchBar({
    super.key,
    this.placeholder = 'Doctors, symptoms, specialties',
    this.onTap,
    this.onVoice,
    this.controller,
    this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final field = onTap != null
        ? Text(placeholder, style: CharakText.body.copyWith(color: CharakColors.inkFaint))
        : TextField(
            controller: controller,
            onChanged: onChanged,
            autofocus: autofocus,
            cursorColor: CharakColors.primary,
            style: CharakText.body.copyWith(color: CharakColors.ink),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: placeholder,
              hintStyle: CharakText.body.copyWith(color: CharakColors.inkFaint),
            ),
          );
    final bar = Container(
      height: 56,
      padding: EdgeInsets.fromLTRB(20, 0, onVoice != null ? 8 : 20, 0),
      decoration: BoxDecoration(color: CharakColors.card, borderRadius: const BorderRadius.all(CharakRadius.pill)),
      child: Row(children: [
        Icon(Icons.search_rounded, size: 22, color: CharakColors.inkMuted),
        const SizedBox(width: 12),
        Expanded(child: field),
        if (onVoice != null)
          CharakPressable(
            onTap: onVoice,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: CharakColors.primarySoft, shape: BoxShape.circle),
              child: Icon(Icons.mic_none_rounded, size: 20, color: CharakColors.primaryDeep),
            ),
          ),
      ]),
    );
    return onTap != null ? CharakPressable(onTap: onTap, child: bar) : bar;
  }
}

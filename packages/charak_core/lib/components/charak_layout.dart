import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import 'charak_controls.dart';
import 'charak_screen_header.dart';
import 'charak_topbar.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  final Color? eyebrowColor;
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
    this.eyebrowColor,
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

  /// The scroll offset, for the header and bar alone: scrolling rebuilds
  /// those two, not the scroll view and everything in it.
  final _offset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final o = _scroll.hasClients ? _scroll.offset : 0.0;
      if ((o - _offset.value).abs() > 0.5) _offset.value = o;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    // What overlays the bottom: the floating tab bar (a shell with
    // `extendBody`) or the system gesture area. Content scrolls clear of it
    // and the Now Bar floats above it.
    final under = MediaQuery.paddingOf(context).bottom;
    const barH = 56.0;

    final header = ValueListenableBuilder<double>(
      valueListenable: _offset,
      builder: (_, offset, child) => Opacity(
        opacity: (1 - offset / CharakMotion.headerFadeEnd).clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -offset.clamp(0.0, 400.0) * CharakMotion.headerParallax),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 36, CharakSpacing.gutter, 20),
        child: CharakScreenHeader(
          title: widget.title,
          eyebrow: widget.eyebrow,
          eyebrowColor: widget.eyebrowColor,
          subtitle: widget.subtitle,
          subtitleColor: widget.subtitleColor,
          display: widget.display,
        ),
      ),
    );

    Widget scroll = CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top + barH)),
        SliverToBoxAdapter(child: header),
        if (widget.slivers != null) ...[
          ...widget.slivers!,
          SliverToBoxAdapter(child: SizedBox(height: under)),
        ] else
          SliverPadding(
            padding: widget.padding + EdgeInsets.only(bottom: under),
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

    final topBar = ValueListenableBuilder<double>(
      valueListenable: _offset,
      builder: (context, offset, _) {
        final bar = ((offset - CharakMotion.headerFadeStart) /
                (CharakMotion.headerFadeEnd - CharakMotion.headerFadeStart))
            .clamp(0.0, 1.0);
        return ClipRect(
          child: BackdropFilter(
            // A zero blur still costs a backdrop layer every frame; with the
            // bar fully transparent there is nothing to frost.
            enabled: bar > 0,
            filter: ImageFilter.blur(sigmaX: 20 * bar, sigmaY: 20 * bar),
            child: Container(
              height: top + barH,
              padding: EdgeInsets.fromLTRB(12, top, 12, 0),
              color: CharakColors.ground.withValues(alpha: 0.85 * bar),
              child: Row(
                children: [
                  if (widget.showBack)
                    CharakRoundIconButton(
                      icon: LucideIcons.arrowLeft,
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
      },
    );

    return Scaffold(
      backgroundColor: CharakColors.ground,
      body: Stack(
        children: [
          Positioned.fill(child: scroll),
          Positioned(left: 0, right: 0, top: 0, child: topBar),
          if (widget.floating != null)
            Positioned(left: 12, right: 12, bottom: 12 + under, child: widget.floating!),
        ],
      ),
      bottomNavigationBar: widget.bottom,
    );
  }
}

// ───────────────────── pushed screen ───────────────────────────────────────

/// Every pushed screen: a back button on top, then the screen's big title in
/// the top third, then its content; actions sit in [bottom] (a
/// [CharakCtaBar]). As the content scrolls the title fades up and reappears
/// small in a frosted bar — the same motion as the tab roots
/// ([CharakLargeTitleScaffold]), so every screen in both apps reads alike.
///
/// [body] keeps its own scrolling (a ListView, a form): it runs inside a
/// nested scroll view whose header is the title, so the title scrolls away
/// first and the body continues. Leave [title] null for screens whose content
/// is itself the headline (an outcome state, a call).
class CharakScreen extends StatefulWidget {
  final String? title;
  final String? eyebrow;
  final String? subtitle;

  /// Small title for the collapsed bar; defaults to [title].
  final String? barTitle;

  final Widget body;

  /// Pinned under the content (a [CharakCtaBar]).
  final Widget? bottom;

  /// Round actions at the top right.
  final List<Widget> actions;
  final VoidCallback? onBack;

  const CharakScreen({
    super.key,
    this.title,
    this.eyebrow,
    this.subtitle,
    this.barTitle,
    required this.body,
    this.bottom,
    this.actions = const [],
    this.onBack,
  });

  @override
  State<CharakScreen> createState() => _CharakScreenState();
}

class _CharakScreenState extends State<CharakScreen> {
  static const _barH = 56.0;
  final _outer = ScrollController();

  /// The outer scroll offset, for the header and bar alone (see
  /// [_CharakLargeTitleScaffoldState._offset]).
  final _offset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _outer.addListener(() {
      final o = _outer.offset;
      if ((o - _offset.value).abs() > 0.5 || o <= 0) _offset.value = o;
    });
  }

  @override
  void dispose() {
    _outer.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final hasTitle = widget.title != null && widget.title!.isNotEmpty;

    final scroll = NestedScrollView(
      controller: _outer,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      headerSliverBuilder: (context, _) => [
        SliverToBoxAdapter(child: SizedBox(height: top + _barH)),
        if (hasTitle)
          SliverToBoxAdapter(
            child: ValueListenableBuilder<double>(
              valueListenable: _offset,
              builder: (_, offset, child) => Opacity(
                opacity: (1 - offset / 72).clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, -offset.clamp(0.0, 200.0) * CharakMotion.headerParallax),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 12, CharakSpacing.gutter, 18),
                child: CharakScreenHeader(
                  title: widget.title!,
                  eyebrow: widget.eyebrow,
                  subtitle: widget.subtitle,
                ),
              ),
            ),
          ),
      ],
      body: widget.body,
    );

    final topBar = ValueListenableBuilder<double>(
      valueListenable: _offset,
      builder: (context, offset, _) {
        // Pushed headers are shorter than tab roots', so the fold happens sooner.
        final bar = hasTitle ? ((offset - 24) / 48).clamp(0.0, 1.0) : 0.0;
        return ClipRect(
          child: BackdropFilter(
            // No blur to draw until the bar starts to fold in (and never on a
            // screen without a title, where the bar is solid).
            enabled: bar > 0,
            filter: ImageFilter.blur(sigmaX: 20 * bar, sigmaY: 20 * bar),
            child: Container(
              height: top + _barH,
              padding: EdgeInsets.fromLTRB(12, top, 12, 0),
              color: CharakColors.ground.withValues(alpha: hasTitle ? 0.85 * bar : 1),
              child: Row(
                children: [
                  CharakRoundIconButton(
                    icon: LucideIcons.arrowLeft,
                    semanticLabel: 'Back',
                    onTap: widget.onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Opacity(
                      opacity: bar,
                      child: Transform.translate(
                        offset: Offset(0, 8 * (1 - bar)),
                        child: Text(
                          widget.barTitle ?? widget.title ?? '',
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
      },
    );

    return Scaffold(
      backgroundColor: CharakColors.ground,
      body: Stack(
        children: [
          Positioned.fill(child: scroll),
          Positioned(left: 0, right: 0, top: 0, child: topBar),
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
  Widget build(BuildContext context) => CharakRiseIn(child: _body(context));

  Widget _body(BuildContext context) => Column(
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

// ───────────────────── spot mark ───────────────────────────────────────────

/// The Charak spot: a line glyph over a soft tonal disc, set off-centre so the
/// two overlap like a two-colour print. It is the patient app's mark for a
/// kind of care: one per specialty and per way of being seen, never inside a
/// boxed badge. [toneIndex] picks from [CharakTileTones].
class CharakSpot extends StatelessWidget {
  final IconData icon;
  final int toneIndex;
  final double size;

  const CharakSpot({super.key, required this.icon, this.toneIndex = 0, this.size = 44});

  /// (disc, glyph) for a tone on the current scheme. On ink the disc is the
  /// tone's light colour, translucent, and the glyph is that light colour.
  static (Color, Color) colors(int toneIndex) {
    final i = toneIndex % CharakTileTones.all.length;
    final (bg, fg) = CharakTileTones.all[i];
    if (CharakColors.isInk) {
      final light = fg == CharakTileTones.ortho.$2 ? CharakPalette.ink100 : bg;
      return (CharakTileTones.spots[i].withValues(alpha: 0.24), light);
    }
    return (CharakTileTones.spots[i], fg);
  }

  @override
  Widget build(BuildContext context) {
    final (disc, glyph) = colors(toneIndex);
    // The disc sits up and left, the glyph down and right, overlapping by
    // about half, so they read as one mark rather than a ball and an icon.
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Positioned(
          left: 0,
          top: 0,
          child: Container(
            width: size * 0.7,
            height: size * 0.7,
            decoration: BoxDecoration(color: disc, shape: BoxShape.circle),
          ),
        ),
        Positioned(
          right: size * 0.02,
          bottom: size * 0.02,
          child: Icon(icon, size: size * 0.66, color: glyph),
        ),
      ]),
    );
  }
}

// ───────────────────── care grid ───────────────────────────────────────────

/// One kind of care in a [CharakSpecialtyGrid]: a card with its [CharakSpot],
/// the name, and an optional [hint] in plain words ("Fever, cough, BP,
/// sugar"), since patients look for a symptom more often than a specialty.
class CharakSpecialtyTile extends StatelessWidget {
  final String label;
  final String? hint;
  final IconData icon;
  final int toneIndex;
  final VoidCallback? onTap;

  const CharakSpecialtyTile({
    super.key,
    required this.label,
    required this.icon,
    this.hint,
    this.toneIndex = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => _CareCell(tile: this, prominent: false);
}

class _CareCell extends StatelessWidget {
  final CharakSpecialtyTile tile;
  final bool prominent;
  const _CareCell({required this.tile, required this.prominent});

  @override
  Widget build(BuildContext context) {
    final hint = tile.hint;
    return Semantics(
      button: tile.onTap != null,
      label: hint == null ? tile.label : '${tile.label}. $hint',
      excludeSemantics: true,
      child: CharakPressable(
        onTap: tile.onTap,
        child: Container(
          padding: prominent ? const EdgeInsets.fromLTRB(18, 18, 14, 18) : const EdgeInsets.fromLTRB(14, 14, 12, 16),
          decoration: BoxDecoration(
            color: CharakColors.card,
            borderRadius: BorderRadius.all(prominent ? CharakRadius.card : CharakRadius.tile),
            boxShadow: CharakShadows.card,
          ),
          child: prominent || hint == null ? _named(hint) : _symptomFirst(hint),
        ),
      ),
    );
  }

  /// The way of being seen (and a tile without a hint): mark, name, hint.
  Widget _named(String? hint) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CharakSpot(icon: tile.icon, toneIndex: tile.toneIndex, size: prominent ? 52 : 40),
            const Spacer(),
            // Blue acts: the two ways of being seen are the page's first
            // choice, and say so.
            if (prominent)
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: CharakColors.primarySoft, shape: BoxShape.circle),
                child: Icon(LucideIcons.arrowUpRight, size: 16, color: CharakColors.primaryDeep),
              ),
          ]),
          SizedBox(height: prominent ? 18 : 14),
          Text(
            tile.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: prominent
                ? CharakText.titleSmall.copyWith(fontSize: 19, color: CharakColors.ink)
                : CharakText.label.weight(650).copyWith(fontSize: 16, height: 1.2, color: CharakColors.ink),
          ),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(
              hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CharakText.caption.copyWith(color: CharakColors.inkMuted, height: 1.35),
            ),
          ],
        ],
      );

  /// A specialty, the way Apple Health labels a category: the mark and the
  /// specialty's name small, in its tone, on top; what it treats large
  /// underneath. People look for their problem ("Fever, cough") more often
  /// than for a specialty's name.
  Widget _symptomFirst(String hint) {
    final (_, tone) = CharakSpot.colors(tile.toneIndex);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          CharakSpot(icon: tile.icon, toneIndex: tile.toneIndex, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tile.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CharakText.label.weight(650).copyWith(fontSize: 14, height: 1.15, color: tone),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text(
          hint,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: CharakText.label.weight(650).copyWith(fontSize: 18, height: 1.2, color: CharakColors.ink),
        ),
      ],
    );
  }
}

/// Kinds of care, two to a row, each its own lifted card (r20, the soft
/// [CharakShadows.card], 10px apart) so
/// every choice is clearly its own target. Each row takes the height of its
/// taller card, so a two-line hint or a large system font never clips and
/// the rows stay even. [prominent] is for the first choice on Home (home
/// visit or online): r26 cards, bigger spots, the name in the wide title
/// face, and a blue arrow, since that pair is what most people tap.
class CharakSpecialtyGrid extends StatelessWidget {
  final List<CharakSpecialtyTile> tiles;
  final bool prominent;
  const CharakSpecialtyGrid({super.key, required this.tiles, this.prominent = false});

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) => CharakRiseIn(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tiles.length; i += 2) ...[
              if (i > 0) const SizedBox(height: _gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _CareCell(tile: tiles[i], prominent: prominent)),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: i + 1 < tiles.length
                          ? _CareCell(tile: tiles[i + 1], prominent: prominent)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

// ───────────────────── search bar ──────────────────────────────────────────

/// Pill search field (56px) on a lifted card surface ([CharakShadows.card]),
/// with an optional round voice
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
  Widget build(BuildContext context) => CharakRiseIn(child: _body(context));

  Widget _body(BuildContext context) {
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
      decoration: BoxDecoration(
        color: CharakColors.card,
        borderRadius: const BorderRadius.all(CharakRadius.pill),
        boxShadow: CharakShadows.card,
      ),
      child: Row(children: [
        Icon(LucideIcons.search, size: 22, color: CharakColors.inkMuted),
        const SizedBox(width: 12),
        Expanded(child: field),
        if (onVoice != null)
          CharakPressable(
            onTap: onVoice,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: CharakColors.primarySoft, shape: BoxShape.circle),
              child: Icon(LucideIcons.mic, size: 20, color: CharakColors.primaryDeep),
            ),
          ),
      ]),
    );
    return onTap != null ? CharakPressable(onTap: onTap, child: bar) : bar;
  }
}

import 'package:flutter/material.dart';

import 'design/tokens.dart';

/// One block of a legal document's text.
@immutable
class CharakLegalBlock {
  /// `h2`, `h3`, `p`, `ul`, `ol` or `table`.
  final String kind;

  /// The text of a heading or paragraph.
  final String text;

  /// List items, or table rows as two cells each (the header row first).
  final List<List<String>> rows;

  const CharakLegalBlock(this.kind, {this.text = '', this.rows = const []});
}

/// Renders the text of a legal document (legal_documents.body, migration
/// 0030): `##` and `###` headings, paragraphs, `- ` and `1. ` lists, two-column
/// tables, and **bold** / *italic*. That is all docs/legal/publish.py lets a
/// document use, so nothing reaches a phone as raw markdown.
class CharakLegalText extends StatelessWidget {
  final String body;
  const CharakLegalText({super.key, required this.body});

  /// The blocks in [body], in order.
  @visibleForTesting
  static List<CharakLegalBlock> parse(String body) {
    final blocks = <CharakLegalBlock>[];
    final para = <String>[];
    List<List<String>>? list;
    String? listKind;
    List<List<String>>? table;

    void flush() {
      if (para.isNotEmpty) {
        blocks.add(CharakLegalBlock('p', text: para.join(' ')));
        para.clear();
      }
      if (list != null) {
        blocks.add(CharakLegalBlock(listKind!, rows: list!));
        list = null;
        listKind = null;
      }
      if (table != null) {
        blocks.add(CharakLegalBlock('table', rows: table!));
        table = null;
      }
    }

    for (final raw in body.split('\n')) {
      final line = raw.trimRight();
      final numbered = RegExp(r'^\d+\. (.*)$').firstMatch(line);
      if (line.isEmpty) {
        flush();
      } else if (line.startsWith('### ')) {
        flush();
        blocks.add(CharakLegalBlock('h3', text: line.substring(4)));
      } else if (line.startsWith('## ')) {
        flush();
        blocks.add(CharakLegalBlock('h2', text: line.substring(3)));
      } else if (line.startsWith('- ') || numbered != null) {
        final kind = numbered != null ? 'ol' : 'ul';
        if (listKind != kind) {
          flush();
          list = [];
          listKind = kind;
        }
        list!.add([numbered?.group(1) ?? line.substring(2)]);
      } else if (line.startsWith('|') && line.endsWith('|')) {
        final cells = line.substring(1, line.length - 1).split('|').map((c) => c.trim()).toList();
        if (cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c))) continue; // the |---|---| rule
        if (table == null) {
          flush();
          table = [];
        }
        table!.add(cells);
      } else if (list != null) {
        // A wrapped list item continues on the next line.
        list!.last[0] = '${list!.last[0]} ${line.trimLeft()}';
      } else {
        para.add(line);
      }
    }
    flush();
    return blocks;
  }

  /// **bold** and *italic* runs, in [base].
  static TextSpan inline(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
    var at = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(m.group(1) != null
          ? TextSpan(text: m.group(1), style: base.weight(600))
          : TextSpan(text: m.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: base, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final text = CharakText.body.copyWith(color: CharakColors.ink, height: 1.6);
    final muted = text.copyWith(color: CharakColors.inkMuted);
    final children = <Widget>[];
    for (final b in parse(body)) {
      switch (b.kind) {
        case 'h2':
          children.add(Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 28, bottom: 10),
            child: Semantics(
              header: true,
              child: Text(b.text, style: CharakText.titleSmall.copyWith(color: CharakColors.ink)),
            ),
          ));
        case 'h3':
          children.add(Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8),
            child: Semantics(
              header: true,
              child: Text(b.text, style: CharakText.label.weight(650).copyWith(color: CharakColors.ink)),
            ),
          ));
        case 'p':
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text.rich(inline(b.text, text)),
          ));
        case 'ul' || 'ol':
          for (var i = 0; i < b.rows.length; i++) {
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 24,
                  child: b.kind == 'ol'
                      ? Text('${i + 1}.', style: muted.tabular)
                      : Padding(
                          padding: const EdgeInsets.only(top: 9, left: 4),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: CharakColors.inkFaint, shape: BoxShape.circle),
                          ),
                        ),
                ),
                Expanded(child: Text.rich(inline(b.rows[i].first, text))),
              ]),
            ));
          }
          children.add(const SizedBox(height: 4));
        case 'table':
          children.add(_Table(rows: b.rows, text: text, muted: muted));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// A two-column table, stacked so it reads on a phone: the first column as a
/// label, the second under it. The header row names the columns, so it isn't
/// repeated on every row.
class _Table extends StatelessWidget {
  final List<List<String>> rows;
  final TextStyle text;
  final TextStyle muted;
  const _Table({required this.rows, required this.text, required this.muted});

  @override
  Widget build(BuildContext context) {
    final body = rows.length > 1 ? rows.sublist(1) : rows;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 16),
      decoration: BoxDecoration(
        color: CharakColors.bgSubtle,
        borderRadius: const BorderRadius.all(CharakRadius.tile),
      ),
      child: Column(children: [
        for (var i = 0; i < body.length; i++)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: i == 0
                ? null
                : BoxDecoration(border: Border(top: BorderSide(color: CharakColors.border))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(CharakLegalText.inline(body[i].first, text.weight(600))),
              if (body[i].length > 1) ...[
                const SizedBox(height: 2),
                Text.rich(CharakLegalText.inline(body[i][1], muted)),
              ],
            ]),
          ),
      ]),
    );
  }
}

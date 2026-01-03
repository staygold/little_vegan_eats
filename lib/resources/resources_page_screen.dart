// lib/resources/resources_page_screen.dart
import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/sub_header_bar.dart';
import 'resource.dart';

class ResourcePageScreen extends StatelessWidget {
  // ✅ Either provide a Resource OR provide title/body
  final Resource? resource;
  final String? title;
  final String? body;

  const ResourcePageScreen._({
    super.key,
    required this.resource,
    required this.title,
    required this.body,
  });

  // ✅ For dynamic WP resources
  factory ResourcePageScreen.fromResource({
    Key? key,
    required Resource resource,
  }) {
    return ResourcePageScreen._(
      key: key,
      resource: resource,
      title: null,
      body: null,
    );
  }

  // ✅ For placeholders / static pages
  factory ResourcePageScreen.fromText({
    Key? key,
    required String title,
    required String body,
  }) {
    return ResourcePageScreen._(
      key: key,
      resource: null,
      title: title,
      body: body,
    );
  }

  static const Color _bg = Color(0xFFECF3F4);
  static const Color _ink = Color(0xFF044246);
  static const Color _sub = Color(0xFF3A6A67);
  static const Color _panel = Color(0xFFDCEEEA);

  @override
  Widget build(BuildContext context) {
    final pageTitle = resource?.title ?? (title ?? '');
    final contentHtml = resource?.contentHtml ?? (body ?? '');

    final acf = resource?.acf ?? const <String, dynamic>{};
    final layoutMode = (acf['layout_mode'] ?? 'simple').toString();

    // ✅ ACF fields (all optional)
    final heroSubtitle = (acf['hero_subtitle'] ?? '').toString().trim();

    // ✅ Section titles NOT hardcoded
    final tilesTitle = (acf['tiles_title'] ?? '').toString().trim();
    final cardsTitle = (acf['card_grid_section_title'] ?? '').toString().trim();

    // ✅ Card grid inner title/intro
    final cardGridTitle = (acf['card_grid_title'] ?? '').toString().trim();
    final cardGridIntro = (acf['card_grid_intro'] ?? '').toString().trim();

    final sourceUrl = (acf['source_url'] ?? '').toString().trim();

    // ACF Free name mismatch safety: tiles_row vs titles_row
    final tilesRaw = (acf['tiles_row'] ?? acf['titles_row'] ?? '').toString();

    final calloutTitle = (acf['callout_title'] ?? '').toString();
    final calloutItemsRaw = (acf['callout_items'] ?? '').toString();

    // ✅ JSON uses card_grid_rows (fallback to card_grid)
    final cardGridRaw = (acf['card_grid_rows'] ?? acf['card_grid'] ?? '').toString();

    final legendComplete = (acf['legend_complete'] ?? 'Complete protein').toString();
    final legendIncomplete = (acf['legend_incomplete'] ?? 'Incomplete protein').toString();

    final tiles = _parsePipe3Lines(tilesRaw);
    final calloutItems = _parseLines(calloutItemsRaw);
    final cards = _parseCards(cardGridRaw);

    final hasEnhanced = resource != null &&
        layoutMode == 'enhanced' &&
        (tiles.isNotEmpty ||
            calloutItems.isNotEmpty ||
            cards.isNotEmpty ||
            heroSubtitle.isNotEmpty ||
            tilesTitle.isNotEmpty ||
            cardsTitle.isNotEmpty ||
            cardGridTitle.isNotEmpty ||
            cardGridIntro.isNotEmpty ||
            sourceUrl.isNotEmpty);

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          SubHeaderBar(
            title: pageTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Text(
                  pageTitle.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontVariations: [FontVariation('wght', 900)],
                    letterSpacing: 0.8,
                    color: _ink,
                  ),
                ),

                if (heroSubtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    heroSubtitle,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontVariations: [FontVariation('wght', 600)],
                      height: 1.35,
                      color: _sub,
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ✅ Simple pages: paragraph + UL get styled automatically
                ..._renderSimpleHtml(contentHtml),

                if (hasEnhanced) ...[
                  const SizedBox(height: 18),

                  // ✅ Tiles (2 across, stacked rows)
                  if (tiles.isNotEmpty) ...[
                    if (tilesTitle.isNotEmpty) ...[
                      _SectionLabel(tilesTitle.toUpperCase()),
                      const SizedBox(height: 10),
                    ],
                    _TilesGrid(tiles: tiles),
                    const SizedBox(height: 12),

                    // ✅ SOURCE URL moved under tiles
                    if (sourceUrl.isNotEmpty) ...[
                      _SourceUrlBox(url: sourceUrl),
                      const SizedBox(height: 16),
                    ],
                  ] else ...[
                    // If no tiles, still show sourceUrl if present
                    if (sourceUrl.isNotEmpty) ...[
                      _SourceUrlBox(url: sourceUrl),
                      const SizedBox(height: 16),
                    ],
                  ],

                  // ✅ Callout
                  if (calloutTitle.trim().isNotEmpty || calloutItems.isNotEmpty) ...[
                    _CalloutBox(
                      title: calloutTitle.trim().isEmpty ? null : calloutTitle.trim(),
                      items: calloutItems,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ✅ Card grid + title/intro (one per row)
                  if (cards.isNotEmpty || cardGridTitle.isNotEmpty || cardGridIntro.isNotEmpty) ...[
                    if (cardsTitle.isNotEmpty) ...[
                      _SectionLabel(cardsTitle.toUpperCase()),
                      const SizedBox(height: 10),
                    ],

                    // ⚠️ Prevent duplicate headings:
                    // If you want a big sentence like in your screenshot, use card_grid_title.
                    // If you also set cardsTitle, cardsTitle acts like the small uppercase section label.
                    if (cardGridTitle.isNotEmpty) ...[
                      Text(
                        cardGridTitle,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontVariations: [FontVariation('wght', 900)],
                          height: 1.15,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (cardGridIntro.isNotEmpty) ...[
                      Text(
                        cardGridIntro,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontVariations: [FontVariation('wght', 600)],
                          height: 1.45,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (cards.isNotEmpty) ...[
                      _CardList(cards: cards),
                      const SizedBox(height: 12),
                      _LegendRow(
                        completeLabel: legendComplete,
                        incompleteLabel: legendIncomplete,
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Simple HTML renderer (paragraph + UL) ----------
  static List<Widget> _renderSimpleHtml(String html) {
    final raw = html.trim();
    if (raw.isEmpty) return const [SizedBox.shrink()];

    final looksLikeHtml = RegExp(r'<[^>]+>').hasMatch(raw);
    if (!looksLikeHtml) {
      return [_para(raw)];
    }

    String decodeEntities(String s) {
      return s
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&#8217;', "'")
          .replaceAll('&#8211;', '–')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#8220;', '"')
          .replaceAll('&#8221;', '"')
          .replaceAll('&#8230;', '…')
          .trim();
    }

    // Extract <li> items
    final liMatches = RegExp(r'<li[^>]*>([\s\S]*?)<\/li>', caseSensitive: false)
        .allMatches(raw)
        .map((m) => m.group(1) ?? '')
        .map((s) => s.replaceAll(RegExp(r'<[^>]*>'), ''))
        .map(decodeEntities)
        .where((s) => s.isNotEmpty)
        .toList();

    // Remove <ul> blocks for paragraph extraction
    final withoutUl = raw.replaceAll(
      RegExp(r'<ul[^>]*>[\s\S]*?<\/ul>', caseSensitive: false),
      '\n',
    );

    // Extract <p> blocks (or fallback to stripped text)
    final pMatches = RegExp(r'<p[^>]*>([\s\S]*?)<\/p>', caseSensitive: false)
        .allMatches(withoutUl);

    final paragraphs = <String>[];
    for (final m in pMatches) {
      final t = decodeEntities((m.group(1) ?? '').replaceAll(RegExp(r'<[^>]*>'), ''));
      if (t.isNotEmpty) paragraphs.add(t);
    }

    if (paragraphs.isEmpty) {
      final stripped = decodeEntities(withoutUl.replaceAll(RegExp(r'<[^>]*>'), ''));
      if (stripped.isNotEmpty) paragraphs.add(stripped);
    }

    final widgets = <Widget>[];

    for (int i = 0; i < paragraphs.length; i++) {
      widgets.add(_para(paragraphs[i]));
      if (i != paragraphs.length - 1) widgets.add(const SizedBox(height: 10));
    }

    if (liMatches.isNotEmpty) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(_BulletList(items: liMatches));
    }

    return widgets;
  }

  static Widget _para(String text) {
    final t = text.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Text(
      t,
      style: const TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontVariations: [FontVariation('wght', 600)],
        height: 1.45,
        color: _ink,
      ),
    );
  }

  // ---------- Parsing helpers ----------
  static bool _isInstructionLine(String l) {
    final s = l.trim().toLowerCase();
    return s.startsWith('one ') || s.startsWith('format:') || s.startsWith('example');
  }

  static List<_Tile> _parsePipe3Lines(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) => l.contains('|'))
        .where((l) => !_isInstructionLine(l))
        .map((line) {
          final parts = line.split('|').map((p) => p.trim()).toList();
          return _Tile(
            label: parts.isNotEmpty ? parts[0] : '',
            sublabel: parts.length > 1 ? parts[1] : '',
            value: parts.length > 2 ? parts[2] : '',
          );
        })
        .where((t) => t.label.isNotEmpty || t.value.isNotEmpty)
        .toList();
  }

  static List<String> _parseLines(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) => !_isInstructionLine(l))
        .toList();
  }

  static List<_CardItem> _parseCards(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) => l.contains('|'))
        .where((l) => !_isInstructionLine(l))
        .map((line) {
          final parts = line.split('|').map((p) => p.trim()).toList();
          final title = parts.isNotEmpty ? parts[0] : '';
          final value = parts.length > 1 ? parts[1] : '';
          final flag = parts.length > 2 ? parts[2].toLowerCase().trim() : '';

          // ✅ Explicit match (prevents "incomplete" accidentally reading as complete)
          final isComplete = flag == 'complete';

          return _CardItem(
            title: title,
            value: value,
            isComplete: isComplete,
          );
        })
        .where((c) => c.title.isNotEmpty)
        .toList();
  }
}

// ---------- UI bits ----------
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  static const Color _ink = Color(0xFF044246);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 13,
        fontWeight: FontWeight.w900,
        fontVariations: [FontVariation('wght', 900)],
        letterSpacing: 0.9,
        color: _ink,
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  const _BulletList({required this.items});

  static const Color _ink = Color(0xFF044246);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.map((t) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '•',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w900,
                  fontVariations: [FontVariation('wght', 900)],
                  color: _ink,
                  height: 1.2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontVariations: [FontVariation('wght', 600)],
                    height: 1.35,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _SourceUrlBox extends StatelessWidget {
  final String url;
  const _SourceUrlBox({required this.url});

  static const Color _ink = Color(0xFF044246);
  static const Color _sub = Color(0xFF3A6A67);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SOURCE',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              fontVariations: [FontVariation('wght', 900)],
              letterSpacing: 0.8,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            url,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontVariations: [FontVariation('wght', 600)],
              height: 1.35,
              color: _sub,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  final String label;
  final String sublabel;
  final String value;

  _Tile({required this.label, required this.sublabel, required this.value});
}

/// ✅ Tiles: 2 across, stacked (no carousel)
class _TilesGrid extends StatelessWidget {
  final List<_Tile> tiles;
  const _TilesGrid({required this.tiles});

  static const Color _ink = Color(0xFF044246);
  static const Color _sub = Color(0xFF3A6A67);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.95,
      ),
      itemBuilder: (context, i) {
        final t = tiles[i];
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  fontVariations: [FontVariation('wght', 900)],
                  letterSpacing: 0.7,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.sublabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontVariations: [FontVariation('wght', 600)],
                  color: _sub,
                  height: 1.15,
                ),
              ),
              const Spacer(),
              Text(
                t.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontVariations: [FontVariation('wght', 900)],
                  color: _ink,
                  height: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CalloutBox extends StatelessWidget {
  final String? title;
  final List<String> items;

  const _CalloutBox({required this.title, required this.items});

  static const Color _ink = Color(0xFF044246);
  static const Color _panel = Color(0xFFDCEEEA);

  @override
  Widget build(BuildContext context) {
    if ((title == null || title!.trim().isEmpty) && items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title!.trim().isNotEmpty) ...[
            Text(
              title!,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                fontVariations: [FontVariation('wght', 900)],
                color: _ink,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
          ],
          ...items.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '•',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w900,
                      fontVariations: [FontVariation('wght', 900)],
                      color: _ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontVariations: [FontVariation('wght', 600)],
                        height: 1.35,
                        color: _ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardItem {
  final String title;
  final String value;
  final bool isComplete;

  _CardItem({
    required this.title,
    required this.value,
    required this.isComplete,
  });
}

/// ✅ One per row. White section never “hidden”.
class _CardList extends StatelessWidget {
  final List<_CardItem> cards;
  const _CardList({required this.cards});

  static const Color _ink = Color(0xFF044246);
  static const Color _sub = Color(0xFF3A6A67);
  static const Color _headerBg = Color(0xFFDCEEEA);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          _ProteinCard(item: cards[i]),
          if (i != cards.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProteinCard extends StatelessWidget {
  final _CardItem item;
  const _ProteinCard({required this.item});

  static const Color _ink = Color(0xFF044246);
  static const Color _sub = Color(0xFF3A6A67);
  static const Color _headerBg = Color(0xFFDCEEEA);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // Header (mint)
            Container(
              width: double.infinity,
              color: _headerBg,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontVariations: [FontVariation('wght', 900)],
                        color: _ink,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ProteinIconSvg(isComplete: item.isComplete, size: 26),
                ],
              ),
            ),

            // Body (white) - always visible
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              constraints: const BoxConstraints(minHeight: 48),
              child: Text(
                item.value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontVariations: [FontVariation('wght', 600)],
                  color: _sub,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProteinIconSvg extends StatelessWidget {
  final bool isComplete;
  final double size;

  const _ProteinIconSvg({
    required this.isComplete,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final asset = isComplete
        ? 'assets/images/icons/Complete-protein.svg'
        : 'assets/images/icons/Incomplete-protein.svg';

    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String completeLabel;
  final String incompleteLabel;

  const _LegendRow({
    required this.completeLabel,
    required this.incompleteLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LegendItem(isComplete: true, text: completeLabel),
        const SizedBox(width: 14),
        _LegendItem(isComplete: false, text: incompleteLabel),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final bool isComplete;
  final String text;

  const _LegendItem({required this.isComplete, required this.text});

  static const Color _sub = Color(0xFF3A6A67);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ProteinIconSvg(isComplete: isComplete, size: 16),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontVariations: [FontVariation('wght', 600)],
            color: _sub,
          ),
        ),
      ],
    );
  }
}

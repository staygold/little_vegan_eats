import 'package:flutter/material.dart';

import 'recipe_detail_screen.dart';
import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';

class LatestRecipesPage extends StatefulWidget {
  const LatestRecipesPage({
    super.key,
    this.title = 'Latest recipes',
    required this.recipes,
    required this.favoriteIds,
    this.limit = 20,
  });

  final String title;

  /// ✅ Raw WP recipe objects OR indexed recipe objects
  final List<Map<String, dynamic>> recipes;

  final Set<int> favoriteIds;

  /// ✅ Default 20
  final int limit;

  @override
  State<LatestRecipesPage> createState() => _LatestRecipesPageState();
}

class _LatestRecipesPageState extends State<LatestRecipesPage> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return int.tryParse(v.toString().trim());
  }

  String _titleOf(Map<String, dynamic> r) {
    // Raw WP object: title.rendered
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      final s = (t['rendered'] as String).trim();
      if (s.isNotEmpty) {
        return s.replaceAll('&#038;', '&').replaceAll('&amp;', '&');
      }
    }

    // Indexed object might store a plain title
    final plain = r['title'];
    if (plain is String && plain.trim().isNotEmpty) return plain.trim();

    // Sometimes inner recipe has name
    final recipe = r['recipe'];
    if (recipe is Map) {
      final name = recipe['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    }

    return 'Untitled';
  }

  String? _thumbOf(Map<String, dynamic> r) {
    // Raw WP object: inner recipe image urls
    final recipe = r['recipe'];
    if (recipe is Map) {
      final url = (recipe['thumbnail_url'] ??
              recipe['image_url'] ??
              recipe['image_url_full'] ??
              recipe['image'])
          ?.toString();
      if (url != null && url.trim().isNotEmpty) return url.trim();
    }

    // Indexed object might store imageUrl directly
    final url2 =
        (r['imageUrl'] ?? r['image_url'] ?? r['thumb'] ?? r['thumbnail_url'])
            ?.toString();
    if (url2 != null && url2.trim().isNotEmpty) return url2.trim();

    return null;
  }

  DateTime _dateOf(Map<String, dynamic> r) {
    // Prefer modified date (newer content updates), fallback to publish date.
    final candidates = <dynamic>[
      r['modified_gmt'],
      r['modified'],
      r['date_gmt'],
      r['date'],
    ];

    // Sometimes your indexed object might keep something like updatedAt/createdAt
    candidates.addAll([r['updatedAt'], r['createdAt'], r['updated_at'], r['created_at']]);

    for (final c in candidates) {
      final dt = _parseDate(c);
      if (dt != null) return dt;
    }

    // Fallback: very old so it sinks to bottom
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;

    // epoch millis
    if (v is int) {
      // handle seconds vs millis
      if (v < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    }

    if (v is num) {
      final i = v.toInt();
      if (i < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(i * 1000, isUtc: true).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(i, isUtc: true).toLocal();
    }

    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // WordPress usually gives ISO strings like "2026-01-02T08:08:51"
    // or "...Z". DateTime.parse handles both.
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _latestBase() {
    final list = List<Map<String, dynamic>>.from(widget.recipes);

    list.sort((a, b) => _dateOf(b).compareTo(_dateOf(a))); // newest first

    final limit = widget.limit <= 0 ? 20 : widget.limit;
    if (list.length <= limit) return list;
    return list.take(limit).toList();
  }

  @override
  Widget build(BuildContext context) {
    final baseLatest = _latestBase();

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? baseLatest
        : baseLatest.where((r) {
            final title = _titleOf(r).toLowerCase();
            return title.contains(query);
          }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          SubHeaderBar(title: widget.title),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchPill(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              hintText: 'Search recipes',
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {},
              onClear: () => setState(() {}),
            ),
          ),

          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No recipes found.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withOpacity(0.55),
                            ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = filtered[i];
                      final id = _toInt(r['id']);
                      final title = _titleOf(r);
                      final thumb = _thumbOf(r);
                      final isFav = id != null && widget.favoriteIds.contains(id);

                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: id == null
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RecipeDetailScreen(id: id),
                                    ),
                                  ),
                          child: SizedBox(
                            height: 92,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 120,
                                  height: double.infinity,
                                  child: thumb == null
                                      ? Container(color: const Color(0xFFE9EFEF))
                                      : Image.network(
                                          thumb,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(color: const Color(0xFFE9EFEF)),
                                          frameBuilder: (context, child, frame, wasSyncLoaded) {
                                            if (wasSyncLoaded) return child;
                                            if (frame != null) return child;
                                            return Container(color: const Color(0xFFE9EFEF));
                                          },
                                        ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        if (isFav)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 8, top: 2),
                                            child: Icon(Icons.star_rounded, color: Colors.amber),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

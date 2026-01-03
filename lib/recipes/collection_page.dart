import 'package:flutter/material.dart';

import 'recipe_detail_screen.dart';
import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    required this.title,
    required this.collectionSlug,
    required this.collectionTermId,
    required this.recipes,
    required this.favoriteIds,
  });

  final String title;
  final String collectionSlug;
  final int collectionTermId;

  /// ✅ This can be either:
  /// - the raw WP recipe objects (with top-level id/title/recipe)
  /// - or your indexed list objects (with id/titleLower/collections/etc)
  final List<Map<String, dynamic>> recipes;

  final Set<int> favoriteIds;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
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

    // Sometimes your inner recipe has name
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
      final url =
          (recipe['thumbnail_url'] ?? recipe['image_url'] ?? recipe['image_url_full'] ?? recipe['image'])?.toString();
      if (url != null && url.trim().isNotEmpty) return url.trim();
    }

    // Indexed object might store imageUrl directly
    final url2 = (r['imageUrl'] ?? r['image_url'] ?? r['thumb'] ?? r['thumbnail_url'])?.toString();
    if (url2 != null && url2.trim().isNotEmpty) return url2.trim();

    return null;
  }

  /// ✅ Supports old + new shapes:
  /// - old: r['wprm_collections'] = [termId...]
  /// - new indexed: r['collections'] = ['slug', ...]
  /// - WPRM tags: r['tags']['wprm_collection'] = [{id/term_id/slug...}, ...]
  /// - nested tags: r['recipe']['tags']['wprm_collection'] = ...
  bool _hasCollection(Map<String, dynamic> r) {
    final termId = widget.collectionTermId;
    final slug = widget.collectionSlug.trim().toLowerCase();

    // 1) OLD SHAPE: top-level term IDs
    final v = r['wprm_collections'];
    if (v is List) {
      for (final x in v) {
        final id = _toInt(x);
        if (id != null && id == termId) return true;
      }
    }

    // 2) NEW SHAPE: indexed list might have `collections: List<String>`
    final col = r['collections'];
    if (col is List) {
      for (final x in col) {
        final s = (x ?? '').toString().trim().toLowerCase();
        if (s.isNotEmpty && s == slug) return true;
      }
    }

    // 3) TAGS SHAPE: tags.wprm_collection term maps
    bool checkTags(dynamic tags) {
      if (tags is! Map) return false;
      final list = tags['wprm_collection'] ?? tags['wprm_collections'] ?? tags['collection'] ?? tags['collections'];
      if (list is! List) return false;

      for (final item in list) {
        if (item is Map) {
          final id = _toInt(item['id'] ?? item['term_id'] ?? item['termId']);
          if (id != null && id == termId) return true;

          final s = (item['slug'] ?? '').toString().trim().toLowerCase();
          if (s.isNotEmpty && s == slug) return true;
        } else {
          // sometimes slugs are plain strings
          final s = (item ?? '').toString().trim().toLowerCase();
          if (s.isNotEmpty && s == slug) return true;
          final id = _toInt(item);
          if (id != null && id == termId) return true;
        }
      }
      return false;
    }

    // top-level tags
    if (checkTags(r['tags'])) return true;

    // inner recipe tags
    final recipe = r['recipe'];
    if (recipe is Map) {
      if (checkTags(recipe['tags'])) return true;

      // sometimes tags are nested under recipe['recipe']
      final inner = recipe['recipe'];
      if (inner is Map && checkTags(inner['tags'])) return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final baseFiltered = widget.recipes.where(_hasCollection).toList();

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? baseFiltered
        : baseFiltered.where((r) {
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
                        'No recipes found in this collection.',
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

                                  // ✅ no ugly icon; just a clean neutral block
                                  child: thumb == null
                                      ? Container(color: const Color(0xFFE9EFEF))
                                      : Image.network(
                                          thumb,
                                          fit: BoxFit.cover,
                                          // ✅ also no ugly icon on error
                                          errorBuilder: (_, __, ___) => Container(color: const Color(0xFFE9EFEF)),
                                          // ✅ no flicker fade-to-icon
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

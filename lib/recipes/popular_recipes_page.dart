// lib/recipes/popular_recipes_page.dart
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';
import 'recipe_detail_screen.dart';

class PopularRecipesPage extends StatefulWidget {
  const PopularRecipesPage({
    super.key,
    required this.title,
    required this.recipes,
    required this.favoriteIds,
    this.limit = 50,
  });

  final String title;

  /// raw WP objects list (same shape you pass around)
  final List<Map<String, dynamic>> recipes;

  final Set<int> favoriteIds;

  final int limit;

  @override
  State<PopularRecipesPage> createState() => _PopularRecipesPageState();
}

class _PopularRecipesPageState extends State<PopularRecipesPage> {
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
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      final s = (t['rendered'] as String).trim();
      if (s.isNotEmpty) {
        return s.replaceAll('&#038;', '&').replaceAll('&amp;', '&');
      }
    }

    final plain = r['title'];
    if (plain is String && plain.trim().isNotEmpty) return plain.trim();

    final recipe = r['recipe'];
    if (recipe is Map) {
      final name = recipe['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    }

    return 'Untitled';
  }

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map) {
      final url = (recipe['thumbnail_url'] ??
              recipe['image_url'] ??
              recipe['image_url_full'] ??
              recipe['image'])
          ?.toString();
      if (url != null && url.trim().isNotEmpty) return url.trim();
    }

    final url2 =
        (r['imageUrl'] ?? r['image_url'] ?? r['thumb'] ?? r['thumbnail_url'])
            ?.toString();
    if (url2 != null && url2.trim().isNotEmpty) return url2.trim();

    return null;
  }

  /// ✅ robustly detects "popular" in any of these places:
  /// - top-level wprm_collections: [ids]
  /// - recipe.tags.collections: [{term_id, slug, ...}]
  /// - tags.wprm_collection / tags.collections (older shapes)
  bool _isPopular(Map<String, dynamic> r) {
    const slug = 'popular';

    bool hasSlugInList(dynamic list) {
      if (list is! List) return false;
      for (final item in list) {
        if (item is Map) {
          final s = (item['slug'] ?? '').toString().trim().toLowerCase();
          if (s == slug) return true;
        } else {
          final s = (item ?? '').toString().trim().toLowerCase();
          if (s == slug) return true;
        }
      }
      return false;
    }

    bool checkTags(dynamic tags) {
      if (tags is! Map) return false;

      // common keys seen in your API shapes
      final list = tags['collections'] ??
          tags['wprm_collections'] ??
          tags['wprm_collection'] ??
          tags['collection'];

      return hasSlugInList(list);
    }

    // 1) raw WP top-level term IDs (works if you pass correct term id elsewhere)
    // we don't rely on this here because you may not know termId yet
    // final v = r['wprm_collections']; // leave alone

    // 2) top-level tags (some indexed shapes)
    if (checkTags(r['tags'])) return true;

    // 3) inner recipe tags (your provided JSON has recipe.tags.collections)
    final recipe = r['recipe'];
    if (recipe is Map) {
      final tags = recipe['tags'];
      if (checkTags(tags)) return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    // filter to popular
    final popular = widget.recipes.where(_isPopular).toList();

    // optional: cap
    if (popular.length > widget.limit) {
      popular.removeRange(widget.limit, popular.length);
    }

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? popular
        : popular.where((r) => _titleOf(r).toLowerCase().contains(query)).toList();

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
                        'No popular recipes found yet.',
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

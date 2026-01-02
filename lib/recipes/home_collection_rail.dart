import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';

import '../utils/images.dart'; // upscaleJetpackImage
import '../theme/app_theme.dart';
import 'recipe_detail_screen.dart';
import 'collection_page.dart';

class HomeCollectionRail extends StatefulWidget {
  const HomeCollectionRail({
    super.key,
    required this.title,
    required this.collectionSlug,
    required this.recipes,
    required this.favoriteIds,
  });

  final String title;
  final String collectionSlug; // e.g. "15-minute-meals"
  final List<Map<String, dynamic>> recipes;
  final Set<int> favoriteIds;

  @override
  State<HomeCollectionRail> createState() => _HomeCollectionRailState();
}

class _HomeCollectionRailState extends State<HomeCollectionRail> {
  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return int.tryParse('${v ?? ''}');
  }

  int? _recipeId(dynamic raw) => _toInt(raw);

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      final s = (t['rendered'] as String).trim();
      if (s.isNotEmpty) {
        return s.replaceAll('&#038;', '&').replaceAll('&amp;', '&');
      }
    }
    return 'Untitled';
  }

  String? _str(dynamic v) =>
      (v is String && v.trim().isNotEmpty) ? v.trim() : null;

  /// Same preference logic as RecipeDetailScreen:
  /// pick the biggest, then let upscaleJetpackImage size it.
  String? _bestImageUrl(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map) {
      final rm = Map<String, dynamic>.from(recipe.cast<String, dynamic>());
      return _str(rm['image_url_full']) ??
          _str(rm['image_url']) ??
          _str(rm['image']) ??
          _str(rm['thumbnail_url']);
    }
    return _str(r['jetpack_featured_media_url']);
  }

  String _slugify(String s) {
    // very lightweight slugify (good enough for matching)
    final lower = s.trim().toLowerCase();
    final cleaned = lower
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return cleaned;
  }

  bool _matchesCollectionSlug(Map<String, dynamic> r, String slug) {
    final wanted = slug.trim().toLowerCase();

    // ✅ BEST SOURCE: recipe.tags.collections[].slug
    final recipe = r['recipe'];
    if (recipe is Map) {
      final tags = recipe['tags'];
      if (tags is Map) {
        final cols = tags['collections'] ?? tags['collection'];
        if (cols is List) {
          for (final c in cols) {
            if (c is Map) {
              final cSlug = (c['slug'] ?? '').toString().trim().toLowerCase();
              if (cSlug.isNotEmpty && cSlug == wanted) return true;

              // fallback: match by name if slug missing
              final cName = (c['name'] ?? '').toString().trim().toLowerCase();
              if (cName.isNotEmpty && _slugify(cName) == wanted) return true;
            } else if (c is String) {
              final cs = c.trim().toLowerCase();
              if (cs == wanted || _slugify(cs) == wanted) return true;
            }
          }
        }
      }
    }

    // ✅ Fallback: top-level wprm_collections if it’s strings (post-normalisation)
    final v = r['wprm_collections'];
    if (v is List) {
      for (final x in v) {
        final xs = '$x'.trim().toLowerCase();
        if (xs == wanted || _slugify(xs) == wanted) return true;
      }
    }

    return false;
  }

  List<Map<String, dynamic>> _filteredRecipes() {
    if (widget.recipes.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    for (final r in widget.recipes) {
      if (_matchesCollectionSlug(r, widget.collectionSlug)) out.add(r);
    }
    return out;
  }

  Widget _skeletonRail({
    required TextStyle sectionTitleStyle,
    required double railH,
    required double cardW,
    required double titleBlockH,
    String? helper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 4, 10),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, style: sectionTitleStyle)),
            ],
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(helper, style: Theme.of(context).textTheme.bodySmall),
          ),
        SizedBox(
          height: railH,
          child: ListView.separated(
            padding: const EdgeInsets.only(left: 16, right: 12),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) {
              return SizedBox(
                width: cardW,
                height: railH,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    children: [
                      Expanded(child: Container(color: Colors.black.withOpacity(0.06))),
                      SizedBox(height: titleBlockH, child: Container(color: Colors.black.withOpacity(0.04))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final sectionTitleStyle =
        (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 1.0,
      height: 1.0,
    );

    final cardTextStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w700,
      fontSize: 16,
      height: 1.4,
    );

    final screenW = MediaQuery.of(context).size.width;
    final cardW = (screenW * 0.42).clamp(150.0, 190.0);

    const railH = 190.0;
    const titleBlockH = 68.0;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final requestW = (cardW * dpr * 2.0).round();
    final requestH = ((railH - titleBlockH) * dpr * 2.0).round();
    final cacheW = requestW;
    final cacheH = requestH;

    // ✅ If recipes haven’t loaded yet, don’t lie with “No recipes yet”
    if (widget.recipes.isEmpty) {
      return _skeletonRail(
        sectionTitleStyle: sectionTitleStyle,
        railH: railH,
        cardW: cardW,
        titleBlockH: titleBlockH,
        helper: 'Loading recipes…',
      );
    }

    final all = _filteredRecipes();
    final rail = all.take(5).toList();

    if (rail.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(
          children: [
            Expanded(child: Text(widget.title, style: sectionTitleStyle)),
            const SizedBox(width: 10),
            Text('No recipes yet', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 4, 10),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, style: sectionTitleStyle)),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CollectionPage(
                        title: widget.title,
                        collectionSlug: widget.collectionSlug,
                        // termId not required anymore for filtering,
                        // but keep it if your CollectionPage expects it.
                        // Set to 0 (or remove param if you refactor CollectionPage).
                        collectionTermId: 0,
                        recipes: widget.recipes,
                        favoriteIds: widget.favoriteIds,
                      ),
                    ),
                  );
                },
                child: Text(
                  'VIEW ALL',
                  style: (theme.textTheme.titleMedium ?? const TextStyle())
                      .copyWith(
                    color: AppColors.brandDark,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          height: railH,
          child: ListView.separated(
            padding: const EdgeInsets.only(left: 16, right: 12),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: rail.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final r = rail[i];
              final id = _recipeId(r['id']);
              final title = _titleOf(r);

              final baseUrl = _bestImageUrl(r);
              final imgUrl = baseUrl == null
                  ? null
                  : upscaleJetpackImage(baseUrl, w: requestW, h: requestH);

              final isFav = id != null && widget.favoriteIds.contains(id);

              return SizedBox(
                width: cardW,
                height: railH,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: id == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RecipeDetailScreen(id: id),
                              ),
                            ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (imgUrl == null)
                                const Center(child: Icon(Icons.restaurant_menu))
                              else
                                Image.network(
                                  imgUrl,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                  cacheWidth: cacheW,
                                  cacheHeight: cacheH,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.restaurant_menu),
                                  ),
                                ),
                              if (isFav)
                                const Positioned(
                                  right: 10,
                                  top: 10,
                                  child: Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        SizedBox(
                          height: titleBlockH,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: cardTextStyle,
                              ),
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

        const SizedBox(height: 6),
      ],
    );
  }
}

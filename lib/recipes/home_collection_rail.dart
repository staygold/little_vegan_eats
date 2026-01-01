// lib/recipes/home_collection_rail.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

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
  final String collectionSlug;
  final List<Map<String, dynamic>> recipes;
  final Set<int> favoriteIds;

  @override
  State<HomeCollectionRail> createState() => _HomeCollectionRailState();
}

class _HomeCollectionRailState extends State<HomeCollectionRail> {
  final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'LittleVeganEatsApp/1.0',
      },
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  // ✅ In-memory cache so rails feel instant after first load
  static final Map<String, int> _termIdCacheBySlug = {};
  static final Map<String, Future<int>> _inflightBySlug = {};

  // We no longer “block” UI on loading
  String? _error;
  int? _termId;

  @override
  void initState() {
    super.initState();

    final cached = _termIdCacheBySlug[widget.collectionSlug];
    if (cached != null) {
      _termId = cached;

      // ✅ Optional: silently refresh in background (no spinner)
      _refreshTermIdSilently();
    } else {
      // ✅ No cached termId yet — load without blocking UI
      _loadCollectionTermId();
    }
  }

  Future<void> _refreshTermIdSilently() async {
    try {
      final id = await _fetchTermId(widget.collectionSlug);
      if (!mounted) return;

      // Only update if it actually changed
      if (_termId != id) {
        setState(() => _termId = id);
      }
    } catch (_) {
      // silent refresh failures: ignore (don’t flash errors)
    }
  }

  Future<void> _loadCollectionTermId() async {
    setState(() {
      _error = null;
      // ✅ don’t set a “loading” state that blocks UI
    });

    try {
      final id = await _fetchTermId(widget.collectionSlug);
      if (!mounted) return;
      setState(() => _termId = id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<int> _fetchTermId(String slug) {
    // ✅ Return cache instantly if we have it
    final cached = _termIdCacheBySlug[slug];
    if (cached != null) return Future.value(cached);

    // ✅ De-dupe concurrent requests (multiple rails on one screen)
    final inflight = _inflightBySlug[slug];
    if (inflight != null) return inflight;

    final fut = () async {
      final res = await _dio.get(
        'https://littleveganeats.co/wp-json/wp/v2/wprm_collections',
        queryParameters: {
          'slug': slug,
          'per_page': 1,
        },
      );

      final data = res.data;
      if (data is! List || data.isEmpty) {
        throw Exception('Collection not found for slug "$slug"');
      }

      final obj = data.first;
      if (obj is! Map) throw Exception('Unexpected collection response shape');

      final map = Map<String, dynamic>.from(obj);
      final id = _toInt(map['id']);
      if (id == null || id <= 0) throw Exception('Collection term id missing');

      // ✅ Save in cache
      _termIdCacheBySlug[slug] = id;
      return id;
    }();

    _inflightBySlug[slug] = fut;
    fut.whenComplete(() {
      // ✅ clean up inflight map
      _inflightBySlug.remove(slug);
    });

    return fut;
  }

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

  bool _hasCollectionTerm(Map<String, dynamic> r, int termId) {
    final v = r['wprm_collections'];
    if (v is List) {
      for (final x in v) {
        final id = _toInt(x);
        if (id == termId) return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _filteredRecipes() {
    final id = _termId;
    if (id == null) return const [];
    final list = <Map<String, dynamic>>[];
    for (final r in widget.recipes) {
      if (_hasCollectionTerm(r, id)) list.add(r);
    }
    return list;
  }

  Widget _skeletonRail({
    required TextStyle sectionTitleStyle,
    required double railH,
    required double cardW,
    required double titleBlockH,
  }) {
    // ✅ Instant placeholder (no spinner)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 4, 10),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, style: sectionTitleStyle)),
              if (_error != null)
                TextButton(
                  onPressed: _loadCollectionTermId,
                  child: const Text('Retry'),
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
                      Expanded(
                        child: Container(
                          color: Colors.black.withOpacity(0.06),
                        ),
                      ),
                      SizedBox(
                        height: titleBlockH,
                        child: Container(
                          color: Colors.black.withOpacity(0.04),
                        ),
                      ),
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

    // ✅ Make cards less wide (more square / 4:3 feel)
    final screenW = MediaQuery.of(context).size.width;
    final cardW = (screenW * 0.42).clamp(150.0, 190.0);

    // Rail height: image + title block
    const railH = 190.0;

    // Title block height fixed
    const titleBlockH = 68.0;

    // Image sizing: crisp
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final requestW = (cardW * dpr * 2.0).round();
    final requestH = ((railH - titleBlockH) * dpr * 2.0).round();

    final cacheW = requestW;
    final cacheH = requestH;

    // ✅ If we don’t have the termId yet, render skeleton instantly
    if (_termId == null) {
      return _skeletonRail(
        sectionTitleStyle: sectionTitleStyle,
        railH: railH,
        cardW: cardW,
        titleBlockH: titleBlockH,
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
                  final termId = _termId!;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CollectionPage(
                        title: widget.title,
                        collectionSlug: widget.collectionSlug,
                        collectionTermId: termId,
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
                                  // ✅ prevents “pop” if image re-renders
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

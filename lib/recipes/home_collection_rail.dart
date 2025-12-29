import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../utils/images.dart'; // upscaleJetpackImage
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

  bool _loading = true;
  String? _error;
  int? _termId;

  @override
  void initState() {
    super.initState();
    _loadCollectionTermId();
  }

  Future<void> _loadCollectionTermId() async {
    setState(() {
      _loading = true;
      _error = null;
      _termId = null;
    });

    try {
      final res = await _dio.get(
        'https://littleveganeats.co/wp-json/wp/v2/wprm_collections',
        queryParameters: {
          'slug': widget.collectionSlug,
          'per_page': 1,
        },
      );

      final data = res.data;
      if (data is! List || data.isEmpty) {
        throw Exception('Collection not found for slug "${widget.collectionSlug}"');
      }

      final obj = data.first;
      if (obj is! Map) throw Exception('Unexpected collection response shape');

      final map = Map<String, dynamic>.from(obj);
      final id = _toInt(map['id']);
      if (id == null || id <= 0) throw Exception('Collection term id missing');

      if (!mounted) return;
      setState(() {
        _termId = id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int? _toInt(dynamic v) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final heading = theme.textTheme.titleMedium ??
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(
          children: [
            Expanded(child: Text(widget.title, style: heading)),
            const SizedBox(width: 10),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(
          children: [
            Expanded(child: Text('${widget.title} (couldn’t load)', style: heading)),
            TextButton(onPressed: _loadCollectionTermId, child: const Text('Retry')),
          ],
        ),
      );
    }

    final all = _filteredRecipes();
    final rail = all.take(5).toList();

    if (rail.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(
          children: [
            Expanded(child: Text(widget.title, style: heading)),
            const SizedBox(width: 10),
            Text('No recipes yet', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    // ✅ Make cards less wide (more square / 4:3 feel)
    // Aim: ~2.5 visible cards on most phones.
    final screenW = MediaQuery.of(context).size.width;
    final cardW = (screenW * 0.42).clamp(150.0, 190.0);

    // Rail height: image + title block, safe & consistent
    const railH = 190.0;

    // Title block height is fixed so we never overflow.
    const titleBlockH = 52.0;

    // Image sizing: crisp
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final requestW = (cardW * dpr * 2.0).round();
    final requestH = ((railH - titleBlockH) * dpr * 2.0).round();

    final cacheW = requestW;
    final cacheH = requestH;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header aligned with app padding
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, style: heading)),
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
                child: const Text('View all'),
              ),
            ],
          ),
        ),

        SizedBox(
          height: railH,
          child: ListView.separated(
            // ✅ Starts 16px inset; once you scroll, cards can slide off-screen
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ✅ Image fills remaining space safely
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
                                  errorBuilder: (_, __, ___) =>
                                      const Center(child: Icon(Icons.restaurant_menu)),
                                ),
                              if (isFav)
                                const Positioned(
                                  right: 10,
                                  top: 10,
                                  child: Icon(Icons.star_rounded, color: Colors.amber),
                                ),
                            ],
                          ),
                        ),

                        // ✅ Fixed-height title block prevents overflow forever
                        SizedBox(
                          height: titleBlockH,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
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

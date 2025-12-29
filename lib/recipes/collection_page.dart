import 'package:flutter/material.dart';

import 'recipe_detail_screen.dart';

class CollectionPage extends StatelessWidget {
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

  final List<Map<String, dynamic>> recipes;
  final Set<int> favoriteIds;

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return int.tryParse('${v ?? ''}');
  }

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

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.trim().isNotEmpty) return url.trim();
    }
    return null;
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

  @override
  Widget build(BuildContext context) {
    final filtered = recipes.where((r) => _hasCollectionTerm(r, collectionTermId)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFECF3F4),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = filtered[i];
          final id = _toInt(r['id']);
          final title = _titleOf(r);
          final thumb = _thumbOf(r);
          final isFav = id != null && favoriteIds.contains(id);

          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: id == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: id)),
                      ),
              child: SizedBox(
                height: 92,
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      height: double.infinity,
                      child: thumb == null
                          ? const Center(child: Icon(Icons.restaurant_menu))
                          : Image.network(
                              thumb,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Center(child: Icon(Icons.restaurant_menu)),
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
    );
  }
}

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
    final baseFiltered = widget.recipes
        .where((r) => _hasCollectionTerm(r, widget.collectionTermId))
        .toList();

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
          // ✅ Sub header
          SubHeaderBar(
            title: widget.title,
          ),

          // ✅ Search pill
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

          // ✅ Recipe list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = filtered[i];
                final id = _toInt(r['id']);
                final title = _titleOf(r);
                final thumb = _thumbOf(r);
                final isFav =
                    id != null && widget.favoriteIds.contains(id);

                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: id == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    RecipeDetailScreen(id: id),
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
                                ? const Center(
                                    child: Icon(Icons.restaurant_menu),
                                  )
                                : Image.network(
                                    thumb,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Center(
                                          child:
                                              Icon(Icons.restaurant_menu),
                                        ),
                                  ),
                          ),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  if (isFav)
                                    const Padding(
                                      padding: EdgeInsets.only(
                                          left: 8, top: 2),
                                      child: Icon(
                                        Icons.star_rounded,
                                        color: Colors.amber,
                                      ),
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

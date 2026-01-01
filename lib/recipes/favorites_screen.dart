// lib/recipes/favorites_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_repository.dart';
import 'recipe_detail_screen.dart';

// ✅ reuse shared UI (same as CoursePage)
import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _allRecipes = const [];
  bool _loadingRecipes = true;

  // 🔍 search (same as CoursePage)
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _warmRecipeCache();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _warmRecipeCache() async {
    setState(() => _loadingRecipes = true);
    try {
      final list = await RecipeRepository.ensureRecipesLoaded(
        backgroundRefresh: true,
        forceRefresh: false,
      );
      if (!mounted) return;
      setState(() {
        _allRecipes = list;
        _loadingRecipes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecipes = false);
    }
  }

  Map<String, dynamic>? _findRecipeById(int id) {
    for (final r in _allRecipes) {
      final rid = r['id'];
      if (rid is int && rid == id) return r;
      if (rid is String && int.tryParse(rid) == id) return r;
    }
    return null;
  }

  String _titleOfCached(Map<String, dynamic>? cached) {
    if (cached == null) return 'Recipe';
    final t = cached['title'];
    if (t is Map && t['rendered'] is String) {
      final s = (t['rendered'] as String)
          .replaceAll('&#038;', '&')
          .replaceAll('&amp;', '&')
          .trim();
      if (s.isNotEmpty) return s;
    }
    final name = cached['recipe']?['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return 'Recipe';
  }

  // ✅ New fav schema: doc.id is recipeId; fall back to field for legacy docs.
  int _favRecipeIdFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final fromId = int.tryParse(doc.id);
    if (fromId != null && fromId > 0) return fromId;

    final data = doc.data();
    final raw = data['recipeId'];
    final fromField = (raw is int) ? raw : int.tryParse('$raw');
    if (fromField != null && fromField > 0) return fromField;

    return -1;
  }

  bool _matchesSearch(String title) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in')),
      );
    }

    final favQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        // ✅ matches FavoritesService which writes updatedAt
        .orderBy('updatedAt', descending: true);

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          // ✅ Sub header (same as courses)
          const SubHeaderBar(title: 'Favourites'),

          // ✅ Search pill (same as courses)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchPill(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              hintText: 'Search favourites',
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {},
              onClear: () => setState(() {}),
            ),
          ),

          // ✅ Content
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: favQuery.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: ${snap.error}'),
                  );
                }

                final docs = snap.data?.docs ?? const [];

                if (docs.isEmpty) {
                  return const Center(child: Text('No favourites yet'));
                }

                if (_loadingRecipes) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Build + filter list based on search
                final items = <_FavItem>[];
                for (final doc in docs) {
                  final d = doc.data();
                  final id = _favRecipeIdFromDoc(doc);
                  if (id <= 0) continue;

                  final cached = _findRecipeById(id);

                  final title = _titleOfCached(cached).isNotEmpty
                      ? _titleOfCached(cached)
                      : (d['title']?.toString() ?? 'Recipe');

                  if (!_matchesSearch(title)) continue;

                  final imageUrl =
                      (cached?['recipe']?['image_url_full'] as String?) ??
                          (cached?['recipe']?['image_url'] as String?) ??
                          (d['imageUrl']?.toString());

                  items.add(_FavItem(id: id, title: title, imageUrl: imageUrl));
                }

                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No favourites match "${_searchCtrl.text.trim()}".',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = items[i];

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RecipeDetailScreen(id: item.id),
                            ),
                          );
                        },
                        child: SizedBox(
                          height: 92,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120,
                                height: double.infinity,
                                child: (item.imageUrl == null ||
                                        item.imageUrl!.trim().isEmpty)
                                    ? const Center(
                                        child: Icon(Icons.restaurant_menu),
                                      )
                                    : Image.network(
                                        item.imageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                          child: Icon(Icons.restaurant_menu),
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
                                          item.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const Padding(
                                        padding:
                                            EdgeInsets.only(left: 8, top: 2),
                                        child: Icon(
                                          Icons.star_rounded,
                                          size: 18,
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FavItem {
  const _FavItem({
    required this.id,
    required this.title,
    this.imageUrl,
  });

  final int id;
  final String title;
  final String? imageUrl;
}

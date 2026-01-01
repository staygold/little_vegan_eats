import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_repository.dart';
import 'recipe_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _allRecipes = const [];
  bool _loadingRecipes = true;

  @override
  void initState() {
    super.initState();
    _warmRecipeCache();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('My favourites'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: favQuery.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
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

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data();

              // ✅ read ID from doc.id first (new schema)
              final id = _favRecipeIdFromDoc(doc);
              if (id <= 0) return const SizedBox.shrink();

              // Prefer live recipe cache; fallback to stored metadata
              final cached = _findRecipeById(id);
              final title = (cached?['title']?['rendered'] as String?) ??
                  (cached?['recipe']?['name'] as String?) ??
                  (d['title']?.toString()) ??
                  'Recipe';

              final imageUrl =
                  (cached?['recipe']?['image_url_full'] as String?) ??
                      (cached?['recipe']?['image_url'] as String?) ??
                      (d['imageUrl']?.toString());

              return Card(
                child: ListTile(
                  leading: (imageUrl == null || imageUrl.trim().isEmpty)
                      ? const Icon(Icons.restaurant)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 52,
                              height: 52,
                              child: Icon(Icons.restaurant),
                            ),
                          ),
                        ),
                  title: Text(title),
                  subtitle: const Text('Tap to open'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RecipeDetailScreen(id: id),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

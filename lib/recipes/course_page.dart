import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'recipe_detail_screen.dart';
import 'recipe_repository.dart';

// ✅ reuse shared UI
import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';

class CoursePage extends StatefulWidget {
  const CoursePage({
    super.key,
    required this.courseSlug,
    required this.title,
    required this.subtitle,
    this.recipes,
    this.favoriteIds,
  });

  final String courseSlug;
  final String title;
  final String subtitle;

  final List<Map<String, dynamic>>? recipes;
  final Set<int>? favoriteIds;

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _recipes = const [];

  // 🔍 search
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  // Favorites
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};
  bool _loadingFavs = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _favSub?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Recipes
      if (widget.recipes != null) {
        _recipes = widget.recipes!;
      } else {
        _recipes = await RecipeRepository.ensureRecipesLoaded(
          backgroundRefresh: true,
          forceRefresh: false,
        );
      }

      // Favorites
      if (widget.favoriteIds != null) {
        _favoriteIds
          ..clear()
          ..addAll(widget.favoriteIds!);
        _loadingFavs = false;
      } else {
        _wireFavorites();
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _wireFavorites() {
    _authSub?.cancel();
    _favSub?.cancel();

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _favSub?.cancel();

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _favoriteIds.clear();
          _loadingFavs = false;
        });
        return;
      }

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites');

      _favSub = col.snapshots().listen((snap) {
        final next = <int>{};
        for (final d in snap.docs) {
          final raw = d.data()['recipeId'];
          final id = (raw is int) ? raw : int.tryParse('$raw') ?? -1;
          if (id > 0) next.add(id);
        }

        if (!mounted) return;
        setState(() {
          _favoriteIds
            ..clear()
            ..addAll(next);
          _loadingFavs = false;
        });
      });
    });
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      return t['rendered']
          .toString()
          .replaceAll('&#038;', '&')
          .replaceAll('&amp;', '&')
          .trim();
    }
    return 'Untitled';
  }

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map && recipe['image_url'] is String) {
      final url = recipe['image_url'].toString().trim();
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  bool _matchesCourse(Map<String, dynamic> r, String slug) {
    final s = slug.toLowerCase();
    return r.toString().toLowerCase().contains(s);
  }

  List<Map<String, dynamic>> _filtered() {
    final base = _recipes.where((r) => _matchesCourse(r, widget.courseSlug));
    final q = _searchCtrl.text.trim().toLowerCase();

    if (q.isEmpty) return base.toList();

    return base
        .where((r) => _titleOf(r).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _init, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final list = _filtered();

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          // ✅ Sub header
          SubHeaderBar(title: widget.title),

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

          // ✅ Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(widget.subtitle, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 14),

                if (_loadingFavs)
                  Row(
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Loading favourites…'),
                    ],
                  ),

                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Center(
                      child: Text(
                        'No recipes found for "${widget.title}" yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                ...list.map((r) {
                  final id = _toInt(r['id']);
                  final title = _titleOf(r);
                  final thumb = _thumbOf(r);
                  final isFav =
                      id != null && _favoriteIds.contains(id);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
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
                                        child:
                                            Icon(Icons.restaurant_menu),
                                      )
                                    : Image.network(
                                        thumb,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                          child: Icon(
                                              Icons.restaurant_menu),
                                        ),
                                      ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      14, 12, 14, 12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 2,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: theme.textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight:
                                                    FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      if (isFav)
                                        const Padding(
                                          padding: EdgeInsets.only(
                                              left: 8, top: 2),
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
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

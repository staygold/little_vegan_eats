import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'recipe_detail_screen.dart';
import 'recipe_repository.dart';

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

  /// Optional: can be passed in by a parent that already loaded recipes.
  final List<Map<String, dynamic>>? recipes;

  /// Optional: can be passed in by a parent that already loaded favourites.
  final Set<int>? favoriteIds;

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _recipes = const [];

  // Favorites (if not provided)
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
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) Recipes
      final provided = widget.recipes;
      if (provided != null) {
        _recipes = provided;
      } else {
        _recipes = await RecipeRepository.ensureRecipesLoaded(
          backgroundRefresh: true,
          forceRefresh: false,
        );
      }

      // 2) Favorites
      final favProvided = widget.favoriteIds;
      if (favProvided != null) {
        _favoriteIds
          ..clear()
          ..addAll(favProvided);
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

    setState(() {
      _loadingFavs = true;
      _favoriteIds.clear();
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _favSub?.cancel();

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _loadingFavs = false;
          _favoriteIds.clear();
        });
        return;
      }

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites');

      _favSub = col.snapshots().listen(
        (snap) {
          final next = <int>{};
          for (final d in snap.docs) {
            final data = d.data();
            final raw = data['recipeId'];
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
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _loadingFavs = false;
            _favoriteIds.clear();
          });
        },
      );
    });
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

  /// Robust-ish course matching:
  /// - First, tries taxonomy id arrays (wprm_course / wprm_courses) if present and slug map exists in recipe data.
  /// - Then falls back to checking string-y fields inside recipe map.
  bool _matchesCourse(Map<String, dynamic> r, String slug) {
    final s = slug.trim().toLowerCase();
    if (s.isEmpty) return false;

    // Common taxonomy id arrays
    final a = r['wprm_course'];
    final b = r['wprm_courses'];

    // Sometimes cached recipe data contains a "taxonomies" or "recipe" structure with slugs/names.
    // We'll check a few common places for string course slugs.
    final recipe = r['recipe'];
    if (recipe is Map) {
      final rm = Map<String, dynamic>.from(recipe.cast<String, dynamic>());

      dynamic maybeCourses = rm['course'] ?? rm['courses'] ?? rm['wprm_course'] ?? rm['wprm_courses'];
      if (maybeCourses is String && maybeCourses.toLowerCase().contains(s)) return true;

      if (maybeCourses is List) {
        for (final x in maybeCourses) {
          final xs = x.toString().toLowerCase();
          if (xs == s || xs.contains(s)) return true;
        }
      }
    }

    // If the WP v2 taxonomy ids exist and the recipe cache includes term objects somewhere,
    // you can enhance this later by mapping slug -> termId. For now, we use string fallback.
    if (a is List || b is List) {
      // We don't have reliable termId->slug mapping here without another request,
      // so we do not force-filter by ids only (would risk empty list).
      // Returning false here could hide everything; so we rely on string fallback above.
    }

    // Last resort: search whole record for slug token (cheap but effective)
    final hay = r.toString().toLowerCase();
    return hay.contains('"$s"') || hay.contains(s);
  }

  List<Map<String, dynamic>> _filtered() {
    final out = <Map<String, dynamic>>[];
    for (final r in _recipes) {
      if (_matchesCourse(r, widget.courseSlug)) out.add(r);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _init,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final list = _filtered();

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.subtitle, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),

          if (_loadingFavs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
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
            ),

          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Center(
                child: Text(
                  'No recipes found for "${widget.title}" yet.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          ...list.map((r) {
            final id = _toInt(r['id']);
            final title = _titleOf(r);
            final thumb = _thumbOf(r);
            final isFav = id != null && _favoriteIds.contains(id);

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
                              ? const Center(child: Icon(Icons.restaurant_menu))
                              : Image.network(
                                  thumb,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.restaurant_menu),
                                  ),
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
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (isFav)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8, top: 2),
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
    );
  }
}

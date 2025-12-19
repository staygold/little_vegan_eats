import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/text.dart';
import '../utils/images.dart';
import 'recipe_detail_screen.dart';
import 'package:little_vegan_eats/recipes/recipe_cache.dart';

import 'allergy_engine.dart';

class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({super.key});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'LittleVeganEatsApp/1.0',
      },
    ),
  );

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  String _query = '';

  static const int _perPage = 50;
  int _page = 1;

  bool _loading = true;
  bool _prefetchingAll = false;
  bool _hasMore = true;

  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _selectedCategory = 'All';

  DateTime? _cacheUpdatedAt;
  bool _loadedFromCache = false;

  // ---- Child allergy state ----
  bool _loadingChildren = true;
  String? _childrenError;

  List<ChildProfile> _children = [];
  ChildProfile? _selectedChild;
  bool _includeSwapRecipes = false; // safest default: OFF

  bool _safeForAllChildren = true; // default


  // ------------------------
  // Data helpers
  // ------------------------

  List<String> _coursesOf(Map<String, dynamic> r) {
    final v = r['wprm_course'];

    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    if (v is String && v.trim().isNotEmpty) {
      return [v.trim()];
    }

    return const [];
  }

  List<String> get _courseOptions {
    final set = <String>{};
    for (final r in _items) {
      set.addAll(_coursesOf(r));
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  String _titleOf(Map<String, dynamic> r) =>
      (r['title']?['rendered'] as String?)?.trim().isNotEmpty == true
          ? (r['title']['rendered'] as String)
          : 'Untitled';

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
  }

  String _ingredientsTextOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is! Map) return '';

    final flat = recipe['ingredients_flat'];
    if (flat is! List) return '';

    final buf = StringBuffer();
    for (final row in flat) {
      if (row is! Map) continue;
      final name = (row['name'] ?? '').toString();
      final notes = stripHtml((row['notes'] ?? '').toString());
      if (name.isNotEmpty) buf.write('$name ');
      if (notes.isNotEmpty) buf.write('$notes ');
    }
    return buf.toString().trim();
  }

  // Map Firestore display strings -> canonical keys used by AllergyEngine
  String? _canonicalAllergyKey(String raw) {
    final s = raw.trim().toLowerCase();

    if (s == 'soy') return 'soy';
    if (s == 'peanut' || s == 'peanuts') return 'peanut';
    if (s == 'tree nut' ||
        s == 'tree nuts' ||
        s == 'nuts' ||
        s == 'nut') {
      return 'tree_nut';
    }
    if (s == 'sesame') return 'sesame';
    if (s == 'gluten' || s == 'wheat') return 'gluten';

    // Optional future fields
    if (s == 'coconut') return 'coconut';
    if (s == 'seed' || s == 'seeds') return 'seed';

    return null;
  }

  String _prettyAllergy(String key) {
    switch (key) {
      case 'soy':
        return 'Soy';
      case 'peanut':
        return 'Peanuts';
      case 'tree_nut':
        return 'Tree nuts';
      case 'sesame':
        return 'Sesame';
      case 'gluten':
        return 'Gluten/Wheat';
      case 'coconut':
        return 'Coconut';
      case 'seed':
        return 'Seeds';
      default:
        return key;
    }
  }

  String _combinedAllergiesLabel() {
  final set = <String>{};
  for (final c in _children) {
    set.addAll(c.allergies);
  }
  final list = set.toList()..sort();
  return list.map(_prettyAllergy).join(', ');
}

  // ------------------------
  // Lifecycle
  // ------------------------

  @override
  void initState() {
    super.initState();
    _loadChildren();
    _loadFromCacheThenRefresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadChildren() async {
    setState(() {
      _loadingChildren = true;
      _childrenError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _children = [];
          _selectedChild = null;
          _includeSwapRecipes = false;
          _loadingChildren = false;
        });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data() ?? {};
      final raw = data['children'];

      final kids = <ChildProfile>[];

      if (raw is List) {
        for (final c in raw) {
          if (c is! Map) continue;

          final name = (c['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final allergiesRaw = c['allergies'];
          final allergies = <String>[];

          if (allergiesRaw is List) {
            for (final a in allergiesRaw) {
              final key = _canonicalAllergyKey(a.toString());
              if (key != null) allergies.add(key);
            }
          }

          kids.add(ChildProfile(name: name, allergies: allergies));
        }
      }

      if (!mounted) return;

      setState(() {
        _children = kids;
        _selectedChild = kids.isNotEmpty ? kids.first : null;
        _includeSwapRecipes = false; // strict by default
        _loadingChildren = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _childrenError = e.toString();
        _loadingChildren = false;
      });
    }
  }

  // ------------------------
  // Caching + Networking
  // ------------------------

  Future<void> _loadFromCacheThenRefresh() async {
    // 1) Show cached results immediately (if present)
    try {
      final cached = await RecipeCache.load();
      final updatedAt = await RecipeCache.lastUpdated();

      if (cached.isNotEmpty && mounted) {
        setState(() {
          _items = cached;
          _cacheUpdatedAt = updatedAt;
          _loadedFromCache = true;
          _loading = false;
          _error = null;

          // Cached set is treated as "complete" for search
          _prefetchingAll = false;
          _hasMore = false;
        });
      }
    } catch (_) {
      // ignore cache read issues; we'll fall back to network
    }

    // 2) Then refresh from network
    await _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      // Only show big spinner if we have nothing to show yet
      _loading = _items.isEmpty;
      _error = null;
      _page = 1;
      _hasMore = true;
      _prefetchingAll = false;
      // IMPORTANT: do NOT clear _items here, or offline cache becomes useless
    });

    try {
      final first = await _fetchPage(_page);

      if (!mounted) return;

      setState(() {
        _items = first;
        _hasMore = first.length == _perPage;
        _loading = false;
      });

      // Save partial progress (so offline works even if app closes mid-prefetch)
      await RecipeCache.save(_items);
      final updatedAt = await RecipeCache.lastUpdated();
      if (mounted) {
        setState(() {
          _cacheUpdatedAt = updatedAt;
          _loadedFromCache = true;
        });
      }

      // Prefetch remaining pages so search is complete
      if (_hasMore) {
        _prefetchAllRemaining();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Keep cached/previous list visible; just show error banner
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _prefetchAllRemaining() async {
    if (_prefetchingAll) return;

    setState(() => _prefetchingAll = true);

    try {
      var nextPage = _page;

      while (mounted) {
        nextPage += 1;
        final newItems = await _fetchPage(nextPage);

        if (!mounted) return;

        if (newItems.isEmpty) {
          _hasMore = false;
          break;
        }

        setState(() {
          _page = nextPage;
          _items = [..._items, ...newItems];
          _hasMore = newItems.length == _perPage;
        });

        // Optional: be polite to WP if you hit rate limits
        // await Future.delayed(const Duration(milliseconds: 100));

        if (newItems.length < _perPage) break;
      }

      if (!mounted) return;

      setState(() {
        _prefetchingAll = false;
        _hasMore = false;
      });

      // Save full dataset for offline + complete search
      await RecipeCache.save(_items);
      final updatedAt = await RecipeCache.lastUpdated();
      if (mounted) {
        setState(() {
          _cacheUpdatedAt = updatedAt;
          _loadedFromCache = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prefetchingAll = false;
        // keep already loaded items
      });

      // Still save what we have (better than nothing)
      try {
        await RecipeCache.save(_items);
        final updatedAt = await RecipeCache.lastUpdated();
        if (mounted) {
          setState(() {
            _cacheUpdatedAt = updatedAt;
            _loadedFromCache = true;
          });
        }
      } catch (_) {}
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPage(int page) async {
    final res = await _dio.get(
      'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe',
      queryParameters: {'per_page': _perPage, 'page': page},
    );

    final data = res.data;
    if (data is! List) {
      throw Exception('Unexpected response shape');
    }

    return data.cast<Map<String, dynamic>>();
  }

 // ------------------------
// UI
// ------------------------

@override
Widget build(BuildContext context) {
  final q = _query.trim().toLowerCase();
  final hasAnyAllergies = _children.any((c) => c.allergies.isNotEmpty);

  final visible = _items.where((r) {
    // ---- Course filter ----
    final courses = _coursesOf(r);
    final matchesCourse =
        _selectedCategory == 'All' || courses.contains(_selectedCategory);

    // ---- Search filter ----
    final titleMatch =
        q.isEmpty || _titleOf(r).toLowerCase().contains(q);

    final ingredients = r['recipe']?['ingredients_flat'];
    final ingredientMatch = q.isEmpty
        ? true
        : (ingredients is List &&
            ingredients.any((row) {
              if (row is! Map) return false;
              final name =
                  (row['name'] ?? '').toString().toLowerCase();
              final notes = stripHtml(
                      (row['notes'] ?? '').toString())
                  .toLowerCase();
              return name.contains(q) || notes.contains(q);
            }));

    if (!(matchesCourse && (titleMatch || ingredientMatch))) {
      return false;
    }

    // ---- Allergy filter ----
    if (_children.isNotEmpty) {
      final ingredientsText = _ingredientsTextOf(r);

      bool isAllowedForChild(ChildProfile c) {
        if (c.allergies.isEmpty) return true;

        final res = AllergyEngine.evaluateRecipe(
          ingredientsText: ingredientsText,
          childAllergies: c.allergies,
          includeSwapRecipes: _includeSwapRecipes,
        );

        return res.status == AllergyStatus.safe ||
            (_includeSwapRecipes &&
                res.status == AllergyStatus.swapRequired);
      }

      if (_safeForAllChildren) {
        for (final c in _children) {
          if (!isAllowedForChild(c)) return false;
        }
      } else {
        final c = _selectedChild;
        if (c != null && !isAllowedForChild(c)) return false;
      }
    }

    return true;
  }).toList();

  if (_loading) {
    return const Center(child: CircularProgressIndicator());
  }

  if (_items.isEmpty && _error != null) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadFirstPage,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search recipes...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),

            // ---- Child selector ----
            if (_loadingChildren) ...[
              const SizedBox(height: 10),
              Row(
                children: const [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Loading child profiles...'),
                ],
              ),
            ] else if (_childrenError != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Could not load children: $_childrenError',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _loadChildren,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ] else if (_children.isNotEmpty) ...[
              const SizedBox(height: 10),

              Row(
                children: [
                  const Text('Suitable for:'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _safeForAllChildren
                          ? '__all__'
                          : (_selectedChild?.name ?? '__all__'),
                      items: [
                        const DropdownMenuItem(
                          value: '__all__',
                          child: Text('All children'),
                        ),
                        ..._children.map(
                          (c) => DropdownMenuItem(
                            value: c.name,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _safeForAllChildren = v == '__all__';
                          _selectedChild = _safeForAllChildren
                              ? (_children.isNotEmpty
                                  ? _children.first
                                  : null)
                              : _children
                                  .firstWhere((c) => c.name == v);
                          _includeSwapRecipes = false;
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  hasAnyAllergies
                      ? (_safeForAllChildren
                          ? 'Allergies considered: ${_combinedAllergiesLabel()}'
                          : 'Allergies: ${(_selectedChild?.allergies ?? []).map(_prettyAllergy).join(', ')}')
                      : 'No allergies saved.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),

              if (hasAnyAllergies)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                      'Include recipes that need swaps'),
                  subtitle: const Text(
                    'Shows recipes with a safe replacement suggestion.',
                  ),
                  value: _includeSwapRecipes,
                  onChanged: (val) =>
                      setState(() => _includeSwapRecipes = val),
                ),
            ],

            const SizedBox(height: 8),

            // ---- Course filter ----
            Row(
              children: [
                const Text('Course:'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedCategory,
                    items: _courseOptions
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedCategory = v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      // ---- Recipe list ----
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadFirstPage,
          child: ListView.separated(
            controller: _scroll,
            itemCount: visible.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1),
            itemBuilder: (context, index) {
              final r = visible[index];
              final id = r['id'] as int?;
              final title = _titleOf(r);
              final thumb = _thumbOf(r);

              final courses = _coursesOf(r);
              final courseLabel =
                  courses.isEmpty ? 'No course' : courses.first;

              String? tag;
              String? swapHint;

              final ingredientsText = _ingredientsTextOf(r);

              if (_children.isNotEmpty) {
                if (_safeForAllChildren) {
                  bool anySwap = false;
                  String? firstSwap;

                  for (final c in _children) {
                    if (c.allergies.isEmpty) continue;

                    final res =
                        AllergyEngine.evaluateRecipe(
                      ingredientsText: ingredientsText,
                      childAllergies: c.allergies,
                      includeSwapRecipes: true,
                    );

                    if (res.status ==
                        AllergyStatus.swapRequired) {
                      anySwap = true;
                      firstSwap ??=
                          res.swapNotes.isNotEmpty
                              ? res.swapNotes.first
                              : null;
                    }
                  }

                  tag = anySwap
                      ? '⚠️ Swap required (one or more children)'
                      : '✅ Safe for all children';
                  swapHint = firstSwap;
                } else {
                  final c = _selectedChild;
                  if (c != null && c.allergies.isNotEmpty) {
                    final res =
                        AllergyEngine.evaluateRecipe(
                      ingredientsText: ingredientsText,
                      childAllergies: c.allergies,
                      includeSwapRecipes: true,
                    );

                    if (res.status == AllergyStatus.safe) {
                      tag = '✅ Safe for ${c.name}';
                    } else if (res.status ==
                        AllergyStatus.swapRequired) {
                      tag = '⚠️ Swap required';
                      swapHint = res.swapNotes.isNotEmpty
                          ? res.swapNotes.first
                          : null;
                    }
                  }
                }
              }

              return ListTile(
                leading: SizedBox(
                  width: 56,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: thumb == null
                        ? const Icon(Icons.restaurant_menu)
                        : Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.restaurant_menu),
                          ),
                  ),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$title • $courseLabel'),
                    if (tag != null) ...[
                      const SizedBox(height: 4),
                      Text(tag!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall),
                    ],
                    if (swapHint != null) ...[
                      const SizedBox(height: 2),
                      Text(swapHint!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall),
                    ],
                  ],
                ),
                onTap: id == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                RecipeDetailScreen(id: id),
                          ),
                        ),
              );
            },
          ),
        ),
      ),
    ],
  );
}
}
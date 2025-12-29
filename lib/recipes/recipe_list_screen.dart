import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/text.dart';
import 'recipe_detail_screen.dart';
import 'recipe_cache.dart';
import 'recipe_repository.dart'; // ✅ make sure this path is correct
import 'allergy_engine.dart';
import '../recipes/allergy_keys.dart';

class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({super.key});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  // Used for loading course terms only
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

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  // ---- Course filter ----
  String _selectedCourse = 'All';

  // ---- Course term mapping (ID -> Name) ----
  Map<String, String> _courseIdToName = {}; // "1151" -> "Drinks"
  bool _loadingCourses = false;

  // ---- Cache info ----
  DateTime? _cacheUpdatedAt;
  bool _loadedFromCache = false;

  // ---- Household (adults + children) from Firestore ----
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  bool _loadingHousehold = true;
  String? _householdError;

  final List<_ProfilePerson> _adults = [];
  final List<_ProfilePerson> _children = [];

  // Selection
  _SuitabilityMode _mode = _SuitabilityMode.wholeFamily;
  String? _selectedPersonId; // for single-person mode

  // Toggles
  bool _showSuitableFor = true; // shows/hides the whole suitability section (kept)
  bool _filterByAllergies = true; // default ON
  bool _includeSwapRecipes = false; // OFF by default

  // ✅ Favourites (IDs only)
  StreamSubscription<User?>? _authFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  bool _loadingFavs = true;
  final Set<int> _favoriteIds = <int>{};

  // ------------------------
  // Helpers
  // ------------------------

  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(u.uid);
  }

  CollectionReference<Map<String, dynamic>>? _favoritesCol() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .collection('favorites');
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

  String? _canonicalAllergyKey(String raw) => AllergyKeys.normalize(raw);
  String _prettyAllergy(String key) => AllergyKeys.label(key);

  // ✅ Upgrade UI from cache if it’s newer (not only bigger)
  Future<void> _upgradeItemsFromCacheIfNewer() async {
    try {
      final cached = await RecipeCache.load();
      final updatedAt = await RecipeCache.lastUpdated();

      if (!mounted) return;
      if (cached.isEmpty) return;

      final isNewer = updatedAt != null &&
          (_cacheUpdatedAt == null || updatedAt.isAfter(_cacheUpdatedAt!));
      final lengthChanged = cached.length != _items.length;

      if (isNewer || lengthChanged) {
        setState(() {
          _items = cached;
          _cacheUpdatedAt = updatedAt;
          _loadedFromCache = true;
        });
      }
    } catch (_) {}
  }

  // ------------------------
  // Courses (WPRM)
  // ------------------------

  List<String> _coursesOf(Map<String, dynamic> r) {
    final v = r['wprm_course'];

    List<String> raw = [];
    if (v is List) {
      raw = v
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (v is int) {
      raw = [v.toString()];
    } else if (v is String && v.trim().isNotEmpty) {
      raw = [v.trim()];
    }

    final mapped = raw.map((x) => _courseIdToName[x] ?? x).toList();

    final set = <String>{};
    for (final m in mapped) {
      final s = m.trim();
      if (s.isNotEmpty) set.add(s);
    }

    final list = set.toList()..sort();
    return list;
  }

  List<String> get _courseOptions {
    final set = <String>{};
    for (final r in _items) {
      set.addAll(_coursesOf(r));
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  // ------------------------
  // Lifecycle
  // ------------------------

  @override
  void initState() {
    super.initState();
    _listenToHousehold();
    _listenToFavorites(); // ✅
    _loadCourseTerms();
    _loadRecipes(); // ✅ single source of truth for recipes
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _authFavSub?.cancel();
    _favSub?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------
  // ✅ Favorites (IDs only)
  // ------------------------

  void _listenToFavorites() {
    // Follow auth and rebind fav collection when user changes.
    _authFavSub?.cancel();
    _favSub?.cancel();

    setState(() {
      _loadingFavs = true;
      _favoriteIds.clear();
    });

    _authFavSub = FirebaseAuth.instance.authStateChanges().listen((user) {
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

  bool _isFavorited(int? recipeId) {
    if (recipeId == null) return false;
    return _favoriteIds.contains(recipeId);
  }

  // ------------------------
  // Household
  // ------------------------

  void _listenToHousehold() {
    final doc = _userDoc();
    if (doc == null) {
      setState(() {
        _loadingHousehold = false;
        _householdError = null;
        _adults.clear();
        _children.clear();
      });
      return;
    }

    setState(() {
      _loadingHousehold = true;
      _householdError = null;
    });

    _userSub?.cancel();
    _userSub = doc.snapshots().listen(
      (snap) {
        final data = snap.data() ?? {};
        final rawAdults = (data['adults'] as List?) ?? [];
        final rawChildren = (data['children'] as List?) ?? [];

        final adults = <_ProfilePerson>[];
        final children = <_ProfilePerson>[];

        for (var i = 0; i < rawAdults.length; i++) {
          final a = rawAdults[i];
          if (a is! Map) continue;

          final name = (a['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final hasAllergies = (a['hasAllergies'] == true);

          final parsed = <String>[];
          final allergiesRaw = a['allergies'];
          if (allergiesRaw is List) {
            for (final x in allergiesRaw) {
              final k = _canonicalAllergyKey(x.toString());
              if (k != null) parsed.add(k);
            }
          }

          final canonical =
              hasAllergies ? (parsed.toSet().toList()..sort()) : <String>[];

          adults.add(
            _ProfilePerson(
              id: 'adult_$i',
              type: _PersonType.adult,
              name: name,
              hasAllergies: hasAllergies,
              allergies: canonical,
            ),
          );
        }

        for (var i = 0; i < rawChildren.length; i++) {
          final c = rawChildren[i];
          if (c is! Map) continue;

          final name = (c['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final hasAllergies = (c['hasAllergies'] == true);

          final parsed = <String>[];
          final allergiesRaw = c['allergies'];
          if (allergiesRaw is List) {
            for (final x in allergiesRaw) {
              final k = _canonicalAllergyKey(x.toString());
              if (k != null) parsed.add(k);
            }
          }

          final canonical =
              hasAllergies ? (parsed.toSet().toList()..sort()) : <String>[];

          children.add(
            _ProfilePerson(
              id: 'child_$i',
              type: _PersonType.child,
              name: name,
              hasAllergies: hasAllergies,
              allergies: canonical,
            ),
          );
        }

        if (!mounted) return;

        setState(() {
          _adults
            ..clear()
            ..addAll(adults);

          _children
            ..clear()
            ..addAll(children);

          _loadingHousehold = false;
          _householdError = null;

          if (_mode == _SuitabilityMode.singlePerson) {
            final exists = _allPeople.any((p) => p.id == _selectedPersonId);
            if (!exists) {
              _mode = _SuitabilityMode.wholeFamily;
              _selectedPersonId = null;
              _includeSwapRecipes = false;
            }
          }
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _loadingHousehold = false;
          _householdError = e.toString();
        });
      },
    );
  }

  List<_ProfilePerson> get _allPeople => [..._adults, ..._children];

  bool get _hasAnyActiveAllergies =>
      _allPeople.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

  String _activeAllergiesLabelFor(List<_ProfilePerson> people) {
    final set = <String>{};
    for (final p in people) {
      if (p.hasAllergies && p.allergies.isNotEmpty) set.addAll(p.allergies);
    }
    final list = set.toList()..sort();
    return list.map(_prettyAllergy).join(', ');
  }

  List<_ProfilePerson> _activeProfilesForMode() {
    switch (_mode) {
      case _SuitabilityMode.wholeFamily:
        return _allPeople;
      case _SuitabilityMode.allChildren:
        return _children;
      case _SuitabilityMode.singlePerson:
        return _allPeople.where((x) => x.id == _selectedPersonId).toList();
    }
  }

  // ------------------------
  // Load course terms (ID -> Name)
  // ------------------------

  Future<void> _loadCourseTerms() async {
    if (_loadingCourses) return;

    setState(() => _loadingCourses = true);

    try {
      final map = <String, String>{};
      int page = 1;
      const int perPage = 100;

      while (true) {
        final res = await _dio.get(
          'https://littleveganeats.co/wp-json/wp/v2/wprm_course',
          queryParameters: {
            'per_page': perPage,
            'page': page,
          },
        );

        final data = res.data;
        if (data is! List) break;

        final batch = data.cast<Map<String, dynamic>>();

        for (final t in batch) {
          final id = t['id'];
          final name = (t['name'] ?? '').toString().trim();
          if (id != null && name.isNotEmpty) {
            map[id.toString()] = name;
          }
        }

        if (batch.length < perPage) break;
        page += 1;
      }

      if (!mounted) return;

      setState(() {
        _courseIdToName = map;
      });
    } catch (_) {
      // silent fail
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  // ------------------------
  // ✅ Recipes: cache-first via repository (single source of truth)
  // ------------------------

  Future<void> _loadRecipes({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final recipes = await RecipeRepository.ensureRecipesLoaded(
        backgroundRefresh: true, // cache-first, then background refresh (throttled)
        forceRefresh: forceRefresh,
      );

      final updatedAt = await RecipeCache.lastUpdated();

      if (!mounted) return;
      setState(() {
        _items = recipes;
        _cacheUpdatedAt = updatedAt;
        _loadedFromCache = true;
        _loading = false;
      });

      // Background refresh may update the cache shortly after boot
      unawaited(
        Future.delayed(const Duration(seconds: 2), _upgradeItemsFromCacheIfNewer),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ------------------------
  // Allergy evaluation helpers
  // ------------------------

  bool _isAllowedForPerson({
    required _ProfilePerson p,
    required String ingredientsText,
  }) {
    if (!p.hasAllergies || p.allergies.isEmpty) return true;

    final res = AllergyEngine.evaluateRecipe(
      ingredientsText: ingredientsText,
      childAllergies: p.allergies,
      includeSwapRecipes: _includeSwapRecipes,
    );

    if (res.status == AllergyStatus.safe) return true;
    if (_includeSwapRecipes && res.status == AllergyStatus.swapRequired) return true;
    return false;
  }

  ({String? tag, String? swapHint}) _tagForRecipe({
    required String ingredientsText,
    required List<_ProfilePerson> activeProfiles,
  }) {
    final anyActive =
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);
    if (!anyActive) return (tag: null, swapHint: null);

    bool anySwap = false;
    String? firstSwap;
    bool anyNotSuitable = false;

    for (final p in activeProfiles) {
      if (!p.hasAllergies || p.allergies.isEmpty) continue;

      final res = AllergyEngine.evaluateRecipe(
        ingredientsText: ingredientsText,
        childAllergies: p.allergies,
        includeSwapRecipes: true,
      );

      if (res.status == AllergyStatus.notSuitable) {
        anyNotSuitable = true;
      } else if (res.status == AllergyStatus.swapRequired) {
        anySwap = true;
        firstSwap ??= res.swapNotes.isNotEmpty ? res.swapNotes.first : null;
      }
    }

    if (anyNotSuitable) return (tag: '⛔ Not suitable', swapHint: null);

    if (anySwap) {
      return (
        tag: activeProfiles.length > 1
            ? '⚠️ Swap required (one or more people)'
            : '⚠️ Swap required',
        swapHint: firstSwap,
      );
    }

    if (_mode == _SuitabilityMode.singlePerson && activeProfiles.isNotEmpty) {
      return (tag: '✅ Safe for ${activeProfiles.first.name}', swapHint: null);
    }
    if (_mode == _SuitabilityMode.allChildren) {
      return (tag: '✅ Safe for all children', swapHint: null);
    }
    return (tag: '✅ Safe for whole family', swapHint: null);
  }

  // ------------------------
  // UI
  // ------------------------

  @override
  Widget build(BuildContext context) {
    final courseOptions = _courseOptions;
    final selectedCourse =
        courseOptions.contains(_selectedCourse) ? _selectedCourse : 'All';
    if (selectedCourse != _selectedCourse) _selectedCourse = selectedCourse;

    final q = _query.trim().toLowerCase();

    final activeProfiles = _filterByAllergies ? _activeProfilesForMode() : _allPeople;

    final hasAnyAllergies =
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

    final visible = _items.where((r) {
      final courses = _coursesOf(r);
      final matchesCourse =
          (_selectedCourse == 'All') || courses.contains(_selectedCourse);

      final titleMatch = q.isEmpty || _titleOf(r).toLowerCase().contains(q);

      final ingredients = r['recipe']?['ingredients_flat'];
      final ingredientMatch = q.isEmpty
          ? true
          : (ingredients is List &&
              ingredients.any((row) {
                if (row is! Map) return false;
                final name = (row['name'] ?? '').toString().toLowerCase();
                final notes =
                    stripHtml((row['notes'] ?? '').toString()).toLowerCase();
                return name.contains(q) || notes.contains(q);
              }));

      if (!(matchesCourse && (titleMatch || ingredientMatch))) return false;

      if (_filterByAllergies && hasAnyAllergies) {
        final ingredientsText = _ingredientsTextOf(r);
        for (final p in _activeProfilesForMode()) {
          if (!_isAllowedForPerson(p: p, ingredientsText: ingredientsText)) {
            debugPrint(
              '[RecipeList] FILTERED BY ALLERGY id=${r['id']} title="${_titleOf(r)}"',
            );
            return false;
          }
        }
      }

      return true;
    }).toList();

    debugPrint(
      '[RecipeList] items=${_items.length} visible=${visible.length} '
      'course=$_selectedCourse query="${_query.trim()}" '
      'filterByAllergies=$_filterByAllergies mode=$_mode '
      'people=${_allPeople.length}',
    );

    if (_loading) return const Center(child: CircularProgressIndicator());

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
                onPressed: () => _loadRecipes(forceRefresh: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final suitabilityItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '__whole__', child: Text('Whole family')),
      const DropdownMenuItem(value: '__kids__', child: Text('All children')),
      if (_adults.isNotEmpty)
        const DropdownMenuItem(
          value: '__sep1__',
          enabled: false,
          child: Text('— Adults —'),
        ),
      ..._adults.map((a) {
        final label = a.id == 'adult_0'
            ? 'Adult 1 (You): ${a.name}'
            : 'Adult: ${a.name}';
        return DropdownMenuItem(value: a.id, child: Text(label));
      }),
      if (_children.isNotEmpty)
        const DropdownMenuItem(
          value: '__sep2__',
          enabled: false,
          child: Text('— Children —'),
        ),
      ..._children.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
    ];

    String suitabilityValue;
    if (_mode == _SuitabilityMode.wholeFamily) {
      suitabilityValue = '__whole__';
    } else if (_mode == _SuitabilityMode.allChildren) {
      suitabilityValue = '__kids__';
    } else {
      suitabilityValue = _selectedPersonId ?? '__whole__';
      final exists = _allPeople.any((p) => p.id == suitabilityValue);
      if (!exists) suitabilityValue = '__whole__';
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

              const SizedBox(height: 10),

              if (_loadingHousehold) ...[
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Loading family profiles...'),
                  ],
                ),
              ] else if (_householdError != null) ...[
                Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Could not load family: $_householdError',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _listenToHousehold,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ] else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Filter by allergies'),
                  subtitle: const Text('Turn off to browse all recipes (tags still shown).'),
                  value: _filterByAllergies,
                  onChanged: (val) => setState(() {
                    _filterByAllergies = val;
                    if (!val) _includeSwapRecipes = false;
                  }),
                ),

                if (_filterByAllergies) ...[
                  Row(
                    children: [
                      const Text('Suitable for:'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: suitabilityValue,
                          items: suitabilityItems
                              .where((i) => i.value != '__sep1__' && i.value != '__sep2__')
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;

                            setState(() {
                              if (v == '__whole__') {
                                _mode = _SuitabilityMode.wholeFamily;
                                _selectedPersonId = null;
                              } else if (v == '__kids__') {
                                _mode = _SuitabilityMode.allChildren;
                                _selectedPersonId = null;
                              } else {
                                _mode = _SuitabilityMode.singlePerson;
                                _selectedPersonId = v;
                              }

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
                          ? 'Allergies considered: ${_activeAllergiesLabelFor(_activeProfilesForMode())}'
                          : 'No allergies saved.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),

                  if (hasAnyAllergies) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Include recipes that need swaps'),
                      subtitle: const Text('Shows recipes with a safe replacement suggestion.'),
                      value: _includeSwapRecipes,
                      onChanged: (val) => setState(() => _includeSwapRecipes = val),
                    ),
                  ],
                ],
              ],

              const SizedBox(height: 8),

              Row(
                children: [
                  const Text('Course:'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedCourse,
                      items: courseOptions
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedCourse = v);
                      },
                    ),
                  ),
                ],
              ),

              if (_loadedFromCache || _cacheUpdatedAt != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _cacheUpdatedAt != null ? 'Cached: ${_cacheUpdatedAt!.toLocal()}' : '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await RecipeRepository.ensureRecipesLoaded(
                backgroundRefresh: false,
                forceRefresh: true,
              );

              final updated = await RecipeCache.load();
              final updatedAt = await RecipeCache.lastUpdated();

              if (!mounted) return;
              setState(() {
                _items = updated;
                _cacheUpdatedAt = updatedAt;
                _loadedFromCache = true;
                _error = null;
              });
            },
            child: ListView.separated(
              controller: _scroll,
              itemCount: visible.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final r = visible[index];
                final id = r['id'] as int?;
                final title = _titleOf(r);
                final thumb = _thumbOf(r);

                final courses = _coursesOf(r);
                final courseLabel = courses.isEmpty ? 'No course' : courses.first;

                final ingredientsText = _ingredientsTextOf(r);

                final tagData = _tagForRecipe(
                  ingredientsText: ingredientsText,
                  activeProfiles: _filterByAllergies ? _activeProfilesForMode() : _allPeople,
                );

                final isFav = _isFavorited(id);

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
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.restaurant_menu),
                            ),
                    ),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('$title • $courseLabel')),
                          if (isFav)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: Colors.amber,
                              ),
                            ),
                        ],
                      ),
                      if (tagData.tag != null) ...[
                        const SizedBox(height: 4),
                        Text(tagData.tag!, style: Theme.of(context).textTheme.bodySmall),
                      ],
                      if (tagData.swapHint != null) ...[
                        const SizedBox(height: 2),
                        Text(tagData.swapHint!, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                  onTap: id == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: id)),
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

// ------------------------
// Internal types (TOP-LEVEL)
// ------------------------

enum _SuitabilityMode { wholeFamily, allChildren, singlePerson }
enum _PersonType { adult, child }

class _ProfilePerson {
  final String id;
  final _PersonType type;
  final String name;
  final bool hasAllergies;
  final List<String> allergies;

  const _ProfilePerson({
    required this.id,
    required this.type,
    required this.name,
    required this.hasAllergies,
    required this.allergies,
  });
}

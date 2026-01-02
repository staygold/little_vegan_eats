// lib/recipes/recipe_list_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/text.dart';
import 'recipe_detail_screen.dart';
import 'recipe_cache.dart';
import 'recipe_repository.dart';
import 'allergy_engine.dart';
import '../recipes/allergy_keys.dart';

// ✅ These types MUST exist somewhere in your app.
import '../meal_plan/core/allergy_profile.dart';

import '../shared/search_pill.dart';
import 'widgets/recipe_card.dart';

// ✅ NEW reusable filters UI
import 'widgets/recipe_filters_ui.dart';

/// Minimal local unawaited helper (so you don't need pedantic).
void unawaited(Future<void> f) {}

class _RecipeIndex {
  final int id;
  final String titleLower;

  final String ingredientsText; // original for engine
  final String ingredientsLower; // for search

  final List<String> courses;
  final List<String> collections;
  final List<String> cuisines;
  final List<String> suitable;
  final List<String> nutrition;

  _RecipeIndex({
    required this.id,
    required this.titleLower,
    required this.ingredientsText,
    required this.ingredientsLower,
    required this.courses,
    required this.collections,
    required this.cuisines,
    required this.suitable,
    required this.nutrition,
  });
}

class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({
    super.key,
    this.initialCourseSlug,
    this.lockCourse,
    this.initialCollectionSlug,
    this.lockCollection,
  });

  final String? initialCourseSlug;
  final bool? lockCourse;

  final String? initialCollectionSlug;
  final bool? lockCollection;

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

  // ✅ Search pill requires focusNode
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  Timer? _searchDebounce;

  bool _loading = true; // boot gate
  String? _error;
  List<Map<String, dynamic>> _items = [];

  // ✅ Filter selections
  RecipeFilterSelection _filters = const RecipeFilterSelection();

  // ✅ Allergies ON by default
  AllergiesSelection _allergies = const AllergiesSelection(
    enabled: true, 
    mode: SuitabilityMode.wholeFamily
  );

  // ✅ Visible list is precomputed
  List<Map<String, dynamic>> _visible = [];

  // ✅ Tag cache for visible rows (only when allergies enabled)
  final Map<int, ({String? tag, String? swapHint})> _tagById = {};

  // ---- Term mapping ----
  Map<String, String> _courseIdToName = {};
  Map<String, String> _courseSlugToName = {};

  Map<String, String> _collectionIdToName = {};
  Map<String, String> _collectionSlugToName = {};

  Map<String, String> _cuisineIdToName = {};
  Map<String, String> _cuisineSlugToName = {};

  Map<String, String> _suitableIdToName = {};
  Map<String, String> _suitableSlugToName = {};

  Map<String, String> _nutritionIdToName = {};
  Map<String, String> _nutritionSlugToName = {};

  bool _loadingTerms = false;
  bool _didApplyInitialCourse = false;
  bool _didApplyInitialCollection = false;

  bool _recipesLoaded = false;
  bool _termsLoaded = false;

  DateTime? _cacheUpdatedAt;
  bool _loadedFromCache = false;

  // ✅ Index/caches
  final Map<int, _RecipeIndex> _indexById = {};
  bool _indexReady = false;

  List<String> _courseOptionsCached = const ['All'];
  List<String> _collectionOptionsCached = const ['All'];
  List<String> _cuisineOptionsCached = const ['All'];
  List<String> _suitableOptionsCached = const ['All'];
  List<String> _nutritionOptionsCached = const ['All'];

  // ---- Household ----
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  bool _loadingHousehold = true;
  String? _householdError;

  final List<ProfilePerson> _adults = [];
  final List<ProfilePerson> _children = [];

  // ✅ Favourites
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

  List<ProfilePerson> get _allPeople => [..._adults, ..._children];

  /// ✅ Local default check (since RecipeFilterSelection has no `isAll`)
  bool get _filtersAreDefault =>
      _filters.course == 'All' &&
      _filters.collection == 'All' &&
      _filters.cuisine == 'All' &&
      _filters.suitableFor == 'All' &&
      _filters.nutritionTag == 'All';

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

          // ✅ keep first-load instant
          if (!_allergies.enabled &&
              _query.trim().isEmpty &&
              _filtersAreDefault) {
            _visible = List<Map<String, dynamic>>.from(cached);
            _tagById.clear();
          }
        });

        _rebuildIndexAndOptions(force: true);

        if (_allergies.enabled ||
            _query.trim().isNotEmpty ||
            !_filtersAreDefault) {
          _recomputeVisible();
        }
      }
    } catch (_) {}
  }

  // ------------------------
  // WPRM term parsing helpers (IDs -> names)
  // ------------------------

  List<String> _termsOfField(
    Map<String, dynamic> r,
    String field,
    Map<String, String> idToName,
  ) {
    final v = r[field];

    List<String> raw = [];
    if (v is List) {
      raw =
          v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    } else if (v is int) {
      raw = [v.toString()];
    } else if (v is String && v.trim().isNotEmpty) {
      raw = [v.trim()];
    }

    final mapped = raw.map((x) => idToName[x] ?? x).toList();

    final set = <String>{};
    for (final m in mapped) {
      final s = m.trim();
      if (s.isNotEmpty) set.add(s);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _coursesOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_course', _courseIdToName);

  List<String> _collectionsOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_collections', _collectionIdToName);

  List<String> _cuisinesOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_cuisine', _cuisineIdToName);

  List<String> _suitableForOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_suitable_for', _suitableIdToName);

  List<String> _nutritionTagsOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_nutrition_tag', _nutritionIdToName);

  // ------------------------
  // Initial slugs
  // ------------------------

  void _applyInitialCourseIfNeeded() {
    if (_didApplyInitialCourse) return;

    final slug = widget.initialCourseSlug?.trim();
    if (slug == null || slug.isEmpty) {
      _didApplyInitialCourse = true;
      return;
    }

    final name = _courseSlugToName[slug];
    if (name == null || name.trim().isEmpty) return;

    final opts = _courseOptionsCached;
    if (opts.contains(name)) {
      _filters = _filters.copyWith(course: name);
      _didApplyInitialCourse = true;
    }
  }

  void _applyInitialCollectionIfNeeded() {
    if (_didApplyInitialCollection) return;

    final slug = widget.initialCollectionSlug?.trim();
    if (slug == null || slug.isEmpty) {
      _didApplyInitialCollection = true;
      return;
    }

    final name = _collectionSlugToName[slug];
    if (name == null || name.trim().isEmpty) return;

    final opts = _collectionOptionsCached;
    if (opts.contains(name)) {
      _filters = _filters.copyWith(collection: name);
      _didApplyInitialCollection = true;
    }
  }

  void _maybeFinishBoot() {
    // ✅ OPTIMIZATION: Fast Boot.
    // If recipes are loaded, show them. Don't wait for terms.
    if (!_recipesLoaded) return;

    _applyInitialCourseIfNeeded();
    _applyInitialCollectionIfNeeded();

    final needCourse = (widget.initialCourseSlug?.trim().isNotEmpty ?? false);
    final needCollection =
        (widget.initialCollectionSlug?.trim().isNotEmpty ?? false);

    final courseReady = !needCourse || _didApplyInitialCourse;
    final collectionReady = !needCollection || _didApplyInitialCollection;

    if (courseReady && collectionReady) {
      if (!mounted) return;

      // ✅ first load: show all instantly
      setState(() {
        _loading = false;
        _visible = List<Map<String, dynamic>>.from(_items);
        _tagById.clear();
      });

      // If initial slugs applied, recompute after first paint
      if (!_filtersAreDefault) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _recomputeVisible());
      }
    }
  }

  // ------------------------
  // Lifecycle
  // ------------------------

  @override
  void initState() {
    super.initState();
    _listenToHousehold();
    _listenToFavorites();
    _loadTerms();
    _loadRecipes();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _authFavSub?.cancel();
    _favSub?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------
  // Favorites
  // ------------------------

  void _listenToFavorites() {
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

        final adults = <ProfilePerson>[];
        final children = <ProfilePerson>[];

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
            ProfilePerson(
              id: 'adult_$i',
              type: PersonType.adult,
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
            ProfilePerson(
              id: 'child_$i',
              type: PersonType.child,
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

          // keep allergies selection valid
          if (_allergies.mode == SuitabilityMode.specificPeople) {
            // Check if selected IDs still exist
            final validIds = _allergies.personIds
                .where((id) => _allPeople.any((p) => p.id == id))
                .toSet();
            
            if (validIds.isEmpty) {
               // Fallback if everyone removed
               _allergies = _allergies.copyWith(
                mode: SuitabilityMode.wholeFamily,
                personIds: {},
                includeSwaps: false,
              );
            } else if (validIds.length != _allergies.personIds.length) {
               // Update set to remove stale IDs
               _allergies = _allergies.copyWith(personIds: validIds);
            }
          }
        });

        // ✅ Only recompute if the user actually enabled allergies or applied filters/search.
        if (_allergies.enabled ||
            _query.trim().isNotEmpty ||
            !_filtersAreDefault) {
          _recomputeVisible();
        }
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

  String _activeAllergiesLabelFor(List<ProfilePerson> people) {
    final set = <String>{};
    for (final p in people) {
      if (p.hasAllergies && p.allergies.isNotEmpty) set.addAll(p.allergies);
    }
    final list = set.toList()..sort();
    return list.map(_prettyAllergy).join(', ');
  }

  // ✅ UPDATED: Supports Set of IDs for specific people
  List<ProfilePerson> _activeProfilesForAllergies() {
    if (!_allergies.enabled) return _allPeople;

    switch (_allergies.mode) {
      case SuitabilityMode.wholeFamily:
        return _allPeople;
      case SuitabilityMode.allChildren:
        return _children;
      case SuitabilityMode.specificPeople:
        return _allPeople.where((x) => _allergies.personIds.contains(x.id)).toList();
    }
  }

  // ------------------------
  // Load terms
  // ------------------------

  Future<void> _loadTerms() async {
    if (_loadingTerms) return;
    setState(() => _loadingTerms = true);

    try {
      final courseById = <String, String>{};
      final courseBySlug = <String, String>{};

      final colById = <String, String>{};
      final colBySlug = <String, String>{};

      final cuisineById = <String, String>{};
      final cuisineBySlug = <String, String>{};

      final suitableById = <String, String>{};
      final suitableBySlug = <String, String>{};

      final nutritionById = <String, String>{};
      final nutritionBySlug = <String, String>{};

      Future<void> loadTax({
        required String endpoint,
        required Map<String, String> byId,
        required Map<String, String> bySlug,
      }) async {
        int page = 1;
        const int perPage = 100;

        while (true) {
          final res = await _dio.get(
            'https://littleveganeats.co/wp-json/wp/v2/$endpoint',
            queryParameters: {'per_page': perPage, 'page': page},
          );

          final data = res.data;
          if (data is! List) break;

          final batch = data.cast<Map<String, dynamic>>();
          for (final t in batch) {
            final id = t['id'];
            final name = (t['name'] ?? '').toString().trim();
            final slug = (t['slug'] ?? '').toString().trim();

            if (id != null && name.isNotEmpty) byId[id.toString()] = name;
            if (slug.isNotEmpty && name.isNotEmpty) bySlug[slug] = name;
          }

          if (batch.length < perPage) break;
          page += 1;
        }
      }

      // ✅ OPTIMIZATION: Fire all requests in parallel
      await Future.wait([
        loadTax(
            endpoint: 'wprm_course', byId: courseById, bySlug: courseBySlug),
        loadTax(
            endpoint: 'wprm_collections', byId: colById, bySlug: colBySlug),
        loadTax(
            endpoint: 'wprm_cuisine', byId: cuisineById, bySlug: cuisineBySlug),
        loadTax(
            endpoint: 'wprm_suitable_for',
            byId: suitableById,
            bySlug: suitableBySlug),
        loadTax(
            endpoint: 'wprm_nutrition_tag',
            byId: nutritionById,
            bySlug: nutritionBySlug),
      ]);

      if (!mounted) return;

      setState(() {
        _courseIdToName = courseById;
        _courseSlugToName = courseBySlug;

        _collectionIdToName = colById;
        _collectionSlugToName = colBySlug;

        _cuisineIdToName = cuisineById;
        _cuisineSlugToName = cuisineBySlug;

        _suitableIdToName = suitableById;
        _suitableSlugToName = suitableBySlug;

        _nutritionIdToName = nutritionById;
        _nutritionSlugToName = nutritionBySlug;

        _termsLoaded = true;
      });

      // ✅ FIX: Force index rebuild now that we have Names (not just IDs)
      _rebuildIndexAndOptions(force: true);

      // If we are already displaying items, refresh the list to show the new Names
      if (_recipesLoaded) _recomputeVisible();
    } catch (_) {
      if (!mounted) return;
      setState(() => _termsLoaded = true);
      _rebuildIndexAndOptions(force: true);
    } finally {
      if (mounted) setState(() => _loadingTerms = false);
    }
  }

  // ------------------------
  // Recipes
  // ------------------------

  Future<void> _loadRecipes({bool forceRefresh = false}) async {
    setState(() => _error = null);

    try {
      final recipes = await RecipeRepository.ensureRecipesLoaded(
        backgroundRefresh: true,
        forceRefresh: forceRefresh,
      );

      final updatedAt = await RecipeCache.lastUpdated();

      if (!mounted) return;
      setState(() {
        _items = recipes;
        _cacheUpdatedAt = updatedAt;
        _loadedFromCache = true;
        _recipesLoaded = true;
      });

      _rebuildIndexAndOptions();
      _maybeFinishBoot();

      unawaited(Future.delayed(
          const Duration(seconds: 2), _upgradeItemsFromCacheIfNewer));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _recipesLoaded = true;
        _loading = false;
      });
    }
  }

  // ------------------------
  // Index + Options
  // ------------------------

  void _rebuildIndexAndOptions({bool force = false}) {
    if (_items.isEmpty) {
      _indexById.clear();
      _indexReady = true;

      if (!mounted) return;
      setState(() {
        _courseOptionsCached = const ['All'];
        _collectionOptionsCached = const ['All'];
        _cuisineOptionsCached = const ['All'];
        _suitableOptionsCached = const ['All'];
        _nutritionOptionsCached = const ['All'];
      });
      return;
    }

    // ✅ OPTIMIZATION: Skip re-indexing if the item count hasn't changed.
    // UNLESS "force" is true (which means new Terms just arrived).
    if (!force && _indexReady && _indexById.length == _items.length) return;

    final coursesSet = <String>{};
    final collectionsSet = <String>{};
    final cuisinesSet = <String>{};
    final suitableSet = <String>{};
    final nutritionSet = <String>{};

    _indexById.clear();

    for (final r in _items) {
      final rawId = r['id'];
      if (rawId is! int) continue;

      final titleLower = _titleOf(r).toLowerCase();
      final ingText = _ingredientsTextOf(r);
      final ingLower = ingText.toLowerCase();

      final courses = _coursesOf(r);
      final collections = _collectionsOf(r);
      final cuisines = _cuisinesOf(r);
      final suitable = _suitableForOf(r);
      final nutrition = _nutritionTagsOf(r);

      coursesSet.addAll(courses);
      collectionsSet.addAll(collections);
      cuisinesSet.addAll(cuisines);
      suitableSet.addAll(suitable);
      nutritionSet.addAll(nutrition);

      _indexById[rawId] = _RecipeIndex(
        id: rawId,
        titleLower: titleLower,
        ingredientsText: ingText,
        ingredientsLower: ingLower,
        courses: courses,
        collections: collections,
        cuisines: cuisines,
        suitable: suitable,
        nutrition: nutrition,
      );
    }

    List<String> mkOptions(Set<String> s) {
      final list = s.toList()..sort();
      return ['All', ...list];
    }

    if (!mounted) return;

    setState(() {
      _courseOptionsCached = mkOptions(coursesSet);
      _collectionOptionsCached = mkOptions(collectionsSet);
      _cuisineOptionsCached = mkOptions(cuisinesSet);
      _suitableOptionsCached = mkOptions(suitableSet);
      _nutritionOptionsCached = mkOptions(nutritionSet);
      _indexReady = true;

      _filters = _filters.copyWith(
        course: _clampToOptions(_filters.course, _courseOptionsCached),
        cuisine: _clampToOptions(_filters.cuisine, _cuisineOptionsCached),
        suitableFor:
            _clampToOptions(_filters.suitableFor, _suitableOptionsCached),
        nutritionTag:
            _clampToOptions(_filters.nutritionTag, _nutritionOptionsCached),
        collection:
            _clampToOptions(_filters.collection, _collectionOptionsCached),
      );
    });
  }

  String _clampToOptions(String current, List<String> opts) {
    if (opts.isEmpty) return 'All';
    if (opts.contains(current)) return current;
    return 'All';
  }

  // ------------------------
  // Allergy evaluation
  // ------------------------

  bool _isAllowedForPerson({
    required ProfilePerson p,
    required String ingredientsText,
  }) {
    if (!p.hasAllergies || p.allergies.isEmpty) return true;

    final res = AllergyEngine.evaluateRecipe(
      ingredientsText: ingredientsText,
      childAllergies: p.allergies,
      includeSwapRecipes: _allergies.includeSwaps,
    );

    if (res.status == AllergyStatus.safe) return true;
    if (_allergies.includeSwaps && res.status == AllergyStatus.swapRequired) {
      return true;
    }
    return false;
  }

  ({String? tag, String? swapHint}) _tagForRecipe({
    required String ingredientsText,
    required List<ProfilePerson> activeProfiles,
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

    // ✅ NEW: Handle dynamic labels for multi-select
    if (_allergies.mode == SuitabilityMode.specificPeople) {
      if (activeProfiles.isEmpty) return (tag: null, swapHint: null);
      if (activeProfiles.length == 1) {
        return (tag: '✅ Safe for ${activeProfiles.first.name}', swapHint: null);
      } else if (activeProfiles.length == 2) {
        return (tag: '✅ Safe for ${activeProfiles[0].name} & ${activeProfiles[1].name}', swapHint: null);
      } else {
        return (tag: '✅ Safe for ${activeProfiles.length} selected', swapHint: null);
      }
    }

    if (_allergies.mode == SuitabilityMode.allChildren) {
      return (tag: '✅ Safe for all children', swapHint: null);
    }
    return (tag: '✅ Safe for whole family', swapHint: null);
  }

  // ------------------------
  // Visibility (and tag caching)
  // ------------------------

  void _recomputeVisible() {
    if (!_indexReady) return;

    final q = _query.trim().toLowerCase();

    // ✅ OPTIMIZATION: Fast path: no filters, no search, allergies off => show all, no tag work
    if (!_allergies.enabled && q.isEmpty && _filtersAreDefault) {
      if (!mounted) return;
      setState(() {
        _visible = List<Map<String, dynamic>>.from(_items);
        _tagById.clear();
      });
      return;
    }

    final activeProfiles =
        _allergies.enabled ? _activeProfilesForAllergies() : _allPeople;
    final hasAnyAllergies = _allergies.enabled &&
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

    final next = <Map<String, dynamic>>[];
    final nextTags = <int, ({String? tag, String? swapHint})>{};

    for (final r in _items) {
      final id = r['id'];
      if (id is! int) continue;

      final ix = _indexById[id];
      if (ix == null) continue;

      final matchesCourse =
          (_filters.course == 'All') || ix.courses.contains(_filters.course);
      if (!matchesCourse) continue;

      final matchesCuisine =
          (_filters.cuisine == 'All') || ix.cuisines.contains(_filters.cuisine);
      if (!matchesCuisine) continue;

      final matchesSuitable = (_filters.suitableFor == 'All') ||
          ix.suitable.contains(_filters.suitableFor);
      if (!matchesSuitable) continue;

      final matchesNutrition = (_filters.nutritionTag == 'All') ||
          ix.nutrition.contains(_filters.nutritionTag);
      if (!matchesNutrition) continue;

      final matchesCollection = (_filters.collection == 'All') ||
          ix.collections.contains(_filters.collection);
      if (!matchesCollection) continue;

      if (q.isNotEmpty) {
        final titleMatch = ix.titleLower.contains(q);
        final ingredientMatch = ix.ingredientsLower.contains(q);
        if (!(titleMatch || ingredientMatch)) continue;
      }

      if (hasAnyAllergies) {
        bool allowed = true;
        for (final p in activeProfiles) {
          if (!_isAllowedForPerson(p: p, ingredientsText: ix.ingredientsText)) {
            allowed = false;
            break;
          }
        }
        if (!allowed) continue;

        // ✅ Precompute tag once for this visible recipe (no per-row eval)
        nextTags[id] = _tagForRecipe(
          ingredientsText: ix.ingredientsText,
          activeProfiles: activeProfiles,
        );
      }

      next.add(r);
    }

    if (!mounted) return;
    setState(() {
      _visible = next;
      _tagById
        ..clear()
        ..addAll(nextTags);
    });
  }

  // ------------------------
  // UI helpers
  // ------------------------

  Widget _favBadge() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
    );
  }

  // ------------------------
  // UI
  // ------------------------

  @override
  Widget build(BuildContext context) {
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

    final lockCourse = widget.lockCourse ?? false;
    final lockCollection = widget.lockCollection ?? false;

    final activeProfiles =
        _allergies.enabled ? _activeProfilesForAllergies() : _allPeople;
    final hasAnyAllergies =
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              SearchPill(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                hintText: 'Search recipes or by ingredients',
                onChanged: (v) {
                  _searchDebounce?.cancel();
                  _searchDebounce =
                      Timer(const Duration(milliseconds: 200), () {
                    if (!mounted) return;
                    setState(() => _query = v);
                    _recomputeVisible();
                  });
                },
                onSubmitted: (_) {
                  _searchDebounce?.cancel();
                  _recomputeVisible();
                },
                onClear: () {
                  _searchDebounce?.cancel();
                  _searchCtrl.clear();
                  setState(() => _query = '');
                  _recomputeVisible();
                },
              ),
              const SizedBox(height: 10),

              RecipeFilterBar(
                filters: _filters,
                allergies: _allergies,
                courseOptions: _courseOptionsCached,
                cuisineOptions: _cuisineOptionsCached,
                suitableForOptions: _suitableOptionsCached,
                nutritionOptions: _nutritionOptionsCached,
                collectionOptions: _collectionOptionsCached,
                adults: _adults,
                children: _children,
                lockCourse: lockCourse,
                lockCollection: lockCollection,
                lockCuisine: false,
                lockSuitableFor: false,
                lockNutrition: false,
                householdLoading: _loadingHousehold,
                householdError: _householdError,
                onRetryHousehold: _listenToHousehold,
                onFiltersApplied: (next) {
                  setState(() => _filters = next);
                  // ✅ OPTIMIZATION: Give UI a microtask to finish closing sheet/pill before heavy loop
                  Future.microtask(() => _recomputeVisible());
                },
                onAllergiesApplied: (next) {
                  setState(() => _allergies = next);
                  // ✅ OPTIMIZATION: Give UI a microtask to finish closing sheet/pill before heavy loop
                  Future.microtask(() => _recomputeVisible());
                },
              ),

              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Showing ${_visible.length} recipes',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),

              if (_allergies.enabled) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hasAnyAllergies
                        ? 'Allergies considered: ${_activeAllergiesLabelFor(_activeProfilesForAllergies())}'
                        : 'No allergies saved.',
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
                _recipesLoaded = true;

                // default: show all (instant)
                _visible = List<Map<String, dynamic>>.from(updated);
                _tagById.clear();
              });

              _rebuildIndexAndOptions(force: true);

              if (_allergies.enabled ||
                  _query.trim().isNotEmpty ||
                  !_filtersAreDefault) {
                _recomputeVisible();
              }
            },
            child: ListView.separated(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _visible.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final r = _visible[index];
                final id = r['id'] as int?;
                final title = _titleOf(r);
                final thumb = _thumbOf(r);

                // ✅ Key speed win: only show allergy tags when allergies enabled
                final tagData =
                    (_allergies.enabled && id != null) ? _tagById[id] : null;

                // ✅ UPDATED: Removed course, only showing allergy info
                final subtitleParts = <String>[
                  if (_allergies.enabled && tagData?.tag != null) tagData!.tag!,
                  if (_allergies.enabled && tagData?.swapHint != null)
                    tagData!.swapHint!,
                ];
                final subtitle = subtitleParts
                    .where((s) => s.trim().isNotEmpty)
                    .join(' • ');

                final isFav = _isFavorited(id);

                return RecipeCard(
                  title: title,
                  subtitle: subtitle.isEmpty ? null : subtitle,
                  imageUrl: thumb,
                  compact: false,
                  badge: isFav ? _favBadge() : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: id == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => RecipeDetailScreen(id: id)),
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
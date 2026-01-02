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

import '../shared/search_pill.dart';
import 'widgets/recipe_card.dart';
import 'widgets/recipe_filters_ui.dart'; // ✅ Gets Multi-Select Models from here

/// Minimal local unawaited helper
void unawaited(Future<void> f) {}

class _RecipeIndex {
  final int id;
  final String titleLower;
  final String ingredientsText;
  final String ingredientsLower;
  final List<String> courses;
  final List<String> collections; // ✅ should be NAMES
  final List<String> cuisines;
  final List<String> suitable;
  final List<String> nutrition;

  // ✅ Fields for New Swap Logic
  final List<String> allergyTags; // names are fine
  final String swapText;

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
    required this.allergyTags,
    required this.swapText,
  });
}

class _CStyle {
  static const bool showSubtitle = false;

  static TextStyle meta(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
        height: 1.2,
        fontSize: 14,
        fontVariations: const [FontVariation('wght', 600)],
      );
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
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  Timer? _searchDebounce;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  RecipeFilterSelection _filters = const RecipeFilterSelection();

  // ✅ Multi-Select Ready
  AllergiesSelection _allergies = const AllergiesSelection(
    enabled: true,
    mode: SuitabilityMode.wholeFamily,
    includeSwaps: true,
  );

  List<Map<String, dynamic>> _visible = [];
  final Map<int, ({String? tag, String? swapHint})> _tagById = {};

  // Maps
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
  Map<String, String> _allergenIdToName = {};

  bool _loadingTerms = false;
  bool _didApplyInitialCourse = false;
  bool _didApplyInitialCollection = false;
  bool _recipesLoaded = false;
  bool _termsLoaded = false;
  DateTime? _cacheUpdatedAt;
  bool _loadedFromCache = false;
  final Map<int, _RecipeIndex> _indexById = {};
  bool _indexReady = false;

  List<String> _courseOptionsCached = const ['All'];
  List<String> _collectionOptionsCached = const ['All'];
  List<String> _cuisineOptionsCached = const ['All'];
  List<String> _suitableOptionsCached = const ['All'];
  List<String> _nutritionOptionsCached = const ['All'];

  // Household
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  bool _loadingHousehold = true;
  String? _householdError;
  final List<ProfilePerson> _adults = [];
  final List<ProfilePerson> _children = [];

  // Favourites
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

  // ✅ New Swap Logic Helper
  String _swapTextOf(Map<String, dynamic> r) {
    if (r['recipe'] is Map) {
      final recipeData = r['recipe'] as Map;
      if (recipeData['custom_fields'] is Map) {
        final custom = recipeData['custom_fields'] as Map;
        if (custom['ingredient_swaps'] != null) {
          return custom['ingredient_swaps'].toString();
        }
      }
    }
    if (r['ingredient_swaps'] != null) return r['ingredient_swaps'].toString();
    if (r['meta'] is Map) {
      final meta = r['meta'] as Map;
      if (meta['ingredient_swaps'] != null) {
        return meta['ingredient_swaps'].toString();
      }
    }
    return '';
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

          if (!_allergies.enabled && _query.trim().isEmpty && _filtersAreDefault) {
            _visible = List<Map<String, dynamic>>.from(cached);
            _tagById.clear();
          }
        });

        _rebuildIndexAndOptions(force: true);

        if (_allergies.enabled || _query.trim().isNotEmpty || !_filtersAreDefault) {
          _recomputeVisible();
        }
      }
    } catch (_) {}
  }

  List<String> _termsOfField(
    Map<String, dynamic> r,
    String field,
    Map<String, String> idToName,
  ) {
    final v = r[field];
    List<String> raw = [];
    if (v is List) {
      raw = v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    } else if (v is int) {
      raw = [v.toString()];
    } else if (v is String && v.trim().isNotEmpty) {
      raw = [v.trim()];
    }
    final mapped = raw.map((x) => idToName[x] ?? x).toList();
    return mapped.where((s) => s.trim().isNotEmpty).toSet().toList()..sort();
  }

  // ✅ Collections helper: prefer nested recipe.tags.collections NAMES (like CoursePage fix)
  List<String> _collectionNamesFromRecipeTags(Map<String, dynamic> r) {
    try {
      final recipe = r['recipe'];
      if (recipe is Map) {
        final tags = recipe['tags'];
        if (tags is Map) {
          final cols = tags['collections'] ?? tags['collection'];
          if (cols is List) {
            final out = <String>[];
            for (final c in cols) {
              if (c is Map) {
                final name = (c['name'] ?? '').toString().trim();
                if (name.isNotEmpty) out.add(name);
              } else if (c is String) {
                final s = c.trim();
                if (s.isNotEmpty) out.add(s);
              }
            }
            if (out.isNotEmpty) return out.toSet().toList()..sort();
          }
        }
      }
    } catch (_) {}
    return const [];
  }

  List<String> _coursesOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_course', _courseIdToName);

  // ✅ FIX: collections should be names; fall back to mapping IDs if tags missing
  List<String> _collectionsOf(Map<String, dynamic> r) {
    final fromTags = _collectionNamesFromRecipeTags(r);
    if (fromTags.isNotEmpty) return fromTags;
    return _termsOfField(r, 'wprm_collections', _collectionIdToName);
  }

  List<String> _cuisinesOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_cuisine', _cuisineIdToName);

  List<String> _suitableForOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_suitable_for', _suitableIdToName);

  List<String> _nutritionTagsOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_nutrition_tag', _nutritionIdToName);

  // ✅ Allergy tags are better from recipe.tags.allergies (names) but this mapping is OK if your term endpoint exists.
  List<String> _allergyTagsOf(Map<String, dynamic> r) {
    // prefer nested names if present
    try {
      final recipe = r['recipe'];
      if (recipe is Map && recipe['tags'] is Map) {
        final tags = recipe['tags'] as Map;
        final a = tags['allergies'];
        if (a is List) {
          final out = <String>[];
          for (final item in a) {
            if (item is Map) {
              final name = (item['name'] ?? '').toString().trim();
              if (name.isNotEmpty) out.add(name);
            }
          }
          if (out.isNotEmpty) return out.toSet().toList()..sort();
        }
      }
    } catch (_) {}

    // fallback: map ids from top-level wprm_allergies
    return _termsOfField(r, 'wprm_allergies', _allergenIdToName);
  }

  void _applyInitialCourseIfNeeded() {
    if (_didApplyInitialCourse) return;
    final slug = widget.initialCourseSlug?.trim();
    if (slug == null || slug.isEmpty) {
      _didApplyInitialCourse = true;
      return;
    }
    final name = _courseSlugToName[slug];
    if (name == null || name.trim().isEmpty) return;
    if (_courseOptionsCached.contains(name)) {
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
    if (name == null || name.trim().isNotEmpty != true) return;
    if (_collectionOptionsCached.contains(name)) {
      _filters = _filters.copyWith(collection: name);
      _didApplyInitialCollection = true;
    }
  }

  void _maybeFinishBoot() {
    if (!_recipesLoaded) return;
    _applyInitialCourseIfNeeded();
    _applyInitialCollectionIfNeeded();

    final needCourse = (widget.initialCourseSlug?.trim().isNotEmpty ?? false);
    final needCollection = (widget.initialCollectionSlug?.trim().isNotEmpty ?? false);
    final courseReady = !needCourse || _didApplyInitialCourse;
    final collectionReady = !needCollection || _didApplyInitialCollection;

    if (courseReady && collectionReady) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _visible = List<Map<String, dynamic>>.from(_items);
        _tagById.clear();
      });
      if (!_filtersAreDefault) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeVisible());
      }
    }
  }

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
            final raw = d.data()['recipeId'];
            final id = (raw is int) ? raw : int.tryParse('$raw') ?? -1;
            if (id > 0) next.add(id);
          }
          if (!mounted) return;
          setState(() {
            _favoriteIds..clear()..addAll(next);
            _loadingFavs = false;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _loadingFavs = false;
          });
        },
      );
    });
  }

  bool _isFavorited(int? recipeId) => recipeId != null && _favoriteIds.contains(recipeId);

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

        void parse(List raw, List<ProfilePerson> target, PersonType type, String prefix) {
          for (var i = 0; i < raw.length; i++) {
            final p = raw[i];
            if (p is! Map) continue;
            final name = (p['name'] ?? '').toString().trim();
            if (name.isEmpty) continue;
            final hasAllergies = (p['hasAllergies'] == true);
            final parsed = <String>[];
            if (p['allergies'] is List) {
              for (final x in p['allergies']) {
                final k = _canonicalAllergyKey(x.toString());
                if (k != null) parsed.add(k);
              }
            }
            target.add(ProfilePerson(
              id: '${prefix}_$i',
              type: type,
              name: name,
              hasAllergies: hasAllergies,
              allergies: hasAllergies ? (parsed.toSet().toList()..sort()) : [],
            ));
          }
        }

        parse(rawAdults, adults, PersonType.adult, 'adult');
        parse(rawChildren, children, PersonType.child, 'child');

        if (!mounted) return;
        setState(() {
          _adults..clear()..addAll(adults);
          _children..clear()..addAll(children);
          _loadingHousehold = false;
          _householdError = null;

          if (_allergies.mode == SuitabilityMode.specificPeople) {
            final ids = _allergies.personIds
                .where((id) => _allPeople.any((p) => p.id == id))
                .toSet();
            if (ids.isEmpty) {
              _allergies = _allergies.copyWith(
                mode: SuitabilityMode.wholeFamily,
                personIds: {},
                includeSwaps: false,
              );
            } else {
              _allergies = _allergies.copyWith(personIds: ids);
            }
          }
        });

        if (_allergies.enabled || _query.trim().isNotEmpty || !_filtersAreDefault) {
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
    return set.toList().map(_prettyAllergy).join(', ');
  }

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
      final allergenById = <String, String>{};

      Future<void> loadTax({
        required String endpoint,
        required Map<String, String> byId,
        Map<String, String>? bySlug,
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
          for (final t in data.cast<Map<String, dynamic>>()) {
            final id = t['id']?.toString();
            final name = (t['name'] ?? '').toString().trim();
            final slug = (t['slug'] ?? '').toString().trim();
            if (id != null && name.isNotEmpty) byId[id] = name;
            if (bySlug != null && slug.isNotEmpty && name.isNotEmpty) bySlug[slug] = name;
          }
          if (data.length < perPage) break;
          page++;
        }
      }

      await Future.wait([
        loadTax(endpoint: 'wprm_course', byId: courseById, bySlug: courseBySlug),
        loadTax(endpoint: 'wprm_collections', byId: colById, bySlug: colBySlug),
        loadTax(endpoint: 'wprm_cuisine', byId: cuisineById, bySlug: cuisineBySlug),
        loadTax(endpoint: 'wprm_suitable_for', byId: suitableById, bySlug: suitableBySlug),
        loadTax(endpoint: 'wprm_nutrition_tag', byId: nutritionById, bySlug: nutritionBySlug),
        loadTax(endpoint: 'wprm_allergies', byId: allergenById),
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
        _allergenIdToName = allergenById;

        _termsLoaded = true;
      });

      _rebuildIndexAndOptions(force: true);
      if (_recipesLoaded) _recomputeVisible();
    } catch (_) {
      if (!mounted) return;
      setState(() => _termsLoaded = true);
      _rebuildIndexAndOptions(force: true);
    } finally {
      if (mounted) setState(() => _loadingTerms = false);
    }
  }

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
      unawaited(Future.delayed(const Duration(seconds: 2), _upgradeItemsFromCacheIfNewer));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _recipesLoaded = true;
        _loading = false;
      });
    }
  }

  void _rebuildIndexAndOptions({bool force = false}) {
    if (_items.isEmpty) {
      _indexById.clear();
      _indexReady = true;
      return;
    }
    if (!force && _indexReady && _indexById.length == _items.length) return;

    final cSet = <String>{}, colSet = <String>{}, cuiSet = <String>{}, sSet = <String>{}, nSet = <String>{};
    _indexById.clear();

    for (final r in _items) {
      final id = r['id'];
      if (id is! int) continue;

      final idx = _RecipeIndex(
        id: id,
        titleLower: _titleOf(r).toLowerCase(),
        ingredientsText: _ingredientsTextOf(r),
        ingredientsLower: _ingredientsTextOf(r).toLowerCase(),
        courses: _coursesOf(r),
        collections: _collectionsOf(r), // ✅ now names
        cuisines: _cuisinesOf(r),
        suitable: _suitableForOf(r),
        nutrition: _nutritionTagsOf(r),
        allergyTags: _allergyTagsOf(r),
        swapText: _swapTextOf(r),
      );

      cSet.addAll(idx.courses);
      colSet.addAll(idx.collections);
      cuiSet.addAll(idx.cuisines);
      sSet.addAll(idx.suitable);
      nSet.addAll(idx.nutrition);

      _indexById[id] = idx;
    }

    if (!mounted) return;
    setState(() {
      _courseOptionsCached = ['All', ...(cSet.toList()..sort())];
      _collectionOptionsCached = ['All', ...(colSet.toList()..sort())];
      _cuisineOptionsCached = ['All', ...(cuiSet.toList()..sort())];
      _suitableOptionsCached = ['All', ...(sSet.toList()..sort())];
      _nutritionOptionsCached = ['All', ...(nSet.toList()..sort())];
      _indexReady = true;

      _filters = _filters.copyWith(
        course: _clampToOptions(_filters.course, _courseOptionsCached),
        cuisine: _clampToOptions(_filters.cuisine, _cuisineOptionsCached),
        suitableFor: _clampToOptions(_filters.suitableFor, _suitableOptionsCached),
        nutritionTag: _clampToOptions(_filters.nutritionTag, _nutritionOptionsCached),
        collection: _clampToOptions(_filters.collection, _collectionOptionsCached),
      );
    });
  }

  String _clampToOptions(String c, List<String> o) => o.contains(c) ? c : 'All';

  bool _isAllowedForPerson({required ProfilePerson p, required _RecipeIndex ix}) {
    if (!p.hasAllergies || p.allergies.isEmpty) return true;

    final res = AllergyEngine.evaluate(
      recipeAllergyTags: ix.allergyTags,
      swapFieldText: ix.swapText,
      userAllergies: p.allergies,
    );

    if (res.status == AllergyStatus.safe) return true;
    if (_allergies.includeSwaps && res.status == AllergyStatus.swapRequired) return true;
    return false;
  }

  ({String? tag, String? swapHint}) _tagForRecipe({
    required _RecipeIndex ix,
    required List<ProfilePerson> activeProfiles,
  }) {
    final anyActive =
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);
    if (!anyActive) return (tag: null, swapHint: null);

    bool anySwap = false;
    bool anyNotSuitable = false;

    for (final p in activeProfiles) {
      if (!p.hasAllergies || p.allergies.isEmpty) continue;

      final res = AllergyEngine.evaluate(
        recipeAllergyTags: ix.allergyTags,
        swapFieldText: ix.swapText,
        userAllergies: p.allergies,
      );

      if (res.status == AllergyStatus.notSuitable) {
        anyNotSuitable = true;
      } else if (res.status == AllergyStatus.swapRequired) {
        anySwap = true;
      }
    }

    if (anyNotSuitable) return (tag: '⛔ Not suitable', swapHint: null);

    if (anySwap) {
      final label = activeProfiles.length > 1
          ? '⚠️ Swap required (one or more)'
          : '⚠️ Swap required';
      return (tag: label, swapHint: null);
    }

    if (_allergies.mode == SuitabilityMode.specificPeople) {
      if (activeProfiles.length == 1) {
        return (tag: '✅ Safe for ${activeProfiles.first.name}', swapHint: null);
      }
      if (activeProfiles.length > 1) {
        return (tag: '✅ Safe for ${activeProfiles.length} selected', swapHint: null);
      }
    }
    if (_allergies.mode == SuitabilityMode.allChildren) {
      return (tag: '✅ Safe for all children', swapHint: null);
    }
    return (tag: '✅ Safe for whole family', swapHint: null);
  }

  void _recomputeVisible() {
    if (!_indexReady) return;
    final q = _query.trim().toLowerCase();

    if (!_allergies.enabled && q.isEmpty && _filtersAreDefault) {
      if (mounted) {
        setState(() {
          _visible = List<Map<String, dynamic>>.from(_items);
          _tagById.clear();
        });
      }
      return;
    }

    final activeProfiles = _allergies.enabled ? _activeProfilesForAllergies() : _allPeople;
    final hasAnyAllergies = _allergies.enabled &&
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

    final next = <Map<String, dynamic>>[];
    final nextTags = <int, ({String? tag, String? swapHint})>{};

    for (final r in _items) {
      final id = r['id'];
      if (id is! int) continue;
      final ix = _indexById[id];
      if (ix == null) continue;

      if (_filters.course != 'All' && !ix.courses.contains(_filters.course)) continue;
      if (_filters.cuisine != 'All' && !ix.cuisines.contains(_filters.cuisine)) continue;
      if (_filters.suitableFor != 'All' && !ix.suitable.contains(_filters.suitableFor)) continue;
      if (_filters.nutritionTag != 'All' && !ix.nutrition.contains(_filters.nutritionTag)) continue;
      if (_filters.collection != 'All' && !ix.collections.contains(_filters.collection)) continue;

      if (q.isNotEmpty &&
          !ix.titleLower.contains(q) &&
          !ix.ingredientsLower.contains(q)) continue;

      if (hasAnyAllergies) {
        bool allowed = true;
        for (final p in activeProfiles) {
          if (!_isAllowedForPerson(p: p, ix: ix)) {
            allowed = false;
            break;
          }
        }
        if (!allowed) continue;

        nextTags[id] = _tagForRecipe(ix: ix, activeProfiles: activeProfiles);
      }

      next.add(r);
    }

    if (!mounted) return;
    setState(() {
      _visible = next;
      _tagById..clear()..addAll(nextTags);
    });
  }

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

    final activeProfiles = _allergies.enabled ? _activeProfilesForAllergies() : _allPeople;
    final hasAnyAllergies = activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

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
                  _searchDebounce = Timer(const Duration(milliseconds: 200), () {
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
                lockCourse: widget.lockCourse ?? false,
                lockCollection: widget.lockCollection ?? false,
                householdLoading: _loadingHousehold,
                householdError: _householdError,
                onRetryHousehold: _listenToHousehold,
                onFiltersApplied: (next) {
                  setState(() => _filters = next);
                  Future.microtask(_recomputeVisible);
                },
                onAllergiesApplied: (next) {
                  setState(() => _allergies = next);
                  Future.microtask(_recomputeVisible);
                },
              ),
              const SizedBox(height: 8),
              if (_allergies.enabled) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hasAnyAllergies
                        ? 'Allergies considered: ${_activeAllergiesLabelFor(activeProfiles)}'
                        : 'No allergies saved.',
                    style: _CStyle.meta(context),
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
              if (!mounted) return;
              setState(() {
                _items = updated;
                _visible = List<Map<String, dynamic>>.from(updated);
                _tagById.clear();
              });
              _rebuildIndexAndOptions(force: true);
              if (_allergies.enabled || _query.isNotEmpty || !_filtersAreDefault) {
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
                final tagData = (_allergies.enabled && id != null) ? _tagById[id] : null;

                final subtitleParts = <String>[
                  if (_allergies.enabled && tagData?.tag != null) tagData!.tag!,
                  if (_allergies.enabled && tagData?.swapHint != null) tagData!.swapHint!,
                ];
                final subtitle = subtitleParts.where((s) => s.trim().isNotEmpty).join(' • ');

                return RecipeCard(
                  title: title,
                  subtitle: subtitle.isEmpty ? null : subtitle,
                  imageUrl: thumb,
                  compact: false,
                  badge: _isFavorited(id) ? _favBadge() : null,
                  trailing: const Icon(Icons.chevron_right),
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

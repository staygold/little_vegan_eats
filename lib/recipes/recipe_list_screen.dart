// lib/recipes/recipe_list_screen.dart
import 'dart:async';
import 'dart:ui' show FontVariation;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart'; 
import '../theme/app_theme.dart';
import '../shared/search_pill.dart';
import '../utils/text.dart';

import 'allergy_engine.dart';
import 'family_profile.dart';
import 'family_profile_repository.dart';
import 'household_food_policy.dart';
import 'recipe_cache.dart';
import 'recipe_detail_screen.dart';
import 'recipe_index.dart';
import 'recipe_index_builder.dart';
import 'recipe_repository.dart';
import 'food_policy_core.dart';
import 'widgets/recipe_filters_ui.dart';
import 'widgets/smart_recipe_card.dart'; 

/// Minimal local unawaited helper
void unawaited(Future<void> f) {}

class _CStyle {
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
    this.lockCourse = false,
    this.initialCollectionSlug,
    this.lockCollection = false,
    this.pageTitle, 
  });

  final String? initialCourseSlug;
  final bool lockCourse;
  final String? initialCollectionSlug;
  final bool lockCollection;
  final String? pageTitle;

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

  AllergiesSelection _allergies = const AllergiesSelection(
    enabled: true,
    mode: SuitabilityMode.wholeFamily,
    includeSwaps: true,
  );

  List<Map<String, dynamic>> _visible = [];
  
  // taxonomy maps
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
  DateTime? _cacheUpdatedAt;

  final Map<int, RecipeIndex> _indexById = {};
  bool _indexReady = false;

  List<String> _courseOptionsCached = const ['All'];
  List<String> _collectionOptionsCached = const ['All'];
  List<String> _cuisineOptionsCached = const ['All'];
  List<String> _suitableOptionsCached = const ['All'];
  List<String> _nutritionOptionsCached = const ['All'];

  // household (repo-driven)
  StreamSubscription<FamilyProfile>? _userSub;
  StreamSubscription<User?>? _authHouseSub;
  bool _loadingHousehold = true;
  String? _householdError;
  FamilyProfile _family = const FamilyProfile(adults: [], children: []);

  // repo instance (source of truth)
  final FamilyProfileRepository _familyRepo = FamilyProfileRepository();

  // one façade service
  late final HouseholdFoodPolicy _policy =
      HouseholdFoodPolicy(familyRepo: _familyRepo);

  // favourites
  StreamSubscription<User?>? _authFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  bool _loadingFavs = true;
  final Set<int> _favoriteIds = <int>{};

  // ------------------------
  // Helpers
  // ------------------------
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

  // ✅ IMPROVED SWAP FINDER: Checks 5 different locations
  String _swapTextOf(Map<String, dynamic> r) {
    String? tryGet(dynamic val) {
      if (val != null && val.toString().trim().isNotEmpty) {
        return val.toString();
      }
      return null;
    }

    // 1. Top Level
    var found = tryGet(r['ingredient_swaps']) ?? tryGet(r['swap_text']);
    if (found != null) return stripHtml(found).trim();

    // 2. Meta
    if (r['meta'] is Map) {
      final m = r['meta'];
      found = tryGet(m['ingredient_swaps']) ?? tryGet(m['wprm_ingredient_swaps']);
      if (found != null) return stripHtml(found).trim();
    }

    // 3. Inner Recipe
    final recipe = r['recipe'];
    if (recipe is Map) {
      found = tryGet(recipe['ingredient_swaps']) ?? tryGet(recipe['swap_text']);
      if (found != null) return stripHtml(found).trim();

      // 4. Custom Fields inside Recipe
      if (recipe['custom_fields'] is Map) {
        final cf = recipe['custom_fields'];
        found = tryGet(cf['ingredient_swaps']);
        if (found != null) return stripHtml(found).trim();
      }
    }

    return '';
  }

  List<String> _termsOfField(Map<String, dynamic> r, String field, Map<String, String> idToName) {
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

  List<String> _allergyTagsOf(Map<String, dynamic> r) {
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
    return _termsOfField(r, 'wprm_allergies', _allergenIdToName);
  }

  Map<String, dynamic> _normaliseForIndex(Map<String, dynamic> r) {
    final id = r['id'];
    if (id is! int) return const {};

    return <String, dynamic>{
      'id': id,
      'title': _titleOf(r),
      'ingredients': _ingredientsTextOf(r),
      'wprm_course': _coursesOf(r),
      'wprm_collections': _collectionsOf(r),
      'wprm_cuisine': _cuisinesOf(r),
      'wprm_suitable_for': _suitableForOf(r),
      'wprm_nutrition_tag': _nutritionTagsOf(r),
      'recipe': r['recipe'],
      'meta': r['meta'],
      'ingredient_swaps': _swapTextOf(r),
      'wprm_allergies': _allergyTagsOf(r),
    };
  }

  // ✅ UPDATED: Dynamic labels based on who is selected
  String? _calculateAllergyStatus(RecipeIndex ix, Map<String, dynamic> r) {
    final blockedNames = <String>[];
    final swapNames = <String>[];

    // Use active profiles if specific mode, else all people
    final profilesToCheck = _allergies.mode == SuitabilityMode.specificPeople
        ? _family.allPeople.where((p) => _allergies.personIds.contains(p.id))
        : (_allergies.mode == SuitabilityMode.allChildren ? _family.children : _family.allPeople);

    // 1. Run the Engine for everyone selected
    for (final person in profilesToCheck) {
      if (person.allergies.isEmpty) continue;

      final result = AllergyEngine.evaluate(
        recipeAllergyTags: ix.allergies,
        swapFieldText: _swapTextOf(r),
        userAllergies: person.allergies,
      );

      if (result.status == AllergyStatus.notSuitable) {
        blockedNames.add(person.name);
      } else if (result.status == AllergyStatus.swapRequired) {
        swapNames.add(person.name);
      }
    }

    // 2. Priority: Hard Block (Red)
    if (blockedNames.isNotEmpty) {
      final unique = blockedNames.toSet().toList();
      if (unique.length == 1) return "Not suitable for ${unique.first}";
      if (unique.length == 2) return "Not suitable for ${unique.join(' & ')}";
      return "Not suitable for ${unique.length} people";
    }

    // 3. Secondary: Needs Swap (Amber)
    if (swapNames.isNotEmpty) {
      final unique = swapNames.toSet().toList();
      if (unique.length == 1) return "Needs swap for ${unique.first}";
      if (unique.length == 2) return "Needs swap for ${unique.join(' & ')}";
      return "Needs swap for ${unique.length} people";
    }
    
    // 4. Safe (Green) - DYNAMIC LABEL LOGIC
    final hasAnyAllergies = profilesToCheck.any((p) => p.allergies.isNotEmpty);
    
    if (hasAnyAllergies) {
      if (_allergies.mode == SuitabilityMode.allChildren) {
         return "Safe for all children";
      }
      
      if (_allergies.mode == SuitabilityMode.specificPeople) {
         final names = profilesToCheck.map((p) => p.name).toSet().toList();
         if (names.length == 1) return "Safe for ${names.first}";
         if (names.length == 2) return "Safe for ${names.join(' & ')}";
         return "Safe for selected people";
      }
      
      // Default for SuitabilityMode.wholeFamily
      return "Safe for whole family";
    }

    return null; 
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
    if (name == null || name.trim().isEmpty) return;
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
      });
      if (!_filtersAreDefault || _allergies.enabled || _query.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeVisible());
      }
    } else if (!_loadingTerms) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _visible = List<Map<String, dynamic>>.from(_items);
      });
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
    _authHouseSub?.cancel();
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

      final col = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('favorites');

      _favSub = col.snapshots().listen((snap) {
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
      }, onError: (_) {
        if (!mounted) return;
        setState(() => _loadingFavs = false);
      });
    });
  }

  bool _isFavorited(int? recipeId) => recipeId != null && _favoriteIds.contains(recipeId);

  void _listenToHousehold() {
    _authHouseSub?.cancel();
    _userSub?.cancel();

    if (mounted) {
      setState(() {
        _loadingHousehold = true;
        _householdError = null;
      });
    }

    _authHouseSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _userSub?.cancel();

      if (u == null) {
        if (!mounted) return;
        setState(() {
          _loadingHousehold = false;
          _householdError = null;
          _family = const FamilyProfile(adults: [], children: []);
        });
        if (_allergies.enabled || _query.trim().isNotEmpty || !_filtersAreDefault) {
          _recomputeVisible();
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _loadingHousehold = true;
        _householdError = null;
      });

      _userSub = _familyRepo.watchFamilyProfile().listen((nextFamily) {
        if (_allergies.mode == SuitabilityMode.specificPeople) {
          final ids = _allergies.personIds.where((id) => nextFamily.allPeople.any((p) => p.id == id)).toSet();
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

        if (!mounted) return;
        setState(() {
          _family = nextFamily;
          _loadingHousehold = false;
          _householdError = null;
        });

        if (_allergies.enabled || _query.trim().isNotEmpty || !_filtersAreDefault) {
          _recomputeVisible();
        }
      }, onError: (e) {
        if (!mounted) return;
        setState(() {
          _loadingHousehold = false;
          _householdError = e.toString();
        });
      });
    });
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
        _loadingTerms = false;
      });

      _rebuildIndexAndOptions(force: true);
      _maybeFinishBoot();
      
      if (_recipesLoaded) _recomputeVisible();
    } catch (_) {
      if (mounted) setState(() => _loadingTerms = false);
      _rebuildIndexAndOptions(force: true);
      _maybeFinishBoot();
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
        _recipesLoaded = true;
      });
      _rebuildIndexAndOptions(force: true);
      _maybeFinishBoot();
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

    final cSet = <String>{};
    final colSet = <String>{};
    final cuiSet = <String>{};
    final sSet = <String>{};
    final nSet = <String>{};

    final normalised = <Map<String, dynamic>>[];
    for (final r in _items) {
      final m = _normaliseForIndex(r);
      if (m.isNotEmpty) normalised.add(m);
    }

    _indexById
      ..clear()
      ..addAll(RecipeIndexBuilder.buildById(normalised));

    for (final ix in _indexById.values) {
      cSet.addAll(ix.courses);
      colSet.addAll(ix.collections);
      cuiSet.addAll(ix.cuisines);
      sSet.addAll(ix.suitable);
      nSet.addAll(ix.nutrition);
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

    _applyInitialCourseIfNeeded();
    _applyInitialCollectionIfNeeded();
    _maybeFinishBoot();
  }

  String _clampToOptions(String c, List<String> o) => o.contains(c) ? c : 'All';

  void _recomputeVisible() {
    if (!_indexReady) return;

    final q = _query.trim().toLowerCase();
    if (!_allergies.enabled && q.isEmpty && _filtersAreDefault) {
      if (!mounted) return;
      setState(() {
        _visible = List<Map<String, dynamic>>.from(_items);
      });
      return;
    }

    final res = _policy.filterRecipes(
      items: _items,
      indexById: _indexById,
      filters: _filters,
      query: _query,
      family: _family,
      selection: _allergies,
    );

    if (!mounted) return;
    setState(() {
      _visible = res.visible;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_items.isEmpty && _error != null) {
      content = Center(
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
    } else {
      final activeProfiles = _policy.activeProfiles(family: _family, selection: _allergies);
      final hasAnyAllergies = _policy.hasAnyAllergies(profiles: activeProfiles, selection: _allergies);
      final youngestChild = _policy.youngestChild(_family);
      final youngestMonths = _policy.youngestChildAgeMonths(_family);
      final youngestChildName = youngestChild?.name;
      final childNames = _family.children.map((c) => c.name).toList();

      content = Column(
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
                  adults: _family.adults,
                  children: _family.children,
                  lockCourse: widget.lockCourse,
                  lockCollection: widget.lockCollection,
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
                          ? 'Allergies considered: ${_policy.activeAllergiesLabel(activeProfiles)}'
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

                  final ix = (id != null) ? _indexById[id] : null;

                 final String? allergyStatus = (ix == null)
    ? null
    : _policy.allergyStatusLabel(
        ix: ix,
        item: r,
        family: _family,
        selection: _allergies,
      );

                  final babyTag = (ix != null)
                      ? FoodPolicyCore.babySuitabilityLabel(
                          ix: ix,
                          youngestChild: youngestChild,
                          youngestMonths: youngestMonths,
                      )
                      : null;

                  return SmartRecipeCard(
                    title: title,
                    imageUrl: thumb,
                    isFavorite: _isFavorited(id),
                    onTap: id == null ? null : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: id)),
                    ),
                    tags: ix?.suitable ?? [],
                    allergyStatus: allergyStatus,
                    ageWarning: babyTag,
                    childNames: childNames,
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    if (widget.pageTitle != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFECF3F4),
        body: Column(
          children: [
            SubHeaderBar(title: widget.pageTitle!),
            Expanded(child: content),
          ],
        ),
      );
    }

    return content;
  }
}
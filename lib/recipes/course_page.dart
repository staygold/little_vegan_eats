// lib/recipes/course_page.dart
import 'dart:async';
import 'dart:ui'; // FontVariation

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../utils/text.dart'; // stripHtml

import 'recipe_detail_screen.dart';
import 'recipe_repository.dart';
import 'recipe_cache.dart';

import '../recipes/allergy_keys.dart';
import 'allergy_engine.dart';

// ✅ External models
import '../meal_plan/core/allergy_profile.dart';

// ✅ reuse shared UI
import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';
import 'widgets/recipe_filters_ui.dart';
import 'widgets/recipe_card.dart';

/// Minimal local unawaited helper
void unawaited(Future<void> f) {}

class _RecipeIndex {
  final int id;
  final String titleLower;

  final String ingredientsText;
  final String ingredientsLower;

  final List<String> courses;
  final List<String> collections;
  final List<String> cuisines;
  final List<String> suitable;
  final List<String> nutrition;

  final List<String> allergyTags;
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
  static TextStyle meta(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
        height: 1.2,
        fontSize: 14,
        fontVariations: const [FontVariation('wght', 600)],
      );
}

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
  // ------------------------
  // Networking (terms)
  // ------------------------
  final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'LittleVeganEatsApp/1.0',
      },
    ),
  );

  // ------------------------
  // UI state
  // ------------------------
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _visible = [];

  // Search
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  Timer? _searchDebounce;

  // Filters (UI-facing)
  // IMPORTANT: We keep course as "All" so the UI never shows "Breakfast" etc.
  RecipeFilterSelection _filters = const RecipeFilterSelection();

  // ✅ Allergies ON by default
  AllergiesSelection _allergies = const AllergiesSelection(
    enabled: true,
    mode: SuitabilityMode.wholeFamily,
    includeSwaps: true,
  );

  // Tag rendering
  final Map<int, ({String? tag, String? swapHint})> _tagById = {};

  // Term maps
  Map<String, String> _courseIdToName = {};
  Map<String, String> _courseSlugToName = {};
  Map<String, String> _collectionIdToName = {};
  Map<String, String> _cuisineIdToName = {};
  Map<String, String> _suitableIdToName = {};
  Map<String, String> _nutritionIdToName = {};
  Map<String, String> _allergenIdToName = {};

  // Options
  List<String> _courseOptionsCached = const ['All'];
  List<String> _collectionOptionsCached = const ['All'];
  List<String> _cuisineOptionsCached = const ['All'];
  List<String> _suitableOptionsCached = const ['All'];
  List<String> _nutritionOptionsCached = const ['All'];

  bool _loadingTerms = false;
  bool _termsLoaded = false;

  bool _indexReady = false;
  final Map<int, _RecipeIndex> _indexById = {};

  // ✅ Course is locked on this page BUT SHOULD NOT SHOW as a filter selection.
  bool _didApplyInitialCourse = false;
  String? _lockedCourseName; // resolved slug → name

  // ------------------------
  // Household
  // ------------------------
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  bool _loadingHousehold = true;
  String? _householdError;

  final List<ProfilePerson> _adults = [];
  final List<ProfilePerson> _children = [];
  List<ProfilePerson> get _allPeople => [..._adults, ..._children];

  // ------------------------
  // Favorites
  // ------------------------
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};
  bool _loadingFavs = true;

  // ------------------------
  // Helpers
  // ------------------------
  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(u.uid);
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  String _titleOf(Map<String, dynamic> r) =>
      (r['title']?['rendered'] as String?)?.trim().isNotEmpty == true
          ? (r['title']['rendered'] as String)
              .replaceAll('&#038;', '&')
              .replaceAll('&amp;', '&')
              .trim()
          : 'Untitled';

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map && recipe['image_url'] is String) {
      final url = recipe['image_url'].toString().trim();
      if (url.isNotEmpty) return url;
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

  bool _isFavorited(int? recipeId) =>
      recipeId != null && _favoriteIds.contains(recipeId);

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
  // Term parsing
  // ------------------------
  List<String> _termsOfField(
    Map<String, dynamic> r,
    String field,
    Map<String, String> idToName,
  ) {
    final v = r[field];
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
    final mapped = raw.map((x) => idToName[x] ?? x).toList();
    return mapped.where((s) => s.trim().isNotEmpty).toSet().toList()..sort();
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

  List<String> _allergyTagsOf(Map<String, dynamic> r) =>
      _termsOfField(r, 'wprm_allergies', _allergenIdToName);

  // ------------------------
  // Lifecycle
  // ------------------------
  @override
  void initState() {
    super.initState();
    _listenToHousehold();
    _init();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _authSub?.cancel();
    _favSub?.cancel();
    _searchDebounce?.cancel();
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
        _items = widget.recipes!;
      } else {
        _items = await RecipeRepository.ensureRecipesLoaded(
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

      // Terms then index
      await _loadTerms();

      if (!mounted) return;
      setState(() => _loading = false);

      _rebuildIndexAndOptions(force: true);
      _applyInitialCourseIfNeeded();
      _recomputeVisible();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ------------------------
  // Favorites wiring
  // ------------------------
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
          _favoriteIds.clear();
          _loadingFavs = false;
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
            _favoriteIds
              ..clear()
              ..addAll(next);
            _loadingFavs = false;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _loadingFavs = false);
        },
      );
    });
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

        void parse(
          List raw,
          List<ProfilePerson> target,
          PersonType type,
          String prefix,
        ) {
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
              allergies: hasAllergies
                  ? (parsed.toSet().toList()..sort())
                  : [],
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

          if (_allergies.mode == SuitabilityMode.singlePerson) {
            final exists = _allPeople.any((p) => p.id == _allergies.personId);
            if (!exists) {
              _allergies = _allergies.copyWith(
                mode: SuitabilityMode.wholeFamily,
                personId: null,
                includeSwaps: false,
              );
            }
          }
        });

        _recomputeVisible();
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

  List<ProfilePerson> _activeProfilesForAllergies() {
    if (!_allergies.enabled) return _allPeople;
    switch (_allergies.mode) {
      case SuitabilityMode.wholeFamily:
        return _allPeople;
      case SuitabilityMode.allChildren:
        return _children;
      case SuitabilityMode.singlePerson:
        return _allPeople.where((x) => x.id == _allergies.personId).toList();
    }
  }

  String _activeAllergiesLabelFor(List<ProfilePerson> people) {
    final set = <String>{};
    for (final p in people) {
      if (p.hasAllergies && p.allergies.isNotEmpty) set.addAll(p.allergies);
    }
    return set.toList().map(_prettyAllergy).join(', ');
  }

  // ------------------------
  // Terms loading
  // ------------------------
  Future<void> _loadTerms() async {
    if (_loadingTerms) return;
    setState(() => _loadingTerms = true);

    try {
      final courseById = <String, String>{};
      final courseBySlug = <String, String>{};
      final colById = <String, String>{};
      final cuisineById = <String, String>{};
      final suitableById = <String, String>{};
      final nutritionById = <String, String>{};
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
            if (bySlug != null && slug.isNotEmpty && name.isNotEmpty) {
              bySlug[slug] = name;
            }
          }
          if (data.length < perPage) break;
          page++;
        }
      }

      await Future.wait([
        loadTax(endpoint: 'wprm_course', byId: courseById, bySlug: courseBySlug),
        loadTax(endpoint: 'wprm_collections', byId: colById),
        loadTax(endpoint: 'wprm_cuisine', byId: cuisineById),
        loadTax(endpoint: 'wprm_suitable_for', byId: suitableById),
        loadTax(endpoint: 'wprm_nutrition_tag', byId: nutritionById),
        loadTax(endpoint: 'wprm_allergies', byId: allergenById),
      ]);

      if (!mounted) return;
      setState(() {
        _courseIdToName = courseById;
        _courseSlugToName = courseBySlug;
        _collectionIdToName = colById;
        _cuisineIdToName = cuisineById;
        _suitableIdToName = suitableById;
        _nutritionIdToName = nutritionById;
        _allergenIdToName = allergenById;
        _termsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _termsLoaded = true);
    } finally {
      if (mounted) setState(() => _loadingTerms = false);
    }
  }

  // ------------------------
  // Index + options
  // ------------------------
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

    _indexById.clear();

    for (final r in _items) {
      final id = r['id'];
      if (id is! int) continue;

      final ix = _RecipeIndex(
        id: id,
        titleLower: _titleOf(r).toLowerCase(),
        ingredientsText: _ingredientsTextOf(r),
        ingredientsLower: _ingredientsTextOf(r).toLowerCase(),
        courses: _coursesOf(r),
        collections: _collectionsOf(r),
        cuisines: _cuisinesOf(r),
        suitable: _suitableForOf(r),
        nutrition: _nutritionTagsOf(r),
        allergyTags: _allergyTagsOf(r),
        swapText: _swapTextOf(r),
      );

      cSet.addAll(ix.courses);
      colSet.addAll(ix.collections);
      cuiSet.addAll(ix.cuisines);
      sSet.addAll(ix.suitable);
      nSet.addAll(ix.nutrition);

      _indexById[id] = ix;
    }

    if (!mounted) return;
    setState(() {
      _courseOptionsCached = ['All', ...(cSet.toList()..sort())];
      _collectionOptionsCached = ['All', ...(colSet.toList()..sort())];
      _cuisineOptionsCached = ['All', ...(cuiSet.toList()..sort())];
      _suitableOptionsCached = ['All', ...(sSet.toList()..sort())];
      _nutritionOptionsCached = ['All', ...(nSet.toList()..sort())];

      _indexReady = true;

      // Clamp any existing selections to available options.
      // BUT: keep course as All on this page so it never shows "Breakfast".
      _filters = _filters.copyWith(
        course: 'All',
        cuisine: _clampToOptions(_filters.cuisine, _cuisineOptionsCached),
        suitableFor: _clampToOptions(_filters.suitableFor, _suitableOptionsCached),
        nutritionTag: _clampToOptions(_filters.nutritionTag, _nutritionOptionsCached),
        collection: _clampToOptions(_filters.collection, _collectionOptionsCached),
      );
    });
  }

  String _clampToOptions(String c, List<String> o) => o.contains(c) ? c : 'All';

  // ✅ Resolve slug → name into _lockedCourseName (does NOT set a UI filter)
  void _applyInitialCourseIfNeeded() {
    if (_didApplyInitialCourse) return;

    final slug = widget.courseSlug.trim();
    final name = _courseSlugToName[slug];

    if (name != null && name.trim().isNotEmpty) {
      _lockedCourseName = name.trim();
    } else {
      _lockedCourseName = null;
    }

    // Keep UI clean.
    _filters = _filters.copyWith(course: 'All');

    _didApplyInitialCourse = true;
  }

  // ------------------------
  // Allergy evaluation
  // ------------------------
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
      if (!p.hasAllergies || p.allergies.isNotEmpty == false) continue;

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
    if (anySwap) return (tag: '⚠️ Swap required', swapHint: null);

    if (_allergies.mode == SuitabilityMode.singlePerson && activeProfiles.isNotEmpty) {
      return (tag: '✅ Safe for ${activeProfiles.first.name}', swapHint: null);
    }
    if (_allergies.mode == SuitabilityMode.allChildren) {
      return (tag: '✅ Safe for all children', swapHint: null);
    }
    return (tag: '✅ Safe for whole family', swapHint: null);
  }

  // ------------------------
  // Visible recompute (course locked but not shown)
  // ------------------------
  void _recomputeVisible() {
    if (!_indexReady) return;

    _applyInitialCourseIfNeeded();
    final q = _query.trim().toLowerCase();
    final locked = _lockedCourseName;

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

      // ✅ Hard lock to course WITHOUT touching UI filters
      if (locked != null && locked.isNotEmpty) {
        if (!ix.courses.contains(locked)) continue;
      } else {
        // fallback: only if slug→name didn't resolve
        final s = widget.courseSlug.toLowerCase();
        final hay = (ix.courses.join(' ') + ' ' + ix.titleLower).toLowerCase();
        if (!hay.contains(s)) continue;
      }

      // Other filters (UI-facing)
      if (_filters.cuisine != 'All' && !ix.cuisines.contains(_filters.cuisine)) continue;
      if (_filters.suitableFor != 'All' && !ix.suitable.contains(_filters.suitableFor)) continue;
      if (_filters.nutritionTag != 'All' && !ix.nutrition.contains(_filters.nutritionTag)) continue;
      if (_filters.collection != 'All' && !ix.collections.contains(_filters.collection)) continue;

      // Search
      if (q.isNotEmpty &&
          !ix.titleLower.contains(q) &&
          !ix.ingredientsLower.contains(q)) continue;

      // Allergies
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
      _tagById
        ..clear()
        ..addAll(nextTags);
    });
  }

  // ------------------------
  // Build
  // ------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

    final activeProfiles =
        _allergies.enabled ? _activeProfilesForAllergies() : _allPeople;
    final hasAnyAllergies =
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          // ✅ App header unchanged
          SubHeaderBar(title: widget.title),

          // ✅ Search unchanged
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchPill(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              hintText: 'Search recipes',
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
          ),

          // ✅ Filtering added (course is locked but NOT shown as active)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: RecipeFilterBar(
              filters: _filters,
              allergies: _allergies,
              courseOptions: _courseOptionsCached,
              cuisineOptions: _cuisineOptionsCached,
              suitableForOptions: _suitableOptionsCached,
              nutritionOptions: _nutritionOptionsCached,
              collectionOptions: _collectionOptionsCached,
              adults: _adults,
              children: _children,
              lockCourse: true, // keep UI layout consistent
              lockCollection: false,
              householdLoading: _loadingHousehold,
              householdError: _householdError,
              onRetryHousehold: _listenToHousehold,
              onFiltersApplied: (next) {
                // ✅ Never allow course to become "Breakfast" in the UI
                setState(() => _filters = next.copyWith(course: 'All'));
                Future.microtask(_recomputeVisible);
              },
              onAllergiesApplied: (next) {
                setState(() => _allergies = next);
                Future.microtask(_recomputeVisible);
              },
            ),
          ),

          if (_allergies.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  hasAnyAllergies
                      ? 'Allergies considered: ${_activeAllergiesLabelFor(activeProfiles)}'
                      : 'No allergies saved.',
                  style: _CStyle.meta(context),
                ),
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

                setState(() => _items = updated);
                _rebuildIndexAndOptions(force: true);
                _applyInitialCourseIfNeeded();
                _recomputeVisible();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  

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

                  if (_visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Center(
                        child: Text(
                          'No recipes found for "${widget.title}" yet.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  ..._visible.map((r) {
                    final id = _toInt(r['id']);
                    final title = _titleOf(r);
                    final thumb = _thumbOf(r);

                    final tagData =
                        (_allergies.enabled && id != null) ? _tagById[id] : null;

                    final subtitleParts = [
                      if (_allergies.enabled && tagData?.tag != null) tagData!.tag!,
                      if (_allergies.enabled && tagData?.swapHint != null)
                        tagData!.swapHint!,
                    ];
                    final subtitle =
                        subtitleParts.where((s) => s.trim().isNotEmpty).join(' • ');

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RecipeCard(
                        title: title,
                        subtitle: subtitle.isEmpty ? null : subtitle,
                        imageUrl: thumb,
                        compact: false,
                        badge: _isFavorited(id) ? _favBadge() : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: id == null
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RecipeDetailScreen(id: id),
                                  ),
                                ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// lib/recipes/course_page.dart
import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'recipe_detail_screen.dart';
import 'recipe_repository.dart';

// ✅ reuse shared UI
import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';

// ✅ reuse filters UI + shared types
import 'widgets/recipe_filters_ui.dart';

// ✅ recipe card
import 'widgets/recipe_card.dart';

// ✅ allergy engine
import 'allergy_engine.dart';
import '../recipes/allergy_keys.dart';

class _CStyle {
  static const bool showSubtitle = false;

  static const EdgeInsets metaPadding = EdgeInsets.fromLTRB(16, 0, 16, 10);
  static const double subtitleGap = 6;
  static const double lineGap = 2;

  static TextStyle subtitle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontVariations: const [FontVariation('wght', 600)],
        height: 1.2,
      );

  static TextStyle meta(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
        height: 1.2,
        fontSize: 14,
        fontVariations: const [FontVariation('wght', 600)],
      );

  static TextStyle loading(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
        height: 1.2,
        fontVariations: const [FontVariation('wght', 500)],
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
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _recipes = const [];

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  // ⭐ Favourites
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};
  bool _loadingFavs = true;

  // ✅ Multi-Select Compatible
  RecipeFilterSelection _filters = const RecipeFilterSelection();
  AllergiesSelection _allergies = const AllergiesSelection(
    enabled: true,
    mode: SuitabilityMode.wholeFamily,
    includeSwaps: true,
  );

  List<Map<String, dynamic>> _visible = const [];
  final Map<int, ({String? tag, String? swapHint})> _tagById = {};

  List<String> _courseOptions = const ['All'];
  List<String> _cuisineOptions = const ['All'];
  List<String> _suitableOptions = const ['All'];
  List<String> _nutritionOptions = const ['All'];
  List<String> _collectionOptions = const ['All'];

  // Household
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  bool _loadingHousehold = true;
  String? _householdError;

  final List<ProfilePerson> _adults = [];
  final List<ProfilePerson> _children = [];

  List<ProfilePerson> get _allPeople => [..._adults, ..._children];

  @override
  void initState() {
    super.initState();
    _listenToHousehold();
    _init();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _favSub?.cancel();
    _userSub?.cancel();
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
      if (widget.recipes != null) {
        _recipes = widget.recipes!;
      } else {
        _recipes = await RecipeRepository.ensureRecipesLoaded(
          backgroundRefresh: true,
          forceRefresh: false,
        );
      }

      if (widget.favoriteIds != null) {
        _favoriteIds..clear()..addAll(widget.favoriteIds!);
        _loadingFavs = false;
      } else {
        _wireFavorites();
      }

      _buildOptionsFromCourseRecipes();
      _filters = _filters.copyWith(course: 'All');
      _recomputeVisible();

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
          _favoriteIds..clear()..addAll(next);
          _loadingFavs = false;
        });
      });
    });
  }

  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(u.uid);
  }

  String? _canonicalAllergyKey(String raw) => AllergyKeys.normalize(raw);
  String _prettyAllergy(String key) => AllergyKeys.label(key);

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

        void parse(List raw, List<ProfilePerson> target, PersonType type,
            String prefix) {
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

          // ✅ FIXED: Correct Multi-Select Logic (specificPeople)
          if (_allergies.mode == SuitabilityMode.specificPeople) {
            final valid = _allergies.personIds
                .where((id) => _allPeople.any((p) => p.id == id))
                .toSet();
            if (valid.isEmpty) {
              _allergies = _allergies.copyWith(
                mode: SuitabilityMode.wholeFamily,
                personIds: {},
                includeSwaps: false,
              );
            } else {
              _allergies = _allergies.copyWith(personIds: valid);
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

  // ✅ FIXED: Correct Multi-Select Logic
  List<ProfilePerson> _activeProfilesForAllergies() {
    if (!_allergies.enabled) return _allPeople;

    switch (_allergies.mode) {
      case SuitabilityMode.wholeFamily:
        return _allPeople;
      case SuitabilityMode.allChildren:
        return _children;
      case SuitabilityMode.specificPeople:
        return _allPeople
            .where((x) => _allergies.personIds.contains(x.id))
            .toList();
    }
  }

  String _activeAllergiesLabelFor(List<ProfilePerson> people) {
    final set = <String>{};
    for (final p in people) {
      if (p.hasAllergies && p.allergies.isNotEmpty) set.addAll(p.allergies);
    }
    final list = set.toList()..sort();
    return list.map(_prettyAllergy).join(', ');
  }

  // ------------------------
  // Recipe helpers
  // ------------------------

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

  String _ingredientsTextOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is! Map) return '';
    final flat = recipe['ingredients_flat'];
    if (flat is! List) return '';
    final buf = StringBuffer();
    for (final row in flat) {
      if (row is! Map) continue;
      final name = (row['name'] ?? '').toString();
      final notes = (row['notes'] ?? '').toString();
      if (name.isNotEmpty) buf.write('$name ');
      if (notes.isNotEmpty) buf.write('$notes ');
    }
    return buf.toString().trim();
  }

  // ✅ Swap Text
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

  List<String> _allergyTagsOf(Map<String, dynamic> r) {
    try {
      if (r['recipe'] is Map && r['recipe']['tags'] is Map) {
        final tags = r['recipe']['tags'] as Map;
        if (tags['allergies'] is List) {
          final list = tags['allergies'] as List;
          return list.map((item) => item['name'].toString()).toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  bool _matchesCourse(Map<String, dynamic> r, String slug) {
    final s = slug.toLowerCase();
    return r.toString().toLowerCase().contains(s);
  }

  List<Map<String, dynamic>> _courseRecipes() =>
      _recipes.where((r) => _matchesCourse(r, widget.courseSlug)).toList();

  List<String> _termsFromField(Map<String, dynamic> r, String field) {
    final v = r[field];
    if (v is List) {
      return v.map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    if (v is int) return [v.toString()];
    return const [];
  }

  List<String> _cuisinesOf(Map<String, dynamic> r) =>
      _termsFromField(r, 'wprm_cuisine');
  List<String> _suitableOf(Map<String, dynamic> r) =>
      _termsFromField(r, 'wprm_suitable_for');
  List<String> _nutritionOf(Map<String, dynamic> r) =>
      _termsFromField(r, 'wprm_nutrition_tag');

  // ✅ FIX: collections should be NAMES, not IDs
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
            if (out.isNotEmpty) return out;
          }
        }
      }
    } catch (_) {}
    return const [];
  }

  List<String> _collectionFallbackFromIds(Map<String, dynamic> r) {
    final v = r['wprm_collections'];
    if (v is List) {
      return v.map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    if (v is int) return [v.toString()];
    return const [];
  }

  List<String> _collectionsOf(Map<String, dynamic> r) {
    final names = _collectionNamesFromRecipeTags(r);
    if (names.isNotEmpty) return names;
    return _collectionFallbackFromIds(r);
  }

  List<String> _mkOptions(Set<String> s) {
    final list = s.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...list];
  }

  void _buildOptionsFromCourseRecipes() {
    final base = _courseRecipes();
    _courseOptions = const ['All'];

    final cuisines = <String>{};
    final suitable = <String>{};
    final nutrition = <String>{};
    final collections = <String>{};

    for (final r in base) {
      cuisines.addAll(_cuisinesOf(r));
      suitable.addAll(_suitableOf(r));
      nutrition.addAll(_nutritionOf(r));
      collections.addAll(_collectionsOf(r)); // ✅ now names
    }

    _cuisineOptions = _mkOptions(cuisines);
    _suitableOptions = _mkOptions(suitable);
    _nutritionOptions = _mkOptions(nutrition);
    _collectionOptions = _mkOptions(collections);

    _filters = _filters.copyWith(
      course: 'All',
      cuisine: _clampToOptions(_filters.cuisine, _cuisineOptions),
      suitableFor: _clampToOptions(_filters.suitableFor, _suitableOptions),
      nutritionTag: _clampToOptions(_filters.nutritionTag, _nutritionOptions),
      collection: _clampToOptions(_filters.collection, _collectionOptions),
    );
  }

  String _clampToOptions(String current, List<String> opts) {
    if (opts.isEmpty) return 'All';
    if (opts.contains(current)) return current;
    return 'All';
  }

  // ------------------------
  // Allergy logic
  // ------------------------

  bool _isAllowedForPerson({
    required ProfilePerson p,
    required List<String> tags,
    required String swapText,
  }) {
    if (!p.hasAllergies || p.allergies.isEmpty) return true;

    final res = AllergyEngine.evaluate(
      recipeAllergyTags: tags,
      swapFieldText: swapText,
      userAllergies: p.allergies,
    );

    if (res.status == AllergyStatus.safe) return true;
    if (_allergies.includeSwaps && res.status == AllergyStatus.swapRequired) {
      return true;
    }
    return false;
  }

  ({String? tag, String? swapHint}) _tagForRecipe({
    required List<String> tags,
    required String swapText,
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
        recipeAllergyTags: tags,
        swapFieldText: swapText,
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
      return (
        tag: activeProfiles.length > 1
            ? '⚠️ Swap required (one or more people)'
            : '⚠️ Swap required',
        swapHint: null,
      );
    }

    if (_allergies.mode == SuitabilityMode.specificPeople &&
        activeProfiles.length == 1) {
      return (tag: '✅ Safe for ${activeProfiles.first.name}', swapHint: null);
    }
    if (_allergies.mode == SuitabilityMode.specificPeople &&
        activeProfiles.length > 1) {
      return (tag: '✅ Safe for selected people', swapHint: null);
    }
    if (_allergies.mode == SuitabilityMode.allChildren) {
      return (tag: '✅ Safe for all children', swapHint: null);
    }
    return (tag: '✅ Safe for whole family', swapHint: null);
  }

  // ------------------------
  // Visibility
  // ------------------------

  void _recomputeVisible() {
    final base = _courseRecipes();
    final q = _searchCtrl.text.trim().toLowerCase();

    final activeProfiles =
        _allergies.enabled ? _activeProfilesForAllergies() : _allPeople;
    final hasAnyAllergies = _allergies.enabled &&
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

    final next = <Map<String, dynamic>>[];
    final nextTags = <int, ({String? tag, String? swapHint})>{};

    for (final r in base) {
      final id = _toInt(r['id']);
      final titleLower = _titleOf(r).toLowerCase();

      if (_filters.cuisine != 'All' && !_cuisinesOf(r).contains(_filters.cuisine)) continue;
      if (_filters.suitableFor != 'All' && !_suitableOf(r).contains(_filters.suitableFor)) continue;
      if (_filters.nutritionTag != 'All' && !_nutritionOf(r).contains(_filters.nutritionTag)) continue;
      if (_filters.collection != 'All' && !_collectionsOf(r).contains(_filters.collection)) continue;

      if (q.isNotEmpty && !titleLower.contains(q)) continue;

      final tags = _allergyTagsOf(r);
      final swapText = _swapTextOf(r);

      if (hasAnyAllergies) {
        bool allowed = true;
        for (final p in activeProfiles) {
          if (!_isAllowedForPerson(p: p, tags: tags, swapText: swapText)) {
            allowed = false;
            break;
          }
        }
        if (!allowed) continue;

        if (id != null) {
          nextTags[id] = _tagForRecipe(
            tags: tags,
            swapText: swapText,
            activeProfiles: activeProfiles,
          );
        }
      }

      next.add(r);
    }

    if (!mounted) return;
    setState(() {
      _visible = next;
      _tagById..clear()..addAll(nextTags);
    });
  }

  @override
  Widget build(BuildContext context) {
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

    final activeProfiles =
        _allergies.enabled ? _activeProfilesForAllergies() : _allPeople;
    final hasAnyAllergies =
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          SubHeaderBar(title: widget.title),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchPill(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              hintText: 'Search recipes',
              onChanged: (_) => _recomputeVisible(),
              onSubmitted: (_) => _recomputeVisible(),
              onClear: () {
                _searchCtrl.clear();
                _recomputeVisible();
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: RecipeFilterBar(
              filters: _filters,
              allergies: _allergies,
              courseOptions: _courseOptions,
              lockCourse: true,
              cuisineOptions: _cuisineOptions,
              suitableForOptions: _suitableOptions,
              nutritionOptions: _nutritionOptions,
              collectionOptions: _collectionOptions,
              adults: _adults,
              children: _children,
              householdLoading: _loadingHousehold,
              householdError: _householdError,
              onRetryHousehold: _listenToHousehold,
              onFiltersApplied: (next) {
                final corrected = next.copyWith(course: 'All');
                setState(() => _filters = corrected);
                Future.microtask(_recomputeVisible);
              },
              onAllergiesApplied: (next) {
                setState(() => _allergies = next);
                Future.microtask(_recomputeVisible);
              },
            ),
          ),

          Padding(
            padding: _CStyle.metaPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_CStyle.showSubtitle) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(widget.subtitle, style: _CStyle.subtitle(context)),
                  ),
                  const SizedBox(height: _CStyle.subtitleGap),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Showing ${_visible.length} recipes',
                    style: _CStyle.meta(context),
                  ),
                ),
                if (_allergies.enabled) ...[
                  SizedBox(height: _CStyle.lineGap),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      hasAnyAllergies
                          ? 'Allergies considered: ${_activeAllergiesLabelFor(_activeProfilesForAllergies())}'
                          : 'No allergies saved.',
                      style: _CStyle.meta(context),
                    ),
                  ),
                ],
                if (_loadingFavs) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text('Loading favourites…', style: _CStyle.loading(context)),
                    ],
                  ),
                ],
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (_visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: Center(
                      child: Text(
                        'No suitable recipes found.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ..._visible.map((r) {
                  final id = _toInt(r['id']);
                  final title = _titleOf(r);
                  final thumb = _thumbOf(r);
                  final isFav = id != null && _favoriteIds.contains(id);

                  final tagData =
                      (_allergies.enabled && id != null) ? _tagById[id] : null;

                  final tagParts = <String>[
                    if (_allergies.enabled && tagData?.tag != null) tagData!.tag!,
                    if (_allergies.enabled && tagData?.swapHint != null)
                      tagData!.swapHint!,
                  ];
                  final tagLine =
                      tagParts.where((s) => s.trim().isNotEmpty).join(' • ');

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RecipeCard(
                      title: title,
                      subtitle: tagLine.isNotEmpty ? tagLine : null,
                      imageUrl: thumb,
                      compact: false,
                      onTap: id == null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RecipeDetailScreen(id: id),
                                ),
                              ),
                      trailing: isFav
                          ? const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.star_rounded,
                                size: 20,
                                color: Colors.amber,
                              ),
                            )
                          : const Icon(Icons.chevron_right_rounded),
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

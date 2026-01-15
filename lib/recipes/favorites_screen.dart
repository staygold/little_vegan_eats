// lib/recipes/favorites_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_repository.dart';
import 'recipe_detail_screen.dart';
import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';
import 'widgets/smart_recipe_card.dart';

import 'family_profile_repository.dart';
import 'family_profile.dart';
import 'household_food_policy.dart';
import 'food_policy_core.dart';
import 'recipe_index.dart';
import 'recipe_index_builder.dart';
import 'allergy_engine.dart';
import '../utils/text.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _allRecipes = const [];
  bool _loadingRecipes = true;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  final FamilyProfileRepository _familyRepo = FamilyProfileRepository();
  late final HouseholdFoodPolicy _policy = HouseholdFoodPolicy(familyRepo: _familyRepo);
  StreamSubscription<FamilyProfile>? _familySub;
  FamilyProfile _family = const FamilyProfile(adults: [], children: []);

  final Map<int, RecipeIndex> _indexById = {};

  @override
  void initState() {
    super.initState();
    _warmRecipeCache();
    _listenToHousehold();
  }

  @override
  void dispose() {
    _familySub?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _listenToHousehold() {
    _familySub = _familyRepo.watchFamilyProfile().listen((fam) {
      if (!mounted) return;
      setState(() => _family = fam);
    });
  }

  Future<void> _warmRecipeCache() async {
    setState(() => _loadingRecipes = true);
    try {
      final list = await RecipeRepository.ensureRecipesLoaded(
        backgroundRefresh: true,
        forceRefresh: false,
      );

      _buildIndex(list);

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

  void _buildIndex(List<Map<String, dynamic>> list) {
    _indexById.clear();
    final normalised = <Map<String, dynamic>>[];
    for (final r in list) {
      final m = _normaliseForIndex(r);
      if (m.isNotEmpty) normalised.add(m);
    }
    _indexById.addAll(RecipeIndexBuilder.buildById(normalised));
  }

  List<String> _householdNames() {
    return _family.allPeople
        .map((p) => (p.name ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  // ----------------------------------------------------------------------
  // ALLERGY STATUS LABEL (matches your “Safe for [Name]” requirement)
  // ----------------------------------------------------------------------
  String? _calculateAllergyStatus(Map<String, dynamic> recipe, List<String> recipeTags, String swapText) {
    final blockedNames = <String>[];
    final swapNames = <String>[];

    // how many people actually have allergies configured?
    final allergyPeople = _family.allPeople.where((p) => p.allergies.isNotEmpty).toList();

    for (final person in allergyPeople) {
      final result = AllergyEngine.evaluate(
        recipeAllergyTags: recipeTags,
        swapFieldText: swapText,
        userAllergies: person.allergies,
      );

      if (result.status == AllergyStatus.notSuitable) {
        blockedNames.add(person.name);
      } else if (result.status == AllergyStatus.swapRequired) {
        swapNames.add(person.name);
      }
    }

    // 1) Hard stop first
    if (blockedNames.isNotEmpty) {
      final unique = blockedNames.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      if (unique.length == 1) return "Not suitable for ${unique.first}";
      return "Not suitable for ${unique.length} people";
    }

    // 2) Swap second
    if (swapNames.isNotEmpty) {
      final unique = swapNames.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      if (unique.length == 1) return "Needs swap for ${unique.first}";
      return "Needs swap for ${unique.length} people";
    }

    // 3) Safe (only show if allergies exist)
    if (allergyPeople.isNotEmpty) {
      if (allergyPeople.length == 1) {
        final n = (allergyPeople.first.name ?? '').trim();
        if (n.isNotEmpty) return "Safe for $n";
        return "Safe"; // fallback; your display layer can upgrade if it has householdNames
      }
      return "Safe for whole family";
    }

    return null;
  }

  // ----------------------------------------------------------------------
  // INDEX NORMALISATION + SWAP TEXT (for AllergyEngine)
  // ----------------------------------------------------------------------
  Map<String, dynamic> _normaliseForIndex(Map<String, dynamic> r) {
    final id = _toInt(r['id']);
    if (id == null) return const {};
    return <String, dynamic>{
      'id': id,
      'title': _titleOfCached(r),
      'ingredients': '',
      'wprm_course': _termsFromField(r, 'wprm_course'),
      'wprm_collections': _termsFromField(r, 'wprm_collections'),
      'wprm_cuisine': _termsFromField(r, 'wprm_cuisine'),
      'wprm_suitable_for': _termsFromField(r, 'wprm_suitable_for'),
      'wprm_nutrition_tag': _termsFromField(r, 'wprm_nutrition_tag'),
      'recipe': r['recipe'],
      'meta': r['meta'],
      'ingredient_swaps': _swapTextOf(r),
      'wprm_allergies': _allergyTagsOf(r),
    };
  }

  String _swapTextOf(Map<String, dynamic> r) {
    String? tryGet(dynamic val) {
      if (val != null && val.toString().trim().isNotEmpty) return val.toString();
      return null;
    }

    var found = tryGet(r['ingredient_swaps']) ?? tryGet(r['swap_text']);
    if (found != null) return stripHtml(found).trim();

    if (r['meta'] is Map) {
      final m = r['meta'];
      found = tryGet(m['ingredient_swaps']) ?? tryGet(m['wprm_ingredient_swaps']);
      if (found != null) return stripHtml(found).trim();
    }

    final recipe = r['recipe'];
    if (recipe is Map) {
      found = tryGet(recipe['ingredient_swaps']) ?? tryGet(recipe['swap_text']);
      if (found != null) return stripHtml(found).trim();

      if (recipe['custom_fields'] is Map) {
        final cf = recipe['custom_fields'];
        found = tryGet(cf['ingredient_swaps']);
        if (found != null) return stripHtml(found).trim();
      }
    }

    return '';
  }

  List<String> _allergyTagsOf(Map<String, dynamic> r) {
    try {
      final recipe = r['recipe'];
      if (recipe is Map && recipe['tags'] is Map) {
        final tags = recipe['tags'] as Map;
        final a = tags['allergies'];
        if (a is List) {
          return a.map((e) => (e is Map ? e['name'] : e).toString()).toList();
        }
      }
    } catch (_) {}
    return _termsFromField(r, 'wprm_allergies');
  }

  List<String> _termsFromField(Map<String, dynamic> r, String field) {
    final v = r[field];
    if (v is List) return v.map((e) => e.toString().trim()).toList();
    if (v is String && v.isNotEmpty) return [v];
    return const [];
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return int.tryParse(v.toString().trim());
  }

  Map<String, dynamic>? _findRecipeById(int id) {
    for (final r in _allRecipes) {
      final rid = r['id'];
      if (rid is int && rid == id) return r;
      if (rid is String && int.tryParse(rid) == id) return r;
    }
    return null;
  }

  String _titleOfCached(Map<String, dynamic>? cached) {
    if (cached == null) return 'Recipe';
    final t = cached['title'];
    if (t is Map && t['rendered'] is String) {
      final s = (t['rendered'] as String)
          .replaceAll('&#038;', '&')
          .replaceAll('&amp;', '&')
          .trim();
      if (s.isNotEmpty) return s;
    }
    final name = cached['recipe']?['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return 'Recipe';
  }

  int _favRecipeIdFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final fromId = int.tryParse(doc.id);
    if (fromId != null && fromId > 0) return fromId;

    final data = doc.data();
    final raw = data['recipeId'];
    final fromField = (raw is int) ? raw : int.tryParse('$raw');
    if (fromField != null && fromField > 0) return fromField;

    return -1;
  }

  bool _matchesSearch(String title) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please sign in')));
    }

    final favQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .orderBy('updatedAt', descending: true);

    final youngestChild = _policy.youngestChild(_family);
    final youngestMonths = _policy.youngestChildAgeMonths(_family);
    final childNames = _family.children.map((c) => c.name).toList();
    final householdNames = _householdNames();

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          const SubHeaderBar(title: 'Favourites'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchPill(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              hintText: 'Search favourites',
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {},
              onClear: () => setState(() {}),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: favQuery.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) return const Center(child: Text('No favourites yet'));
                if (_loadingRecipes) return const Center(child: CircularProgressIndicator());

                final items = <_FavItem>[];
                for (final doc in docs) {
                  final d = doc.data();
                  final id = _favRecipeIdFromDoc(doc);
                  if (id <= 0) continue;

                  final cached = _findRecipeById(id);

                  final title = _titleOfCached(cached).isNotEmpty
                      ? _titleOfCached(cached)
                      : (d['title']?.toString() ?? 'Recipe');

                  if (!_matchesSearch(title)) continue;

                  final imageUrl =
                      (cached?['recipe']?['image_url_full'] as String?) ??
                      (cached?['recipe']?['image_url'] as String?) ??
                      (d['imageUrl']?.toString());

                  items.add(_FavItem(id: id, title: title, imageUrl: imageUrl, cachedData: cached));
                }

                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No favourites match "${_searchCtrl.text.trim()}".',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final ix = (item.cachedData != null) ? _indexById[item.id] : null;

                    final babyTag = (ix != null)
                        ? FoodPolicyCore.babySuitabilityLabel(
                            ix: ix,
                            youngestChild: youngestChild,
                            youngestMonths: youngestMonths,
                          )
                        : null;

                    String? allergyStatus;
                    if (ix != null && item.cachedData != null) {
                      allergyStatus = _calculateAllergyStatus(
                        item.cachedData!,
                        ix.allergies,
                        _swapTextOf(item.cachedData!),
                      );
                    }

                    return SmartRecipeCard(
                      title: item.title,
                      imageUrl: item.imageUrl,
                      isFavorite: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: item.id)),
                      ),
                      tags: ix?.suitable ?? [],
                      ageWarning: babyTag,
                      childNames: childNames,
                      householdNames: householdNames,
                      allergyStatus: allergyStatus,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FavItem {
  const _FavItem({
    required this.id,
    required this.title,
    this.imageUrl,
    this.cachedData,
  });

  final int id;
  final String title;
  final String? imageUrl;
  final Map<String, dynamic>? cachedData;
}

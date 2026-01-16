// lib/meal_plan/choose_recipe_page.dart
//
// ✅ Uses unified SmartRecipeCard inputs (ageWarning, childNames, householdNames, allergyStatus)
// ✅ Keeps "Snack" vs "Snacks" canonicalization so filtering never goes empty
// ✅ Keeps existing UX: recommended section + shuffle + Select overlay button
//
// Notes:
// - We compute ageWarning via FoodPolicyCore.babySuitabilityLabel (same as CollectionPage/RecipeListScreen)
// - We compute allergyStatus with dynamic labels (same logic style as CollectionPage)
// - We feed householdNames + childNames so the card renders consistently

import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';
import '../theme/app_theme.dart';

import '../recipes/household_food_policy.dart';
import '../recipes/food_policy_core.dart';
import '../recipes/recipe_index.dart';
import '../recipes/family_profile.dart';
import '../recipes/family_profile_repository.dart';
import '../recipes/allergy_engine.dart';
import '../recipes/widgets/recipe_filters_ui.dart';
import '../recipes/widgets/smart_recipe_card.dart';
import '../utils/text.dart';

class _MPChooseStyle {
  static const Color bg = Color(0xFFECF3F4);
  static const Color brandDark = AppColors.brandDark;

  static const EdgeInsets sectionPad = EdgeInsets.fromLTRB(16, 0, 16, 16);
  static const EdgeInsets metaPad = EdgeInsets.fromLTRB(16, 0, 16, 10);

  static TextStyle meta(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
            height: 1.2,
            fontSize: 14,
            fontVariations: const [FontVariation('wght', 600)],
          );

  static TextStyle recTitle(BuildContext context) =>
      (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
            color: Colors.white,
            fontVariations: const [FontVariation('wght', 800)],
          );
}

class ChooseRecipePage extends StatefulWidget {
  final List<Map<String, dynamic>> recipes;
  final Map<int, RecipeIndex> indexById;
  final FamilyProfile familyProfile;

  final String? headerLabel;
  final int? currentId;
  final String initialCourse;

  const ChooseRecipePage({
    super.key,
    required this.recipes,
    required this.indexById,
    required this.familyProfile,
    this.headerLabel,
    this.currentId,
    this.initialCourse = 'All',
  });

  @override
  State<ChooseRecipePage> createState() => _ChooseRecipePageState();
}

class _ChooseRecipePageState extends State<ChooseRecipePage> {
  late final HouseholdFoodPolicy _policy;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  late RecipeFilterSelection _filters;
  late AllergiesSelection _allergies;

  List<Map<String, dynamic>> _visible = [];
  int? _recommendedId;
  final Random _rng = Random();

  // ----------------------------------------------------------------
  // NORMALISATION (Snack vs Snacks)
  // ----------------------------------------------------------------
  String _canonCourse(String input) {
    final s = input.trim();
    if (s.isEmpty) return s;
    final lower = s.toLowerCase();
    if (lower == 'snack' || lower == 'snacks') return 'Snacks';
    if (lower == 'all') return 'All';
    if (lower == 'breakfast') return 'Breakfast';
    if (lower == 'lunch') return 'Lunch';
    if (lower == 'dinner') return 'Dinner';
    if (lower == 'main course' || lower == 'main courses') return 'Main Course';
    return s;
  }

  RecipeFilterSelection _normaliseFilters(RecipeFilterSelection f) {
    return f.copyWith(course: _canonCourse(f.course));
  }

  List<String> _buildCourseOptions() {
    final raw = <String>{};
    for (final ix in widget.indexById.values) {
      for (final c in ix.courses) {
        final t = c.trim();
        if (t.isNotEmpty) raw.add(t);
      }
    }

    final canon = <String>{};
    for (final c in raw) {
      canon.add(_canonCourse(c));
    }

    final list = canon.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    list.removeWhere((x) => x.toLowerCase() == 'all');
    return ['All', ...list];
  }

  // ----------------------------------------------------------------
  // Helpers (match other screens)
  // ----------------------------------------------------------------
  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      final s = (t['rendered'] as String)
          .replaceAll('&#038;', '&')
          .replaceAll('&amp;', '&')
          .trim();
      if (s.isNotEmpty) return s;
    }
    final plain = r['title'];
    if (plain is String && plain.trim().isNotEmpty) return plain.trim();
    return 'Untitled';
  }

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map) {
      final url = (recipe['image_url'] ?? recipe['image'])?.toString();
      if (url != null && url.trim().isNotEmpty) return url.trim();
    }
    return null;
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return int.tryParse(v.toString().trim());
  }

  String _swapTextOf(Map<String, dynamic> r) {
    String? tryGet(dynamic val) {
      if (val != null && val.toString().trim().isNotEmpty) return val.toString();
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

  List<String> _householdNames(FamilyProfile fam) {
    return fam.allPeople
        .map((p) => (p.name ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  List<String> _childNames(FamilyProfile fam) {
    return fam.children
        .map((c) => (c.name ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  // ----------------------------------------------------------------
  // ALLERGY STATUS LABEL (match CollectionPage style)
  // ----------------------------------------------------------------
  String? _calculateAllergyStatus(RecipeIndex ix, Map<String, dynamic> recipe) {
    final blockedNames = <String>[];
    final swapNames = <String>[];

    // Use HouseholdFoodPolicy active profiles (same “who is selected” logic used elsewhere)
    final activePeople = _policy.activeProfiles(
      family: widget.familyProfile,
      selection: _allergies,
    );

    final allergyPeople = activePeople.where((p) => p.allergies.isNotEmpty).toList();
    if (allergyPeople.isEmpty) return null;

    final swapText = _swapTextOf(recipe);

    for (final person in allergyPeople) {
      final result = AllergyEngine.evaluate(
        recipeAllergyTags: ix.allergies,
        swapFieldText: swapText,
        userAllergies: person.allergies,
      );

      if (result.status == AllergyStatus.notSuitable) {
        blockedNames.add(person.name);
      } else if (result.status == AllergyStatus.swapRequired) {
        swapNames.add(person.name);
      }
    }

    if (blockedNames.isNotEmpty) {
      final unique = blockedNames.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      if (unique.length == 1) return "Not suitable for ${unique.first}";
      return "Not suitable for ${unique.length} people";
    }

    if (swapNames.isNotEmpty) {
      final unique = swapNames.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      if (unique.length == 1) return "Needs swap for ${unique.first}";
      return "Needs swap for ${unique.length} people";
    }

    // Safe label if allergies exist in selected group
    if (allergyPeople.length == 1) {
      final n = (allergyPeople.first.name ?? '').trim();
      if (n.isNotEmpty) return "Safe for $n";
      return "Safe";
    }

    // Match RecipeListScreen style (“Safe for …”) but keep it simple:
    if (_allergies.mode == SuitabilityMode.allChildren) return "Safe for all children";
    if (_allergies.mode == SuitabilityMode.specificPeople) return "Safe for selected people";
    return "Safe for whole family";
  }

  // ----------------------------------------------------------------
  // Lifecycle
  // ----------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _policy = HouseholdFoodPolicy(familyRepo: FamilyProfileRepository());

    _filters = _normaliseFilters(
      RecipeFilterSelection(course: _canonCourse(widget.initialCourse)),
    );

    _allergies = const AllergiesSelection(
      enabled: true,
      mode: SuitabilityMode.wholeFamily,
      includeSwaps: true,
      hideUnsafe: true,
    );

    _runFilter();
    _pickRecommendation();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _runFilter() {
    final normalised = _normaliseFilters(_filters);

    final res = _policy.filterRecipes(
      items: widget.recipes,
      indexById: widget.indexById,
      filters: normalised,
      query: _query,
      family: widget.familyProfile,
      selection: _allergies,
    );

    setState(() {
      _filters = normalised;
      _visible = res.visible;
    });

    if (_recommendedId != null) {
      final stillVisible = _visible.any((r) => _toInt(r['id']) == _recommendedId);
      if (!stillVisible) _pickRecommendation();
    } else {
      _pickRecommendation();
    }
  }

  void _pickRecommendation() {
    if (_visible.isEmpty) {
      setState(() => _recommendedId = null);
      return;
    }

    final pool = _visible.where((r) => _toInt(r['id']) != widget.currentId).toList();
    if (pool.isEmpty) {
      setState(() => _recommendedId = null);
      return;
    }

    final randomItem = pool[_rng.nextInt(pool.length)];
    setState(() => _recommendedId = _toInt(randomItem['id']));
  }

  void _onSelect(int id) {
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final recRecipe = (_recommendedId != null)
        ? widget.recipes.firstWhere(
            (r) => _toInt(r['id']) == _recommendedId,
            orElse: () => const <String, dynamic>{},
          )
        : null;

    final validRec = (recRecipe != null && recRecipe.isNotEmpty) ? recRecipe : null;

    final allIndexes = widget.indexById.values;

    final courseOpts = _buildCourseOptions();

    List<String> _optsFrom(Iterable<String> raw) {
      final s = raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      s.removeWhere((x) => x.toLowerCase() == 'all');
      return ['All', ...s];
    }

    final cuisineOpts = _optsFrom(allIndexes.expand((i) => i.cuisines));
    final suitableOpts = _optsFrom(allIndexes.expand((i) => i.suitable));
    final nutritionOpts = _optsFrom(allIndexes.expand((i) => i.nutrition));
    final colOpts = _optsFrom(allIndexes.expand((i) => i.collections));

    return Scaffold(
      backgroundColor: _MPChooseStyle.bg,
      body: Column(
        children: [
          const SubHeaderBar(title: 'Choose recipe'),

          if (widget.headerLabel != null)
            Padding(
              padding: _MPChooseStyle.metaPad,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.headerLabel!, style: _MPChooseStyle.meta(context)),
              ),
            ),

          Container(
            color: _MPChooseStyle.bg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                SearchPill(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  hintText: 'Search recipes',
                  onChanged: (v) {
                    _query = v;
                    _runFilter();
                  },
                  onSubmitted: (v) {
                    _query = v;
                    _runFilter();
                  },
                  onClear: () {
                    _searchCtrl.clear();
                    _query = '';
                    _runFilter();
                  },
                ),
                const SizedBox(height: 10),
                RecipeFilterBar(
                  filters: _filters,
                  allergies: _allergies,
                  courseOptions: courseOpts,
                  cuisineOptions: cuisineOpts,
                  suitableForOptions: suitableOpts,
                  nutritionOptions: nutritionOpts,
                  collectionOptions: colOpts,
                  adults: widget.familyProfile.adults,
                  children: widget.familyProfile.children,
                  onFiltersApplied: (f) {
                    setState(() => _filters = _normaliseFilters(f));
                    _runFilter();
                  },
                  onAllergiesApplied: (a) {
                    setState(() => _allergies = a);
                    _runFilter();
                  },
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (validRec != null)
                  Container(
                    color: _MPChooseStyle.brandDark,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Recommended for you', style: _MPChooseStyle.recTitle(context)),
                            ),
                            TextButton.icon(
                              onPressed: _pickRecommendation,
                              icon: const Icon(Icons.shuffle_rounded, size: 18, color: Colors.white),
                              label: const Text('Shuffle'),
                              style: TextButton.styleFrom(foregroundColor: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildCard(validRec, isDark: true),
                      ],
                    ),
                  ),

                if (_visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No recipes found matching your filters.')),
                  )
                else
                  Padding(
                    padding: _MPChooseStyle.sectionPad,
                    child: Column(
                      children: _visible
                          .map((r) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _buildCard(r, isDark: false),
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r, {required bool isDark}) {
    final id = _toInt(r['id']);
    if (id == null) return const SizedBox.shrink();

    final ix = widget.indexById[id];

    final fam = widget.familyProfile;
    final youngestChild = _policy.youngestChild(fam);
    final youngestMonths = _policy.youngestChildAgeMonths(fam);

    final childNames = _childNames(fam);
    final householdNames = _householdNames(fam);

    final ageWarning = (ix != null)
        ? FoodPolicyCore.babySuitabilityLabel(
            ix: ix,
            youngestChild: youngestChild,
            youngestMonths: youngestMonths,
          )
        : null;

    final allergyStatus = (ix != null) ? _calculateAllergyStatus(ix, r) : null;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        SmartRecipeCard(
          title: _titleOf(r),
          imageUrl: _thumbOf(r),
          isFavorite: false,
          onTap: () => _onSelect(id),
          tags: ix?.suitable ?? const [],
          allergyStatus: allergyStatus,
          ageWarning: ageWarning,
          childNames: childNames,
          householdNames: householdNames,
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 32,
            child: FilledButton(
              onPressed: () => _onSelect(id),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? Colors.white : AppColors.brandDark,
                foregroundColor: isDark ? AppColors.brandDark : Colors.white,
                elevation: 2,
              ),
              child: const Text('Select', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }
}

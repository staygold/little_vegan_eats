// lib/meal_plan/choose_recipe_page.dart

import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';
import '../theme/app_theme.dart';

import '../recipes/household_food_policy.dart';
import '../recipes/recipe_index.dart';
import '../recipes/family_profile.dart';
import '../recipes/family_profile_repository.dart';
import '../recipes/allergy_engine.dart'; 
import '../recipes/widgets/recipe_filters_ui.dart';
import '../recipes/widgets/smart_recipe_card.dart';

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
  // ✅ Renamed back to 'recipes' to match your caller
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

  @override
  void initState() {
    super.initState();
    _policy = HouseholdFoodPolicy(familyRepo: FamilyProfileRepository());
    
    _filters = RecipeFilterSelection(course: widget.initialCourse);
    
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
    final res = _policy.filterRecipes(
      items: widget.recipes,
      indexById: widget.indexById,
      filters: _filters,
      query: _query,
      family: widget.familyProfile,
      selection: _allergies,
    );

    setState(() {
      _visible = res.visible;
    });

    if (_recommendedId != null) {
      final stillVisible = _visible.any((r) => r['id'] == _recommendedId);
      if (!stillVisible) {
        _pickRecommendation();
      }
    } else {
      _pickRecommendation();
    }
  }

  void _pickRecommendation() {
    if (_visible.isEmpty) {
      setState(() => _recommendedId = null);
      return;
    }

    final pool = _visible.where((r) => r['id'] != widget.currentId).toList();
    
    if (pool.isEmpty) {
      setState(() => _recommendedId = null);
      return;
    }

    final randomItem = pool[_rng.nextInt(pool.length)];
    setState(() => _recommendedId = randomItem['id']);
  }

  void _onSelect(int id) {
    Navigator.of(context).pop(id);
  }

  String _titleOf(Map<String, dynamic> r) =>
      (r['title']?['rendered'] as String?) ?? 'Untitled';

  String? _thumbOf(Map<String, dynamic> r) =>
      r['recipe']?['image_url'] as String?;

  String? _calculateAllergyStatus(RecipeIndex ix, Map<String, dynamic> r) {
    final activePeople = _policy.activeProfiles(
      family: widget.familyProfile, 
      selection: _allergies
    );
    
    final blockedNames = <String>[];
    final swapNames = <String>[];

    for (final person in activePeople) {
      if (person.allergies.isEmpty) continue;

      final result = AllergyEngine.evaluate(
        recipeAllergyTags: ix.allergies,
        swapFieldText: ix.ingredientSwaps ?? '',
        userAllergies: person.allergies,
      );

      if (result.status == AllergyStatus.notSuitable) {
        blockedNames.add(person.name);
      } else if (result.status == AllergyStatus.swapRequired) {
        swapNames.add(person.name);
      }
    }

    if (blockedNames.isNotEmpty) return "Not suitable"; 
    if (swapNames.isNotEmpty) return "Needs swap";

    if (activePeople.any((p) => p.allergies.isNotEmpty)) {
      if (_allergies.mode == SuitabilityMode.allChildren) return "Safe for kids";
      if (_allergies.mode == SuitabilityMode.specificPeople) return "Safe for selected";
      return "Safe for family";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final recRecipe = (_recommendedId != null) 
        ? widget.recipes.firstWhere((r) => r['id'] == _recommendedId, orElse: () => {})
        : null;
    
    final validRec = (recRecipe != null && recRecipe.isNotEmpty) ? recRecipe : null;

    final allIndexes = widget.indexById.values;
    final courseOpts = ['All', ...allIndexes.expand((i) => i.courses).toSet().toList()..sort()];
    final cuisineOpts = ['All', ...allIndexes.expand((i) => i.cuisines).toSet().toList()..sort()];
    final suitableOpts = ['All', ...allIndexes.expand((i) => i.suitable).toSet().toList()..sort()];
    final nutritionOpts = ['All', ...allIndexes.expand((i) => i.nutrition).toSet().toList()..sort()];
    final colOpts = ['All', ...allIndexes.expand((i) => i.collections).toSet().toList()..sort()];

    return Scaffold(
      backgroundColor: _MPChooseStyle.bg,
      body: Column(
        children: [
          SubHeaderBar(title: 'Choose recipe'),

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
                  // ✅ FIXED: Added missing parameter
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
                    setState(() => _filters = f);
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
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
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
                    child: Center(child: Text("No recipes found matching your filters.")),
                  )
                else
                  Padding(
                    padding: _MPChooseStyle.sectionPad,
                    child: Column(
                      children: _visible.map((r) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildCard(r, isDark: false),
                        );
                      }).toList(),
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
    final id = r['id'] as int;
    final ix = widget.indexById[id];
    final allergyStatus = (ix != null) ? _calculateAllergyStatus(ix, r) : null;
    
    // ✅ FIXED: Removed trailing, using Stack for Select Button
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        SmartRecipeCard(
          title: _titleOf(r),
          imageUrl: _thumbOf(r),
          isFavorite: false, 
          // Tapping the card selects it
          onTap: () => _onSelect(id),
          tags: ix?.suitable ?? [],
          allergyStatus: allergyStatus,
        ),
        
        // Explicit Select Button overlay
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
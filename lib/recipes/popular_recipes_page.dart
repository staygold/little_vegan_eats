import 'dart:async';
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';
import 'recipe_detail_screen.dart';
import 'widgets/smart_recipe_card.dart';

import 'family_profile_repository.dart';
import 'family_profile.dart';
import 'household_food_policy.dart';
import 'food_policy_core.dart';
import 'recipe_index.dart';
import 'recipe_index_builder.dart';
import 'allergy_engine.dart';
import '../utils/text.dart'; 

class PopularRecipesPage extends StatefulWidget {
  const PopularRecipesPage({
    super.key,
    required this.title,
    required this.recipes,
    required this.favoriteIds,
    this.limit = 50,
  });

  final String title;
  final List<Map<String, dynamic>> recipes;
  final Set<int> favoriteIds;
  final int limit;

  @override
  State<PopularRecipesPage> createState() => _PopularRecipesPageState();
}

class _PopularRecipesPageState extends State<PopularRecipesPage> {
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
    _buildIndex();
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

  void _buildIndex() {
    final normalised = <Map<String, dynamic>>[];
    for (final r in widget.recipes) {
      final m = _normaliseForIndex(r);
      if (m.isNotEmpty) normalised.add(m);
    }
    _indexById.addAll(RecipeIndexBuilder.buildById(normalised));
  }

  // ✅ ALLERGY STATUS (Clean Text)
  String? _calculateAllergyStatus(Map<String, dynamic> recipe, List<String> recipeTags, String swapText) {
    final blockedNames = <String>[];
    final swapNames = <String>[];

    for (final person in _family.allPeople) {
      if (person.allergies.isEmpty) continue;

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

    if (blockedNames.isNotEmpty) {
      final unique = blockedNames.toSet().toList();
      if (unique.length == 1) return "Not suitable for ${unique.first}";
      return "Not suitable for ${unique.length} people";
    }

    if (swapNames.isNotEmpty) {
      final unique = swapNames.toSet().toList();
      if (unique.length == 1) return "Needs swap for ${unique.first}";
      return "Needs swap for ${unique.length} people";
    }
    
    final hasAnyAllergies = _family.allPeople.any((p) => p.allergies.isNotEmpty);
    if (hasAnyAllergies) return "Safe for whole family";

    return null;
  }

  Map<String, dynamic> _normaliseForIndex(Map<String, dynamic> r) {
    final id = _toInt(r['id']);
    if (id == null) return const {};

    return <String, dynamic>{
      'id': id,
      'title': _titleOf(r),
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

  // ✅ IMPROVED SWAP FINDER
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

      // 4. Custom Fields
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

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      final s = (t['rendered'] as String).trim();
      if (s.isNotEmpty) {
        return s.replaceAll('&#038;', '&').replaceAll('&amp;', '&');
      }
    }
    final plain = r['title'];
    if (plain is String && plain.trim().isNotEmpty) return plain.trim();
    return 'Untitled';
  }

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map) {
      final url = (recipe['thumbnail_url'] ??
              recipe['image_url'] ??
              recipe['image_url_full'] ??
              recipe['image'])?.toString();
      if (url != null && url.trim().isNotEmpty) return url.trim();
    }
    return null;
  }

  bool _isPopular(Map<String, dynamic> r) {
    const slug = 'popular';
    bool hasSlugInList(dynamic list) {
      if (list is! List) return false;
      for (final item in list) {
        if (item is Map) {
          final s = (item['slug'] ?? '').toString().trim().toLowerCase();
          if (s == slug) return true;
        } else {
          final s = (item ?? '').toString().trim().toLowerCase();
          if (s == slug) return true;
        }
      }
      return false;
    }
    bool checkTags(dynamic tags) {
      if (tags is! Map) return false;
      final list = tags['collections'] ??
          tags['wprm_collections'] ??
          tags['wprm_collection'] ??
          tags['collection'];
      return hasSlugInList(list);
    }
    if (checkTags(r['tags'])) return true;
    final recipe = r['recipe'];
    if (recipe is Map) {
      final tags = recipe['tags'];
      if (checkTags(tags)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final popular = widget.recipes.where(_isPopular).toList();
    if (popular.length > widget.limit) {
      popular.removeRange(widget.limit, popular.length);
    }

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? popular
        : popular.where((r) => _titleOf(r).toLowerCase().contains(query)).toList();

    final youngestChild = _policy.youngestChild(_family);
    final youngestMonths = _policy.youngestChildAgeMonths(_family);
    final childNames = _family.children.map((c) => c.name).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          SubHeaderBar(title: widget.title),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchPill(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              hintText: 'Search popular recipes',
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {},
              onClear: () => setState(() {}),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No popular recipes found yet.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withOpacity(0.55),
                            ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = filtered[i];
                      final id = _toInt(r['id']);
                      final title = _titleOf(r);
                      final thumb = _thumbOf(r);
                      final isFav = id != null && widget.favoriteIds.contains(id);

                      final ix = (id != null) ? _indexById[id] : null;
                      
                      final babyTag = (ix != null)
                          ? FoodPolicyCore.babySuitabilityLabel(
                              ix: ix,
                              youngestChild: youngestChild,
                              youngestMonths: youngestMonths,
                            )
                          : null;

                      String? allergyStatus;
                      if (ix != null) {
                        allergyStatus = _calculateAllergyStatus(r, ix.allergies, _swapTextOf(r));
                      }

                      return SmartRecipeCard(
                        title: title,
                        imageUrl: thumb,
                        isFavorite: isFav,
                        onTap: id == null
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RecipeDetailScreen(id: id),
                                  ),
                                ),
                        tags: ix?.suitable ?? [],
                        ageWarning: babyTag,
                        childNames: childNames,
                        allergyStatus: allergyStatus,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
// lib/recipes/latest_recipes_page.dart
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

class LatestRecipesPage extends StatefulWidget {
  const LatestRecipesPage({
    super.key,
    this.title = 'Latest recipes',
    required this.recipes,
    required this.favoriteIds,
    this.limit = 20,
  });

  final String title;
  final List<Map<String, dynamic>> recipes;
  final Set<int> favoriteIds;
  final int limit;

  @override
  State<LatestRecipesPage> createState() => _LatestRecipesPageState();
}

class _LatestRecipesPageState extends State<LatestRecipesPage> {
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
    _indexById.clear();
    final normalised = <Map<String, dynamic>>[];
    for (final r in widget.recipes) {
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
  // ✅ Allergy label (same behaviour as Collections/Favourites fix)
  // ----------------------------------------------------------------------
  String? _calculateAllergyStatus(Map<String, dynamic> recipe, List<String> recipeTags, String swapText) {
    final blockedNames = <String>[];
    final swapNames = <String>[];

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

    // 1) HARD STOP
    if (blockedNames.isNotEmpty) {
      final unique = blockedNames.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      if (unique.length == 1) return "Not suitable for ${unique.first}";
      return "Not suitable for ${unique.length} people";
    }

    // 2) SWAP REQUIRED
    if (swapNames.isNotEmpty) {
      final unique = swapNames.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      if (unique.length == 1) return "Needs swap for ${unique.first}";
      return "Needs swap for ${unique.length} people";
    }

    // 3) SAFE
    if (allergyPeople.isNotEmpty) {
      if (allergyPeople.length == 1) {
        final n = (allergyPeople.first.name ?? '').trim();
        if (n.isNotEmpty) return "Safe for $n";
        return "Safe";
      }
      return "Safe for whole family";
    }

    return null;
  }

  // ----------------------------------------------------------------------
  // DATA HELPERS
  // ----------------------------------------------------------------------

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
              recipe['image'])
          ?.toString();
      if (url != null && url.trim().isNotEmpty) return url.trim();
    }
    return null;
  }

  DateTime _dateOf(Map<String, dynamic> r) {
    final candidates = <dynamic>[
      r['modified_gmt'],
      r['modified'],
      r['date_gmt'],
      r['date'],
      r['updatedAt'],
      r['createdAt'],
      r['updated_at'],
      r['created_at'],
    ];

    for (final c in candidates) {
      final dt = _parseDate(c);
      if (dt != null) return dt;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;

    if (v is int) {
      if (v < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    }

    if (v is num) {
      final i = v.toInt();
      if (i < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(i * 1000, isUtc: true).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(i, isUtc: true).toLocal();
    }

    final s = v.toString().trim();
    if (s.isEmpty) return null;

    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _latestBase() {
    final list = List<Map<String, dynamic>>.from(widget.recipes);
    list.sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    final limit = widget.limit <= 0 ? 20 : widget.limit;
    if (list.length <= limit) return list;
    return list.take(limit).toList();
  }

  @override
  Widget build(BuildContext context) {
    final baseLatest = _latestBase();

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? baseLatest
        : baseLatest.where((r) => _titleOf(r).toLowerCase().contains(query)).toList();

    final youngestChild = _policy.youngestChild(_family);
    final youngestMonths = _policy.youngestChildAgeMonths(_family);
    final childNames = _family.children.map((c) => c.name).toList();
    final householdNames = _householdNames();

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
              hintText: 'Search recipes',
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
                        'No recipes found.',
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
                        allergyStatus = _calculateAllergyStatus(
                          r,
                          ix.allergies,
                          _swapTextOf(r),
                        );
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
                        householdNames: householdNames,
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

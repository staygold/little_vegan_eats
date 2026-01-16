// lib/recipes/recipe_search_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ for status bar style

import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';
import '../theme/app_theme.dart';

import '../utils/text.dart';

import 'recipe_detail_screen.dart';
import 'widgets/smart_recipe_card.dart';

import 'family_profile.dart';
import 'family_profile_repository.dart';
import 'household_food_policy.dart';
import 'food_policy_core.dart';
import 'recipe_index.dart';
import 'recipe_index_builder.dart';
import 'allergy_engine.dart';

class RecipeSearchScreen extends StatefulWidget {
  const RecipeSearchScreen({
    super.key,
    required this.recipes,
    required this.favoriteIds,
    this.hintText = 'Search recipes or by ingredients',
  });

  final List<Map<String, dynamic>> recipes;
  final Set<int> favoriteIds;
  final String hintText;

  @override
  State<RecipeSearchScreen> createState() => _RecipeSearchScreenState();
}

class _RecipeSearchScreenState extends State<RecipeSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  String _query = '';
  List<Map<String, dynamic>> _results = const [];
  bool _hasSearched = false;

  // In-memory only
  final List<String> _recentSearches = <String>[];

  // ✅ Household + index (match Collection/Favourites style)
  final FamilyProfileRepository _familyRepo = FamilyProfileRepository();
  late final HouseholdFoodPolicy _policy = HouseholdFoodPolicy(familyRepo: _familyRepo);
  StreamSubscription<FamilyProfile>? _familySub;
  FamilyProfile _family = const FamilyProfile(adults: [], children: []);

  final Map<int, RecipeIndex> _indexById = {};

  @override
  void initState() {
    super.initState();

    _results = const [];
    _hasSearched = false;

    _buildIndex();
    _listenToHousehold();

    // ensure clear icon updates as you type (SearchPill relies on controller.text)
    _controller.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _familySub?.cancel();
    _controller.dispose();
    _focus.dispose();
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
  // ALLERGY STATUS LABEL (matches Collection)
  // ----------------------------------------------------------------------
  String? _calculateAllergyStatus(
    Map<String, dynamic> recipe,
    List<String> recipeTags,
    String swapText,
  ) {
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

    if (blockedNames.isNotEmpty) {
      final unique = blockedNames
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (unique.length == 1) return "Not suitable for ${unique.first}";
      return "Not suitable for ${unique.length} people";
    }

    if (swapNames.isNotEmpty) {
      final unique = swapNames.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      if (unique.length == 1) return "Needs swap for ${unique.first}";
      return "Needs swap for ${unique.length} people";
    }

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
  // DATA NORMALIZATION + HELPERS (keep aligned with other pages)
  // ----------------------------------------------------------------------

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

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      return (t['rendered'] as String)
          .replaceAll('&#038;', '&')
          .replaceAll('&amp;', '&')
          .trim();
    }
    final s = (r['title'] ?? '').toString().trim();
    return s.isEmpty ? 'Untitled' : s;
  }

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.trim().isNotEmpty) return url.trim();
    }
    return null;
  }

  // (kept because it’s used for keyword search below)
  String? _subtitleOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map) {
      final courses = recipe['courses'];
      if (courses is List && courses.isNotEmpty) {
        final first = courses.first;
        if (first is String && first.trim().isNotEmpty) return first.trim();
        if (first is Map && first['name'] is String) {
          return (first['name'] as String).trim();
        }
      }
    }
    return null;
  }

  // ----------------------------
  // SEARCH
  // ----------------------------

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final q = v.trim();
      setState(() {
        _query = q;
        if (q.isEmpty) {
          _results = const [];
          _hasSearched = false;
        } else {
          _results = _filter(widget.recipes, q);
          _hasSearched = true;
        }
      });
    });
  }

  void _submitSearch(String q) {
    final query = q.trim();
    if (query.isEmpty) return;

    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );

    setState(() {
      _query = query;
      _results = _filter(widget.recipes, query);
      _hasSearched = true;
      _addRecent(query);
    });

    _focus.unfocus();
  }

  void _addRecent(String q) {
    final s = q.trim();
    if (s.isEmpty) return;

    _recentSearches.removeWhere((x) => x.toLowerCase() == s.toLowerCase());
    _recentSearches.insert(0, s);

    if (_recentSearches.length > 10) {
      _recentSearches.removeRange(10, _recentSearches.length);
    }
  }

  List<Map<String, dynamic>> _filter(
    List<Map<String, dynamic>> recipes,
    String query,
  ) {
    if (query.isEmpty) return const [];
    final q = query.toLowerCase();

    return recipes.where((r) {
      final title = _titleOf(r).toLowerCase();
      if (title.contains(q)) return true;

      final recipe = r['recipe'];
      if (recipe is Map) {
        final keywords = <String>[];

        for (final k in ['courses', 'tags', 'categories', 'keywords']) {
          final v = recipe[k];
          if (v is List) {
            for (final item in v) {
              if (item is String) keywords.add(item);
              if (item is Map && item['name'] is String) {
                keywords.add(item['name'] as String);
              }
            }
          }
        }

        // include subtitle/course as a searchable term too (cheap win)
        final sub = _subtitleOf(r);
        if (sub != null && sub.trim().isNotEmpty) keywords.add(sub.trim());

        if (keywords.join(' ').toLowerCase().contains(q)) return true;
      }

      return false;
    }).toList();
  }

  void _openRecipe(Map<String, dynamic> r) {
    final id = _toInt(r['id']);
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: id)),
    );
  }

  void _clearQuery() {
    _controller.clear();
    setState(() {
      _query = '';
      _results = const [];
      _hasSearched = false;
    });
    _focus.requestFocus();
  }

  // ----------------------------
  // UI: EMPTY STATE (recent only)
  // ----------------------------

  Widget _buildEmptySuggestions(BuildContext context) {
    if (_recentSearches.isEmpty) {
      return const SizedBox(height: 24);
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent searches',
            style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              for (final q in _recentSearches)
                _RecentRow(
                  text: q,
                  onTap: () => _submitSearch(q),
                  onRemove: () => setState(() => _recentSearches.remove(q)),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ----------------------------
  // BUILD
  // ----------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final showEmptyState = _query.isEmpty && !_hasSearched;
    final showNoResults = _query.isNotEmpty && _hasSearched && _results.isEmpty;

    final youngestChild = _policy.youngestChild(_family);
    final youngestMonths = _policy.youngestChildAgeMonths(_family);
    final childNames = _family.children.map((c) => c.name).toList();
    final householdNames = _householdNames();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // ✅ Force this screen to use DARK status bar icons
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Android
        statusBarBrightness: Brightness.light, // iOS (light bg -> dark icons)
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFECF3F4),
        body: SafeArea(
          child: Column(
            children: [
              const SubHeaderBar(title: 'SEARCH RECIPES'),

              // ✅ Use the shared SearchPill (SSoT)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: SearchPill(
                  controller: _controller,
                  focusNode: _focus,
                  hintText: widget.hintText,
                  autofocus: true,
                  onChanged: _onQueryChanged,
                  onSubmitted: _submitSearch,
                  onClear: _clearQuery,
                ),
              ),

              Expanded(
                child: showEmptyState
                    ? SingleChildScrollView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        child: _buildEmptySuggestions(context),
                      )
                    : showNoResults
                        ? Center(
                            child: Text(
                              'No results',
                              style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
                                color: Colors.black.withOpacity(0.55),
                              ),
                            ),
                          )
                        : ListView.separated(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final r = _results[i];
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
                                onTap: id == null ? null : () => _openRecipe(r),
                                tags: ix?.suitable ?? const [],
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
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.text,
    required this.onTap,
    required this.onRemove,
  });

  final String text;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Text(
          text,
          style: (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        onTap: onTap,
        trailing: GestureDetector(
          onTap: onRemove,
          child: Icon(
            Icons.close,
            color: Colors.black.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}

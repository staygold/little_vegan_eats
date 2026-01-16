// lib/meal_plan/builder/meal_plan_builder_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../recipes/recipe_repository.dart';
import '../../recipes/family_profile_repository.dart';
import '../../recipes/recipe_index_builder.dart';
import '../../utils/text.dart';

import '../core/meal_plan_controller.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';
import '../meal_plan_screen.dart';
import 'meal_plan_builder_service.dart';

import 'meal_plan_builder_wizard.dart';

/// Controls how this builder is launched
enum MealPlanBuilderEntry { dayOnly, weekOnly, choose, adhocDay }

class MealPlanBuilderScreen extends StatefulWidget {
  final String weekId;
  final MealPlanBuilderEntry entry;
  final String? initialSelectedDayKey;

  const MealPlanBuilderScreen({
    super.key,
    required this.weekId,
    this.entry = MealPlanBuilderEntry.choose,
    this.initialSelectedDayKey,
  });

  @override
  State<MealPlanBuilderScreen> createState() => _MealPlanBuilderScreenState();
}

class _MealPlanBuilderScreenState extends State<MealPlanBuilderScreen> {
  bool _busy = false;
  bool _launchedWizard = false;

  // -----------------------------
  // ✅ NORMALIZATION HELPERS (Robust Version)
  // -----------------------------
  String _titleOf(Map<String, dynamic> r) =>
      (r['title']?['rendered'] as String?)?.trim().isNotEmpty == true
          ? (r['title']['rendered'] as String)
          : 'Untitled';

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

  // ✅ ROBUST SWAP EXTRACTION (Matches Recipe List)
  String _swapTextOf(Map<String, dynamic> r) {
    if (r['ingredient_swaps'] != null) {
      return r['ingredient_swaps'].toString().trim();
    }

    final recipe = r['recipe'];
    if (recipe is Map) {
      final custom = recipe['custom_fields'];
      if (custom is Map) {
        final val = custom['ingredient_swaps'];
        if (val != null && val.toString().trim().isNotEmpty) {
          return val.toString().trim();
        }
      }

      if (recipe['swap_text'] != null) return recipe['swap_text'].toString().trim();
      if (recipe['swaps'] != null) return recipe['swaps'].toString().trim();
    }

    if (r['meta'] is Map) {
      final meta = r['meta'] as Map;
      if (meta['ingredient_swaps'] != null) {
        return meta['ingredient_swaps'].toString().trim();
      }
    }

    return '';
  }

  List<String> _termsOfField(Map<String, dynamic> r, String field) {
    final v = r[field];
    List<String> raw = [];
    if (v is List) {
      raw = v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    } else if (v is int) {
      raw = [v.toString()];
    } else if (v is String && v.trim().isNotEmpty) {
      raw = [v.trim()];
    }
    return raw;
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

  List<String> _collectionsOf(Map<String, dynamic> r) {
    final fromTags = _collectionNamesFromRecipeTags(r);
    if (fromTags.isNotEmpty) return fromTags;
    return _termsOfField(r, 'wprm_collections');
  }

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
    return _termsOfField(r, 'wprm_allergies');
  }

  Map<String, dynamic> _normaliseForIndex(Map<String, dynamic> r) {
    final id = r['id'];
    if (id is! int) return const {};

    return <String, dynamic>{
      'id': id,
      'title': _titleOf(r),
      'ingredients': _ingredientsTextOf(r),
      'wprm_course': _termsOfField(r, 'wprm_course'),
      'wprm_collections': _collectionsOf(r),
      'wprm_cuisine': _termsOfField(r, 'wprm_cuisine'),
      'wprm_suitable_for': _termsOfField(r, 'wprm_suitable_for'),
      'wprm_nutrition_tag': _termsOfField(r, 'wprm_nutrition_tag'),
      'recipe': r['recipe'],
      'meta': r['meta'],
      'ingredient_swaps': _swapTextOf(r),
      'wprm_allergies': _allergyTagsOf(r),
    };
  }

  // -----------------------------
  // Date helpers
  // -----------------------------
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isPastDay(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return true;
    return _dateOnly(dt).isBefore(_dateOnly(DateTime.now()));
  }

  String _firstNonPastKey(List<String> keys) {
    for (final k in keys) {
      if (!_isPastDay(k)) return k;
    }
    return keys.isNotEmpty ? keys.last : MealPlanKeys.todayKey();
  }

  int? _weekdayForDayKey(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    return dt?.weekday;
  }

  // -----------------------------
  // Draft bootstrap
  // -----------------------------
  MealPlanDraft _makeInitialDraft({
    required List<String> weekKeys,
    required bool isAdhoc,
  }) {
    String startKey = MealPlanKeys.todayKey();

    final initDay = (widget.initialSelectedDayKey ?? '').trim();
    if (initDay.isNotEmpty && !_isPastDay(initDay)) {
      startKey = initDay;
    } else if (weekKeys.isNotEmpty) {
      startKey = _firstNonPastKey(weekKeys);
    }

    final draft = MealPlanDraft(startDayKey: startKey);

    final wd = _weekdayForDayKey(startKey);
    if (!isAdhoc && wd != null) {
      draft.weekdays.add(wd);
    }

    if (widget.entry == MealPlanBuilderEntry.dayOnly) {
      draft.weeks = 1;
      final w = wd ?? DateTime.now().weekday;
      draft.weekdays
        ..clear()
        ..add(w);
    }

    if (widget.entry == MealPlanBuilderEntry.weekOnly) {
      draft.weeks = 1;
      draft.weekdays
        ..clear()
        ..addAll([1, 2, 3, 4, 5, 6, 7]);
    }

    if (widget.entry == MealPlanBuilderEntry.adhocDay) {
      draft.weeks = 1; // not used
      draft.weekdays.clear(); // not used
    }

    return draft;
  }

  // -----------------------------
  // Create actions
  // -----------------------------
  Map<String, String> _audiencesPayload(MealPlanDraft d) {
    return <String, String>{
      'breakfast': d.breakfastAudience,
      'lunch': d.lunchAudience,
      'dinner': d.dinnerAudience,
      'snack': d.snackAudience,
    };
  }

  /// ✅ Builds the plan and returns the focus day key.
  /// IMPORTANT: this function does NOT navigate.
  Future<String> _runBuild(MealPlanDraft d, {required bool isAdhoc}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in to create a meal plan.');
    }

    final weekKeys = MealPlanKeys.weekDayKeys(widget.weekId);
    final safeStartKey =
        _isPastDay(d.startDayKey) ? _firstNonPastKey(weekKeys) : d.startDayKey;

    if (isAdhoc) {
      await _createAdhocOneOffDay(dayKey: safeStartKey, d: d);
      return safeStartKey;
    }

    final cleanWeekdays =
        d.weekdays.where((e) => e >= 1 && e <= 7).toList()..sort();
    if (cleanWeekdays.isEmpty) {
      throw Exception('Please select at least one day.');
    }

    final recipes = await RecipeRepository.ensureRecipesLoaded();
    if (recipes.isEmpty) throw Exception('No recipes available.');

    final normalisedRecipes = <Map<String, dynamic>>[];
    for (final r in recipes) {
      final m = _normaliseForIndex(r);
      if (m.isNotEmpty) normalisedRecipes.add(m);
    }

    final controller = MealPlanController(
      auth: FirebaseAuth.instance,
      repo: MealPlanRepository(FirebaseFirestore.instance),
      profileRepo: FamilyProfileRepository(),
      recipeIndexById: RecipeIndexBuilder.buildById(normalisedRecipes),
      initialWeekId: widget.weekId,
    );

    controller.setAllergyPolicy(includeSwaps: d.includeSwaps);
    controller.start();

    final builder = MealPlanBuilderService(controller);

    await builder.buildAndActivate(
      title: d.planName.trim().isNotEmpty ? d.planName.trim() : 'My Meal Plan',
      availableRecipes: recipes,
      startDayKey: safeStartKey,
      weeks: d.weeks,
      weekdays: cleanWeekdays,
      includeBreakfast: d.breakfast,
      includeLunch: d.lunch,
      includeDinner: d.dinner,
      includeSnacks: d.snacksPerDay > 0,
      snackCount: d.snacksPerDay,
      mealAudiences: _audiencesPayload(d),
    );

    return safeStartKey;
  }

  /// ✅ Creates one-off day. IMPORTANT: does NOT navigate.
  Future<void> _createAdhocOneOffDay({
    required String dayKey,
    required MealPlanDraft d,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in to create a meal plan.');
    }

    final recipes = await RecipeRepository.ensureRecipesLoaded();
    if (recipes.isEmpty) throw Exception('No recipes available.');

    final normalisedRecipes = <Map<String, dynamic>>[];
    for (final r in recipes) {
      final m = _normaliseForIndex(r);
      if (m.isNotEmpty) normalisedRecipes.add(m);
    }

    final controller = MealPlanController(
      auth: FirebaseAuth.instance,
      repo: MealPlanRepository(FirebaseFirestore.instance),
      profileRepo: FamilyProfileRepository(),
      recipeIndexById: RecipeIndexBuilder.buildById(normalisedRecipes),
      initialWeekId: widget.weekId,
    );

    controller.setAllergyPolicy(includeSwaps: d.includeSwaps);
    controller.start();

    final builder = MealPlanBuilderService(controller);

    await builder.buildAdhocDay(
      dateKey: dayKey,
      availableRecipes: recipes,
      includeBreakfast: d.breakfast,
      includeLunch: d.lunch,
      includeDinner: d.dinner,
      snackCount: d.snacksPerDay,
      mealAudiences: _audiencesPayload(d),
    );
  }

  Future<void> _openWizard() async {
    if (_busy) return;
    if (_launchedWizard) return;
    _launchedWizard = true;

    final isAdhoc = widget.entry == MealPlanBuilderEntry.adhocDay;
    final weekKeys = MealPlanKeys.weekDayKeys(widget.weekId);

    setState(() => _busy = true);

    try {
      final draft = _makeInitialDraft(
        weekKeys: weekKeys,
        isAdhoc: isAdhoc,
      );

      // ✅ Wizard returns focusDayKey on success, null on cancel
      final focusKey = await Navigator.of(context).push<String?>(
        MaterialPageRoute(
          builder: (_) => MealPlanWizard(
            title: isAdhoc ? 'One-off day' : 'Build meal plan',
            weekId: widget.weekId,
            weekKeys: weekKeys,
            mode: isAdhoc
                ? MealPlanWizardMode.adhocDay
                : MealPlanWizardMode.program,
            draft: draft,
            onClose: () => Navigator.of(context).pop(null),
            onSubmit: () async {
              // returns the focus day key (wizard should pop with this)
              return await _runBuild(draft, isAdhoc: isAdhoc);
            },
          ),
        ),
      );

      if (!mounted) return;

      // Cancelled -> close this screen too
      if (focusKey == null || focusKey.trim().isEmpty) {
        Navigator.of(context).pop();
        return;
      }

      // ✅ Single navigation happens here (prevents flicker)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MealPlanScreen(
            weekId: widget.weekId,
            focusDayKey: focusKey,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();

    // ✅ Go straight into wizard (no start card)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openWizard();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Simple placeholder while wizard is open
    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        title: const Text(''),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 12),
            Text('Opening builder...', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

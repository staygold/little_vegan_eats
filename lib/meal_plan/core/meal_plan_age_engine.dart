// lib/meal_plan/core/meal_plan_age_engine.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'meal_plan_log.dart';

class MealPlanAgeEngine {
  MealPlanAgeEngine._();

  /// Interpreted as: if youngest child is younger than this, we apply baby rules.
  ///
  /// Your stated rule is 6–8 months, so 9 is a sensible default.
  /// If you want it to remain 12, change this back to 12.
  static const int defaultBabyThresholdMonths = 9;

  // ------------------------------------------------------------
  // AGE
  // ------------------------------------------------------------

  /// Returns age in whole months (>=0), or null if DOB cannot be parsed.
  ///
  /// Supports:
  /// - dobMonth + dobYear (preferred)
  /// - legacy `dob` stored as Timestamp/DateTime/String ("YYYY-MM", "MM/YYYY", "DD/MM/YYYY")
  static int? ageInMonths({
    required Map<String, dynamic> child,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();

    final m = child['dobMonth'];
    final y = child['dobYear'];
    if (m is int && y is int && m >= 1 && m <= 12) {
      return _diffInWholeMonths(fromYear: y, fromMonth: m, to: n);
    }

    final raw = child['dob'];
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    if (raw is DateTime) dt = raw;

    if (dt == null && raw is String && raw.trim().isNotEmpty) {
      final s = raw.trim();

      // "YYYY-MM"
      if (s.contains('-')) {
        final parts = s.split('-');
        final yy = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
        final mm = parts.length > 1 ? int.tryParse(parts[1]) : null;
        if (yy != null && mm != null && mm >= 1 && mm <= 12) {
          return _diffInWholeMonths(fromYear: yy, fromMonth: mm, to: n);
        }
      }

      // "MM/YYYY" or "DD/MM/YYYY"
      if (s.contains('/')) {
        final parts = s.split('/');
        if (parts.length == 2) {
          final mm = int.tryParse(parts[0]);
          final yy = int.tryParse(parts[1]);
          if (yy != null && mm != null && mm >= 1 && mm <= 12) {
            return _diffInWholeMonths(fromYear: yy, fromMonth: mm, to: n);
          }
        }
        if (parts.length == 3) {
          final mm = int.tryParse(parts[1]);
          final yy = int.tryParse(parts[2]);
          if (yy != null && mm != null && mm >= 1 && mm <= 12) {
            return _diffInWholeMonths(fromYear: yy, fromMonth: mm, to: n);
          }
        }
      }
    }

    if (dt != null) {
      return _diffInWholeMonths(fromYear: dt.year, fromMonth: dt.month, to: n);
    }

    return null;
  }

  static int _diffInWholeMonths({
    required int fromYear,
    required int fromMonth,
    required DateTime to,
  }) {
    final ym1 = fromYear * 12 + (fromMonth - 1);
    final ym2 = to.year * 12 + (to.month - 1);
    final diff = ym2 - ym1;
    return diff < 0 ? 0 : diff;
  }

  /// Finds the youngest child age in months from a `children` list.
  /// Returns null if no valid DOB data is found.
  static int? youngestAgeMonths({
    required List<dynamic>? children,
    required DateTime onDate,
  }) {
    if (children == null || children.isEmpty) return null;

    int? best; // smallest = youngest
    for (final c in children) {
      if (c is! Map) continue;
      final child = Map<String, dynamic>.from(c);

      final m = child['dobMonth'];
      final y = child['dobYear'];
      int? age;

      if (m is int && y is int && m >= 1 && m <= 12) {
        age = _diffInWholeMonths(fromYear: y, fromMonth: m, to: onDate);
      } else {
        age = ageInMonths(child: child, now: onDate);
      }

      if (age == null) continue;
      if (best == null || age < best) best = age;
    }
    return best;
  }

  // ------------------------------------------------------------
  // FIRST FOODS GATE
  // ------------------------------------------------------------

  static bool _isSnackSlot(String slotKey) {
    final k = slotKey.trim().toLowerCase();
    return k == 'snack' ||
        k == 'snack1' ||
        k == 'snack2' ||
        k == 'snack_1' ||
        k == 'snack_2';
  }

  static bool _tokenIsFirstFoods(String s) {
    final v = s.trim().toLowerCase();
    if (v.isEmpty) return false;
    return v.contains('first-foods') ||
        v.contains('first foods') ||
        v.contains('first_foods');
  }

  /// Robustly detects "First Foods" in WPRM payloads.
  ///
  /// Your WP example stores it in:
  /// recipe.recipe.tags.collections[].slug == "first-foods"
  /// recipe.recipe.tags.collections[].name == "First Foods"
  ///
  /// But your app can pass flattened variants too, so we also check:
  /// - recipe.tags.collections
  /// - recipe.taxonomies.collections / recipe.taxonomies.collections[]
  /// - recipe.collections / recipe.collection
  /// - recipe.wprm_collections (if it ever becomes a list of term maps)
  static bool _isFirstFoodsRecipe(Map<String, dynamic> recipe) {
    bool hasFirstFoods(dynamic v) {
      if (v == null) return false;

      if (v is bool) return v;

      if (v is String) return _tokenIsFirstFoods(v);

      if (v is num) return false;

      if (v is List) {
        for (final item in v) {
          if (hasFirstFoods(item)) return true;
        }
        return false;
      }

      if (v is Map) {
        final m = Map<String, dynamic>.from(v);

        // Common term-map shapes: {slug,name,taxonomy,...}
        final slug = (m['slug'] ?? '').toString();
        final name = (m['name'] ?? '').toString();
        if (_tokenIsFirstFoods(slug) || _tokenIsFirstFoods(name)) return true;

        // Some shapes use {term, label}
        final term = (m['term'] ?? m['label'] ?? '').toString();
        if (_tokenIsFirstFoods(term)) return true;

        // Otherwise traverse values
        for (final entry in m.entries) {
          if (hasFirstFoods(entry.value)) return true;
        }
        return false;
      }

      return false;
    }

    // 1) direct flags
    if (recipe['first_foods'] == true) return true;

    // 2) flattened keys that might exist in your ingest
    if (hasFirstFoods(recipe['collections'])) return true;
    if (hasFirstFoods(recipe['collection'])) return true;
    if (hasFirstFoods(recipe['category'])) return true;
    if (hasFirstFoods(recipe['categories'])) return true;
    if (hasFirstFoods(recipe['tags'])) return true;

    // 3) taxonomies bucket
    final tax = recipe['taxonomies'];
    if (tax is Map) {
      final t = Map<String, dynamic>.from(tax);
      if (hasFirstFoods(t['collections'])) return true;
      if (hasFirstFoods(t['collection'])) return true;
      if (hasFirstFoods(t['wprm_collections'])) return true;
    }

    // 4) WPRM top-level arrays
    if (hasFirstFoods(recipe['wprm_collections'])) return true;

    // 5) nested WP "recipe" object
    final inner = recipe['recipe'];
    if (inner is Map) {
      final m = Map<String, dynamic>.from(inner);

      if (m['first_foods'] == true) return true;

      // nested tags.collections (canonical path)
      final tags = m['tags'];
      if (tags is Map) {
        final tm = Map<String, dynamic>.from(tags);
        if (hasFirstFoods(tm['collections'])) return true;
      }

      // other defensive checks
      if (hasFirstFoods(m['collections'])) return true;
      if (hasFirstFoods(m['collection'])) return true;
      if (hasFirstFoods(m['tags'])) return true;
      if (hasFirstFoods(m['taxonomies'])) return true;
      if (hasFirstFoods(m['wprm_collections'])) return true;
    }

    return false;
  }

  /// Enforces your baby rule for kids-audience slots:
  /// - youngest < threshold:
  ///     - snacks => first foods only
  ///     - meals => none allowed
  /// - otherwise => allow
  static bool allowRecipeForSlotUsingFirstFoodsGate({
    required Map<String, dynamic> recipe,
    required String slotKey,
    required List<dynamic>? children,
    int babyThresholdMonths = defaultBabyThresholdMonths,
    DateTime? servingDate,
  }) {
    final dt = servingDate ?? DateTime.now();

    final youngest = youngestAgeMonths(children: children, onDate: dt);

    MealPlanLog.d(
      'AGE_GATE slot=$slotKey youngest=$youngest threshold=$babyThresholdMonths children=${children?.length ?? 0} date=${dt.toIso8601String()}',
    );

    // If we can’t compute a youngest age, don’t block recipes (avoid bricking plans).
    if (youngest == null) return true;

    if (youngest >= babyThresholdMonths) return true;

    // Baby rules:
    if (_isSnackSlot(slotKey)) {
      final isFF = _isFirstFoodsRecipe(recipe);

      final id = (recipe['id'] ??
          (recipe['recipe'] is Map ? (recipe['recipe'] as Map)['id'] : null));
      final title = (recipe['title'] ??
          (recipe['recipe'] is Map ? (recipe['recipe'] as Map)['name'] : null));

      MealPlanLog.d('AGE_GATE snack recipe id=$id title=$title firstFoods=$isFF');

      return isFF;
    }

    // meals not allowed for baby in kids-audience slots
    return false;
  }
}

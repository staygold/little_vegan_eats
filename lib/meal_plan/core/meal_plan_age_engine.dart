// lib/meal_plan/core/meal_plan_age_engine.dart

import '../../recipes/recipe_index.dart';

class MealPlanAgeEngine {
  static const int defaultBabyThresholdMonths = 9;

  // -------------------------------------------------------
  // Age helpers
  // -------------------------------------------------------
  static int? childAgeMonths(Map<String, dynamic> child, DateTime onDate) {
    // Supports:
    // - dob as DateTime
    // - dob as ISO string
    // - dob as millis
    // - dobMonth/dobYear
    final dob = child['dob'];

    DateTime? birth;
    if (dob is DateTime) {
      birth = dob;
    } else if (dob is String) {
      birth = DateTime.tryParse(dob);
    } else if (dob is num) {
      birth = DateTime.fromMillisecondsSinceEpoch(dob.toInt());
    }

    if (birth == null) {
      final m = child['dobMonth'];
      final y = child['dobYear'];
      final mm = (m is int) ? m : int.tryParse(m?.toString() ?? '');
      final yy = (y is int) ? y : int.tryParse(y?.toString() ?? '');
      if (mm != null && yy != null && mm >= 1 && mm <= 12) {
        birth = DateTime(yy, mm, 1);
      }
    }

    if (birth == null) return null;

    int months = (onDate.year - birth.year) * 12 + (onDate.month - birth.month);
    if (onDate.day < birth.day) months -= 1;
    if (months < 0) months = 0;
    return months;
  }

  static Map<String, dynamic>? youngestChild(
    List<Map<String, dynamic>> children,
    DateTime onDate,
  ) {
    if (children.isEmpty) return null;

    Map<String, dynamic>? best;
    int? bestAge;

    for (final c in children) {
      final age = childAgeMonths(c, onDate);
      if (age == null) continue;
      if (best == null || age < (bestAge ?? 999999)) {
        best = c;
        bestAge = age;
      }
    }
    return best;
  }

  static int? youngestAgeMonths({
    required List<Map<String, dynamic>> children,
    required DateTime onDate,
  }) {
    final y = youngestChild(children, onDate);
    if (y == null) return null;
    return childAgeMonths(y, onDate);
  }

  // Eldest child = max age (your “target child” rule when 2+ kids)
  static Map<String, dynamic>? targetChildForKidsAudience(
    List<Map<String, dynamic>> children,
    DateTime onDate,
  ) {
    if (children.isEmpty) return null;

    Map<String, dynamic>? best;
    int? bestAge;

    for (final c in children) {
      final age = childAgeMonths(c, onDate);
      if (age == null) continue;
      if (best == null || age > (bestAge ?? -1)) {
        best = c;
        bestAge = age;
      }
    }
    return best;
  }

  // -------------------------------------------------------
  // ✅ first_foods detection (recipe map only)
  // -------------------------------------------------------
  static bool _isFirstFoodsFromRecipe(Map<String, dynamic> recipe) {
    Map<String, dynamic> r = recipe;
    if (recipe['recipe'] is Map) {
      r = Map<String, dynamic>.from(recipe['recipe'] as Map);
    }

    bool containsToken(dynamic v) {
      if (v == null) return false;

      if (v is String) {
        final s = v.toLowerCase();
        return s.contains('first_foods') || s.contains('first foods') || s.contains('first-foods');
      }

      if (v is List) {
        for (final item in v) {
          if (containsToken(item)) return true;
        }
        return false;
      }

      if (v is Map) {
        for (final entry in v.entries) {
          if (containsToken(entry.key)) return true;
          if (containsToken(entry.value)) return true;
        }
        return false;
      }

      // numbers/bools etc -> no
      return false;
    }

    // Most likely places
    if (containsToken(r['first_foods']) || containsToken(r['firstFoods'])) return true;

    final tags = r['tags'];
    if (tags is Map && containsToken(tags)) return true;

    final tax = r['taxonomies'];
    if (tax is Map && containsToken(tax)) return true;

    // fallback: search entire map
    if (containsToken(r)) return true;

    return false;
  }

  // -------------------------------------------------------
  // ✅ SSOT age gating for kids audience
  // -------------------------------------------------------
  static bool allowForKidsAudience({
    required String slotKey,
    required List<Map<String, dynamic>> children,
    required DateTime servingDate,
    required RecipeIndex ix,
    required Map<String, dynamic> recipe,
    int babyThresholdMonths = defaultBabyThresholdMonths,
  }) {
    if (children.isEmpty) return true;

    final isFirstFoods = _isFirstFoodsFromRecipe(recipe);

    final youngest = youngestChild(children, servingDate);
    final youngestAge =
        youngest == null ? null : childAgeMonths(youngest, servingDate);

    // If we can't compute age, be strict: only first_foods.
    if (youngestAge == null) return isFirstFoods;

    final isBaby = youngestAge <= babyThresholdMonths;
    final isBabyOnlyFamily = isBaby && children.length == 1;

    // ✅ STRICT RULE: baby-only + kids audience => (6m+ OR first_foods) ONLY
    if (isBabyOnlyFamily) {
      if (isFirstFoods) return true;

      final minAge = ix.minAgeMonths;

      // Unknown minAge? REJECT. This is what was letting “safe for kids” leak.
      if (minAge == null) return false;

      return minAge <= youngestAge;
    }

    // Multi-child family: target child = eldest
    final target = targetChildForKidsAudience(children, servingDate);
    final targetAge = target == null ? null : childAgeMonths(target, servingDate);

    if (targetAge == null) return isFirstFoods;

    final minAge = ix.minAgeMonths;

    // If minAge missing in multi-child families:
    // allow (and your warning system should handle messaging).
    if (minAge == null) return true;

    return minAge <= targetAge;
  }
}

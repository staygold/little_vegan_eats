// lib/meal_plan/core/meal_plan_age_engine.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'meal_plan_log.dart';

class MealPlanAgeEngine {
  MealPlanAgeEngine._();

  static const int defaultBabyThresholdMonths = 9;

  static int? ageInMonths({
    required Map<String, dynamic> child,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();

    int? parseInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    }

    final m = parseInt(child['dobMonth']);
    final y = parseInt(child['dobYear']);
    if (m != null && y != null && m >= 1 && m <= 12) {
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

      // try ISO DateTime parse
      final parsed = DateTime.tryParse(s);
      if (parsed != null) {
        return _diffInWholeMonths(fromYear: parsed.year, fromMonth: parsed.month, to: n);
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

  static int? youngestAgeMonths({
    required List<dynamic>? children,
    required DateTime onDate,
  }) {
    if (children == null || children.isEmpty) return null;

    int? best;
    for (final c in children) {
      if (c is! Map) continue;
      final child = Map<String, dynamic>.from(c);

      final age = ageInMonths(child: child, now: onDate);
      if (age == null) continue;

      if (best == null || age < best) best = age;
    }
    return best;
  }

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
        final slug = (m['slug'] ?? '').toString();
        final name = (m['name'] ?? '').toString();
        if (_tokenIsFirstFoods(slug) || _tokenIsFirstFoods(name)) return true;

        final term = (m['term'] ?? m['label'] ?? '').toString();
        if (_tokenIsFirstFoods(term)) return true;

        for (final entry in m.entries) {
          if (hasFirstFoods(entry.value)) return true;
        }
        return false;
      }

      return false;
    }

    if (recipe['first_foods'] == true) return true;

    if (hasFirstFoods(recipe['collections'])) return true;
    if (hasFirstFoods(recipe['collection'])) return true;
    if (hasFirstFoods(recipe['category'])) return true;
    if (hasFirstFoods(recipe['categories'])) return true;
    if (hasFirstFoods(recipe['tags'])) return true;

    final tax = recipe['taxonomies'];
    if (tax is Map) {
      final t = Map<String, dynamic>.from(tax);
      if (hasFirstFoods(t['collections'])) return true;
      if (hasFirstFoods(t['collection'])) return true;
      if (hasFirstFoods(t['wprm_collections'])) return true;
    }

    if (hasFirstFoods(recipe['wprm_collections'])) return true;

    final inner = recipe['recipe'];
    if (inner is Map) {
      final m = Map<String, dynamic>.from(inner);

      if (m['first_foods'] == true) return true;

      final tags = m['tags'];
      if (tags is Map) {
        final tm = Map<String, dynamic>.from(tags);
        if (hasFirstFoods(tm['collections'])) return true;
      }

      if (hasFirstFoods(m['collections'])) return true;
      if (hasFirstFoods(m['collection'])) return true;
      if (hasFirstFoods(m['tags'])) return true;
      if (hasFirstFoods(m['taxonomies'])) return true;
      if (hasFirstFoods(m['wprm_collections'])) return true;
    }

    return false;
  }

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

    if (youngest == null) return true;
    if (youngest >= babyThresholdMonths) return true;

    if (_isSnackSlot(slotKey)) {
      final isFF = _isFirstFoodsRecipe(recipe);
      final id = (recipe['id'] ??
          (recipe['recipe'] is Map ? (recipe['recipe'] as Map)['id'] : null));
      final title = (recipe['title'] ??
          (recipe['recipe'] is Map ? (recipe['recipe'] as Map)['name'] : null));

      MealPlanLog.d('AGE_GATE snack recipe id=$id title=$title firstFoods=$isFF');
      return isFF;
    }

    return false;
  }
}

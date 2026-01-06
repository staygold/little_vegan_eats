// lib/meal_plan/builder/meal_plan_config.dart

import '../core/meal_plan_keys.dart';

enum MealPlanHorizon { day, week }

class MealPlanConfig {
  // ✅ stable identity / audit
  final String weekId;
  final int createdAtMs;

  // ✅ builder can omit these
  final String title;

  // ✅ build scope
  final MealPlanHorizon horizon;

  /// If horizon == day, this is the dayKey to apply (yyyy-mm-dd).
  /// If horizon == week, can be null.
  final String? startDayKey;

  /// How many days to generate/affect (1..7 usually)
  final int daysCount;

  /// 0, 1, or 2 (your app uses snack1 + snack2 slots)
  final int snacksPerDay;

  /// Slot toggles
  final bool breakfast;
  final bool lunch;
  final bool dinner;

  /// Future-safe bag for extra options without breaking older docs
  final Map<String, dynamic> extras;

  const MealPlanConfig({
    required this.weekId,
    required this.createdAtMs,

    // ✅ default so builder doesn't need to provide it
    this.title = '',

    required this.horizon,

    // ✅ default so builder doesn't need to provide it
    this.daysCount = 7,

    this.startDayKey,

    this.snacksPerDay = 2,
    this.breakfast = true,
    this.lunch = true,
    this.dinner = true,
    this.extras = const <String, dynamic>{},
  });

  // ----------------------------
  // Helpers / validation-ish
  // ----------------------------

  int get snacksClamped {
    final v = snacksPerDay;
    if (v < 0) return 0;
    if (v > 2) return 2;
    return v;
  }

  int get daysClamped {
    final v = daysCount;
    if (v < 1) return 1;
    if (v > 7) return 7;
    return v;
  }

  String? get effectiveStartDayKey {
    if (horizon == MealPlanHorizon.day) {
      final k = (startDayKey ?? '').trim();
      return k.isEmpty ? MealPlanKeys.todayKey() : k;
    }
    return null;
  }

  // ----------------------------
  // JSON
  // ----------------------------

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'weekId': weekId,
      'createdAtMs': createdAtMs,
      'title': title,
      'horizon': horizon.name,
      'startDayKey': startDayKey,
      'daysCount': daysCount,
      'snacksPerDay': snacksPerDay,
      'breakfast': breakfast,
      'lunch': lunch,
      'dinner': dinner,
      'extras': extras,
    };
  }

  static MealPlanConfig fromJson(Map<String, dynamic> m) {
    final rawH = (m['horizon'] ?? 'week').toString().trim().toLowerCase();
    final h = (rawH == 'day') ? MealPlanHorizon.day : MealPlanHorizon.week;

    int _asInt(dynamic v, {required int fallback}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? fallback;
      return fallback;
    }

    bool _asBool(dynamic v, {required bool fallback}) {
      if (v is bool) return v;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      if (v is num) return v != 0;
      return fallback;
    }

    Map<String, dynamic> _asMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return <String, dynamic>{};
    }

    final weekId = (m['weekId'] ?? '').toString().trim();
    final createdAtMs = _asInt(
      m['createdAtMs'],
      fallback: DateTime.now().millisecondsSinceEpoch,
    );

    return MealPlanConfig(
      weekId: weekId.isNotEmpty ? weekId : MealPlanKeys.currentWeekId(),
      createdAtMs: createdAtMs,
      title: (m['title'] ?? '').toString().trim(),
      horizon: h,
      startDayKey: (m['startDayKey'] ?? '').toString().trim().isEmpty
          ? null
          : (m['startDayKey'] ?? '').toString().trim(),
      daysCount: _asInt(m['daysCount'], fallback: 7),
      snacksPerDay: _asInt(m['snacksPerDay'], fallback: 2),
      breakfast: _asBool(m['breakfast'], fallback: true),
      lunch: _asBool(m['lunch'], fallback: true),
      dinner: _asBool(m['dinner'], fallback: true),
      extras: _asMap(m['extras']),
    );
  }

  MealPlanConfig copyWith({
    String? weekId,
    int? createdAtMs,
    String? title,
    MealPlanHorizon? horizon,
    String? startDayKey,
    int? daysCount,
    int? snacksPerDay,
    bool? breakfast,
    bool? lunch,
    bool? dinner,
    Map<String, dynamic>? extras,
  }) {
    return MealPlanConfig(
      weekId: weekId ?? this.weekId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      title: title ?? this.title,
      horizon: horizon ?? this.horizon,
      startDayKey: startDayKey ?? this.startDayKey,
      daysCount: daysCount ?? this.daysCount,
      snacksPerDay: snacksPerDay ?? this.snacksPerDay,
      breakfast: breakfast ?? this.breakfast,
      lunch: lunch ?? this.lunch,
      dinner: dinner ?? this.dinner,
      extras: extras ?? this.extras,
    );
  }
}

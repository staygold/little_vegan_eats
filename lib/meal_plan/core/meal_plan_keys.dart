// lib/meal_plan/core/meal_plan_keys.dart

/// Centralised keys + date logic for Meal Plans
/// ------------------------------------------------
///
/// ✅ New design principles:
/// • A "week" is Monday → Sunday (always)
/// • The Firestore week document ID == the Monday dayKey of that week
/// • All screens (Home, Hub, MealPlanScreen) must use this
///
/// This file is the ONLY place date / key logic should live.
/// ------------------------------------------------

class MealPlanKeys {
  MealPlanKeys._();

  // ---------- Date helpers ----------

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// YYYY-MM-DD
  static String dayKey(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static DateTime? parseDayKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;

    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);

    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static String todayKey() => dayKey(_dateOnly(DateTime.now()));

  // ---------- Week semantics (MON-SUN) ----------

  static DateTime weekStartMonday(DateTime anyDay) {
    final d = _dateOnly(anyDay);
    final delta = d.weekday - DateTime.monday; // Mon=0
    return d.subtract(Duration(days: delta));
  }

  /// Week doc id == Monday of week (YYYY-MM-DD)
  static String weekIdForDate(DateTime anyDay) => dayKey(weekStartMonday(anyDay));

  /// Current week doc id (Monday)
  static String currentWeekId() => weekIdForDate(DateTime.now());

  /// Day keys belonging to this week (Mon..Sun)
  static List<String> weekDayKeys(String weekId) {
    final start = parseDayKey(weekId) ?? weekStartMonday(DateTime.now());
    return List.generate(7, (i) => dayKey(start.add(Duration(days: i))));
  }

  static String nextWeekId(String weekId) {
    final start = parseDayKey(weekId) ?? weekStartMonday(DateTime.now());
    return dayKey(start.add(const Duration(days: 7)));
  }

  static String prevWeekId(String weekId) {
    final start = parseDayKey(weekId) ?? weekStartMonday(DateTime.now());
    return dayKey(start.subtract(const Duration(days: 7)));
  }

  static bool isDayKeyInWeek(String weekId, String dayKey) {
    final keys = weekDayKeys(weekId);
    return keys.contains(dayKey);
  }

  // ---------- Display helpers ----------

  static String formatPretty(String dayKey) {
    final dt = parseDayKey(dayKey);
    if (dt == null) return dayKey;

    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final weekday = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];

    return '$weekday, ${dt.day} $month';
  }

  /// Single-letter weekday for tabs (M T W T F S S)
  static String weekdayLetter(DateTime dt) {
    switch (dt.weekday) {
      case DateTime.monday:
        return 'M';
      case DateTime.tuesday:
        return 'T';
      case DateTime.wednesday:
        return 'W';
      case DateTime.thursday:
        return 'T';
      case DateTime.friday:
        return 'F';
      case DateTime.saturday:
        return 'S';
      case DateTime.sunday:
        return 'S';
      default:
        return '';
    }
  }
}

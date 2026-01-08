// lib/meal_plan/core/meal_plan_keys.dart

class MealPlanKeys {
  MealPlanKeys._();

  // -------------------------------------------------------
  // CORE DATE FORMATTERS
  // -------------------------------------------------------

  /// YYYY-MM-DD from DateTime (local, no TZ drift)
  static String dayKeyFromDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// LEGACY ALIAS (widely used)
  static String dayKey(DateTime d) => dayKeyFromDate(d);

  /// Parses YYYY-MM-DD
  static DateTime? parseDayKey(String key) {
    try {
      final p = key.split('-');
      if (p.length != 3) return null;
      return DateTime(
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]),
      );
    } catch (_) {
      return null;
    }
  }

  /// Today as YYYY-MM-DD
  static String todayKey() {
    final now = DateTime.now();
    return dayKeyFromDate(DateTime(now.year, now.month, now.day));
  }

  // -------------------------------------------------------
  // WEEK HELPERS (MONDAY START)
  // -------------------------------------------------------

  /// Monday of the week for a date
  static DateTime weekStartMonday(DateTime d) {
    final date = DateTime(d.year, d.month, d.day);
    final diff = date.weekday - DateTime.monday;
    return date.subtract(Duration(days: diff));
  }

  /// Week ID = Monday date (YYYY-MM-DD)
  static String weekIdFromDate(DateTime d) {
    return dayKeyFromDate(weekStartMonday(d));
  }

  /// LEGACY ALIASES
  static String weekIdForDate(DateTime d) => weekIdFromDate(d);

  static String currentWeekId() => weekIdFromDate(DateTime.now());

  /// Returns 7 day keys for a week (Mon → Sun)
  static List<String> weekDayKeys(String weekId) {
    final start = parseDayKey(weekId);
    if (start == null) return const [];
    return List.generate(
      7,
      (i) => dayKeyFromDate(start.add(Duration(days: i))),
    );
  }

  /// Validates a day belongs to a week
  static bool isDayKeyInWeek(String weekId, String dayKey) {
    return weekDayKeys(weekId).contains(dayKey);
  }

  // -------------------------------------------------------
  // DISPLAY HELPERS (USED ALL OVER UI)
  // -------------------------------------------------------

  static String weekdayLetter(DateTime dt) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return letters[(dt.weekday - 1).clamp(0, 6)];
  }

  static String formatPretty(String dayKey) {
    final d = parseDayKey(dayKey);
    if (d == null) return dayKey;

    const weekdays = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }
}

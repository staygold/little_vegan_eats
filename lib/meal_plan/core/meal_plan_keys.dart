// lib/meal_plan/core/meal_plan_keys.dart
class MealPlanKeys {
  MealPlanKeys._();

  // --------------------------
  // Core date helpers
  // --------------------------

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Key format: yyyy-MM-dd
  static String dayKey(DateTime date) {
    final d = _dateOnly(date);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static DateTime? parseDayKey(String key) {
    final s = key.trim();
    if (s.isEmpty) return null;

    final parts = s.split('-');
    if (parts.length != 3) return null;

    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;

    return DateTime(y, m, d);
  }

  // --------------------------
  // Today / current week
  // --------------------------

  static String todayKey() => dayKey(DateTime.now());

  /// We treat a weekId as the dayKey of the Monday for that week.
  static String currentWeekId() => weekIdForDate(DateTime.now());

  // --------------------------
  // Week math
  // --------------------------

  /// Monday start of week for any date.
  static DateTime weekStartMonday(DateTime date) {
    final d = _dateOnly(date);
    // Dart: Monday=1 ... Sunday=7
    final delta = d.weekday - DateTime.monday;
    return d.subtract(Duration(days: delta));
  }

  /// Alias used by some older code paths.
  static DateTime startOfWeek(DateTime date) => weekStartMonday(date);

  /// Week id for a date (Monday key).
  static String weekIdForDate(DateTime date) => dayKey(weekStartMonday(date));

  /// 7 dayKeys for the given weekId (Mon..Sun).
  /// weekId is expected to be the Monday key, but if it isn't, we normalize it.
  static List<String> weekDayKeys(String weekId) {
    final parsed = parseDayKey(weekId) ?? DateTime.now();
    final monday = weekStartMonday(parsed);
    return List.generate(7, (i) => dayKey(monday.add(Duration(days: i))));
  }

  // --------------------------
  // UI helpers
  // --------------------------

  static String weekdayLetter(DateTime dt) {
    // Your UI expects a single character (M T W T F S S)
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

  static String formatPretty(String dayKeyStr) {
    final d = parseDayKey(dayKeyStr);
    if (d == null) return dayKeyStr;

    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final w = wd[(d.weekday - 1).clamp(0, 6)];
    final m = mo[(d.month - 1).clamp(0, 11)];
    return '$w ${d.day} $m';
  }
}

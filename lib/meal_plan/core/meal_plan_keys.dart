/// Centralised keys + date logic for Meal Plans
/// ------------------------------------------------
///
/// Design principles:
/// • A "week" is forward-anchored (today → next 7 days)
/// • The Firestore week document ID == todayKey
/// • All screens (Home, Hub, MealPlanScreen) must use this
///
/// This file is the ONLY place date / key logic should live.
/// ------------------------------------------------

class MealPlanKeys {
  MealPlanKeys._(); // no instances

  // ---------- Date helpers ----------

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// YYYY-MM-DD
  static String dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Today's day key (local time)
  static String todayKey() => dayKey(_dateOnly(DateTime.now()));

  // ---------- Week semantics ----------

  /// Forward-anchored planning week
  ///
  /// This is intentionally NOT Monday-based.
  /// If today is Sunday, the "week" starts Sunday.
  ///
  /// Firestore path:
  /// users/{uid}/mealPlansWeeks/{weekId}
  static String currentWeekId() => todayKey();

  /// Day keys belonging to this week (7 days forward)
  static List<String> weekDayKeys(String weekId) {
    final start = parseDayKey(weekId) ?? _dateOnly(DateTime.now());
    return List.generate(
      7,
      (i) => dayKey(start.add(Duration(days: i))),
    );
  }

  // ---------- Parsing ----------

  static DateTime? parseDayKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;

    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);

    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  // ---------- Display helpers ----------

  static String formatPretty(String dayKey) {
    final dt = parseDayKey(dayKey);
    if (dt == null) return dayKey;

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final weekday = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];

    return '$weekday, ${dt.day} $month';
  }

  /// Single-letter weekday for tabs (S M T W T F S)
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

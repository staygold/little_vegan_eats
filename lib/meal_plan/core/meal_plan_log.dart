// lib/meal_plan/core/meal_plan_log.dart
import 'package:flutter/foundation.dart';

/// Simple leveled logger with:
/// - default OFF in release builds
/// - per-key rate limiting to prevent spam from loops
class MealPlanLog {
  MealPlanLog._();

  /// Log levels (smaller = more important).
  static const int levelError = 0;
  static const int levelWarn = 1;
  static const int levelInfo = 2;
  static const int levelDebug = 3;
  static const int levelTrace = 4;

  /// ✅ Enabled by default only in debug builds.
  static bool enabled = kDebugMode;

  /// ✅ Control verbosity without deleting logs.
  /// Recommended defaults:
  /// - Debug: levelInfo or levelDebug (2 or 3)
  /// - When diagnosing spam: levelWarn (1)
  static int minLevel = levelInfo;

  /// ✅ Rate limiting (per key).
  static int _windowMs = 2000; // 2s window
  static final Map<String, int> _lastMs = {};
  static final Map<String, int> _suppressed = {};

  /// Change how aggressively spam is suppressed.
  static void configure({
    bool? isEnabled,
    int? minimumLevel,
    int? windowMs,
  }) {
    if (isEnabled != null) enabled = isEnabled;
    if (minimumLevel != null) minLevel = minimumLevel;
    if (windowMs != null) _windowMs = windowMs.clamp(250, 60000);
  }

  static void d(String message, {String tag = 'MEALPLAN', String? key}) =>
      _log(levelDebug, message, tag: tag, key: key);

  static void i(String message, {String tag = 'MEALPLAN', String? key}) =>
      _log(levelInfo, message, tag: tag, key: key);

  static void w(String message, {String tag = 'MEALPLAN', String? key}) =>
      _log(levelWarn, message, tag: tag, key: key);

  static void e(
    String message, {
    String tag = 'MEALPLAN',
    Object? error,
    StackTrace? st,
    String? key,
  }) {
    _log(levelError, '❌ $message', tag: tag, key: key);
    if (!enabled || levelError > minLevel) return;
    if (error != null) debugPrint('$tag error: $error');
    if (st != null) debugPrint('$tag stack: $st');
  }

  static void _log(
    int level,
    String message, {
    required String tag,
    String? key,
  }) {
    if (!enabled) return;
    if (level > minLevel) return;

    // If a key is provided, rate limit per key.
    if (key != null && key.trim().isNotEmpty) {
      final k = '$tag::$key';
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastMs[k];

      if (last != null && (now - last) < _windowMs) {
        _suppressed[k] = (_suppressed[k] ?? 0) + 1;
        return;
      }

      // flush suppression count before printing next message for this key
      final sup = _suppressed.remove(k);
      if (sup != null && sup > 0) {
        debugPrint('$tag: (suppressed $sup similar logs for "$key" in last ${_windowMs}ms)');
      }

      _lastMs[k] = now;
    }

    final prefix = switch (level) {
      levelError => '❌',
      levelWarn => '⚠️',
      levelInfo => 'ℹ️',
      levelDebug => '•',
      _ => '…',
    };

    debugPrint('$tag $prefix $message');
  }
}

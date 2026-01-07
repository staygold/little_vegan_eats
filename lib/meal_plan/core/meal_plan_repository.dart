// lib/meal_plan/core/meal_plan_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'meal_plan_keys.dart';

class MealPlanRepository {
  final FirebaseFirestore _firestore;
  MealPlanRepository(this._firestore);

  // -------------------------------------------------------
  // Refs
  // -------------------------------------------------------

  DocumentReference<Map<String, dynamic>> weekDoc({
    required String uid,
    required String weekId,
  }) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('mealPlansWeeks')
        .doc(weekId);
  }

  // -------------------------------------------------------
  // Watch (controller depends on this)
  // -------------------------------------------------------

  Stream<Map<String, dynamic>?> watchWeek({
    required String uid,
    required String weekId,
  }) {
    return weekDoc(uid: uid, weekId: weekId).snapshots().map((snap) => snap.data());
  }

  // -------------------------------------------------------
  // Week bootstrap
  // -------------------------------------------------------

  /// Creates week doc if missing and ensures it has 7 horizon day keys.
  Future<void> ensureWeekExists({
    required String uid,
    required String weekId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    final snap = await ref.get();

    final dayKeys = MealPlanKeys.weekDayKeys(weekId);
    final baseDays = <String, dynamic>{
      for (final dk in dayKeys) dk: <String, dynamic>{},
    };

    if (!snap.exists) {
      await ref.set({
        'weekId': weekId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'days': baseDays,
        'config': <String, dynamic>{
          // New + legacy fields for broad compatibility
          'mode': 'empty', // empty | day | week
          'activeMode': 'week', // week | day (legacy)
          'daysToPlan': 7,
        },
      });
      return;
    }

    // Ensure missing day keys exist (merge-friendly)
    final data = snap.data();
    final existingDays = (data?['days'] is Map) ? (data!['days'] as Map) : null;
    final updates = <String, dynamic>{};

    if (existingDays == null) {
      updates['days'] = baseDays;
    } else {
      for (final dk in dayKeys) {
        if (!existingDays.containsKey(dk)) {
          updates['days.$dk'] = <String, dynamic>{};
        }
      }
    }

    if (updates.isNotEmpty) {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await ref.update(updates);
    }
  }

  // -------------------------------------------------------
  // Authoritative activation methods (Hub + Builder friendly)
  // -------------------------------------------------------

  /// Replaces the entire active week schedule with a WEEK plan.
  /// Used by builder + “activate week plan” flows.
  ///
  /// ✅ IMPORTANT: Firestore does NOT allow FieldValue.delete() inside nested maps.
  /// So we patch config via dotted paths.
  Future<void> activateWeekPlan({
    required String uid,
    required String weekId,
    required Map<String, Map<String, dynamic>> days,
    required String sourceWeekPlanId,
    Map<String, dynamic>? configPatch,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);

    await ref.set({
      'weekId': weekId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final update = <String, dynamic>{
      'days': days, // ✅ replace whole map
      'config.mode': 'week',
      'config.activeMode': 'week',
      'config.daysToPlan': 7,
      'config.sourceWeekPlanId': sourceWeekPlanId,
      // week plan ignores daySources
      'config.daySources': FieldValue.delete(),
      // also clear legacy pointer to avoid stale reads elsewhere
      'config.targetDayKey': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Optional extra config keys (written under config.<key>)
    if (configPatch != null) {
      for (final e in configPatch.entries) {
        final k = e.key.toString().trim();
        if (k.isEmpty) continue;
        update['config.$k'] = e.value;
      }
    }

    await ref.update(update);
  }

  /// Removes the active week plan pointer (keeps days as-is).
  Future<void> removeWeekPlan({
    required String uid,
    required String weekId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);

    await ref.set({
      'weekId': weekId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await ref.update({
      'config.sourceWeekPlanId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Applies a DAY plan to one target day in the week.
  /// Does NOT automatically clear other days unless forceClearWeek = true.
  ///
  /// ✅ IMPORTANT: Firestore does NOT allow FieldValue.delete() inside nested maps.
  /// So we patch config via dotted paths.
  Future<void> applyDayPlan({
    required String uid,
    required String weekId,
    required String dayKey,
    required Map<String, dynamic> daySlots,
    required String sourceDayPlanId,
    bool forceClearWeek = false,
    Map<String, dynamic>? configPatch,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);

    await ref.set({
      'weekId': weekId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (forceClearWeek) {
      await clearWeekDays(uid: uid, weekId: weekId);
    }

    final update = <String, dynamic>{
      'days.$dayKey': daySlots,
      'config.mode': 'day',
      'config.activeMode': 'day',
      'config.daysToPlan': 1,
      'config.targetDayKey': dayKey,
      // day mode clears week-plan pointer
      'config.sourceWeekPlanId': FieldValue.delete(),
      // daySources map (dayKey -> savedPlanId)
      'config.daySources.$dayKey': sourceDayPlanId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (configPatch != null) {
      for (final e in configPatch.entries) {
        final k = e.key.toString().trim();
        if (k.isEmpty) continue;
        update['config.$k'] = e.value;
      }
    }

    await ref.update(update);
  }

  Future<void> removeDayPlan({
    required String uid,
    required String weekId,
    required String dayKey,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);

    await ref.set({
      'weekId': weekId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await ref.update({
      'days.$dayKey': <String, dynamic>{},
      'config.daySources.$dayKey': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeAllDayPlans({
    required String uid,
    required String weekId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    final snap = await ref.get();
    final data = snap.data();
    if (data == null) return;

    final dayKeys = MealPlanKeys.weekDayKeys(weekId);

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      // clear all daySources
      'config.daySources': FieldValue.delete(),
      // if there is no week plan either, mode becomes empty-ish
      'config.mode': 'empty',
    };

    for (final k in dayKeys) {
      updates['days.$k'] = <String, dynamic>{};
    }

    await ref.set({
      'weekId': weekId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await ref.update(updates);
  }

  // -------------------------------------------------------
  // ✅ Hub "Remove plan" behaviour (THE FIX)
  // -------------------------------------------------------

  /// Clears ALL active plan state:
  /// - wipes all week days
  /// - removes any week/day pointers
  /// - resets config to empty
  ///
  /// This prevents the hub showing 7 "Day plan" cards after "remove plan".
  Future<void> clearActivePlan({
    required String uid,
    required String weekId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);

    // Ensure doc exists so update() is always safe.
    await ensureWeekExists(uid: uid, weekId: weekId);

    final dayKeys = MealPlanKeys.weekDayKeys(weekId);

    final updates = <String, dynamic>{
      // clear all day maps
      for (final dk in dayKeys) 'days.$dk': <String, dynamic>{},

      // reset config to "no plan"
      'config.mode': 'empty',
      'config.activeMode': 'week',
      'config.daysToPlan': 7,

      // remove pointers (dotted paths = safe for FieldValue.delete)
      'config.sourceWeekPlanId': FieldValue.delete(),
      'config.sourcePlanId': FieldValue.delete(), // legacy saved-plan pointer
      'config.targetDayKey': FieldValue.delete(),
      'config.daySources': FieldValue.delete(),

      'updatedAt': FieldValue.serverTimestamp(),
    };

    await ref.update(updates);
  }

  // -------------------------------------------------------
  // Day writes (controller save path)
  // -------------------------------------------------------

  Future<void> upsertDayIntoWeek({
    required String uid,
    required String weekId,
    required String dayKey,
    required Map<String, dynamic> daySlots,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);

    await ref.set({
      'weekId': weekId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await ref.update({
      'days.$dayKey': daySlots,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Backwards compatible name (controller uses this).
  Future<void> saveDay({
    required String uid,
    required String weekId,
    required String dayKey,
    required Map<String, dynamic> daySlots,
  }) async {
    await upsertDayIntoWeek(
      uid: uid,
      weekId: weekId,
      dayKey: dayKey,
      daySlots: daySlots,
    );
  }

  // -------------------------------------------------------
  // Controller compatibility: overrideWeekPlan + deleteWeek
  // -------------------------------------------------------

  /// Controller calls overrideWeekPlan for activation flows.
  /// This replaces the full days map + config (no FieldValue.delete inside config map).
  Future<void> overrideWeekPlan({
    required String uid,
    required String weekId,
    required Map<String, Map<String, dynamic>> newDays,
    required Map<String, dynamic> config,
    String? sourcePlanId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);

    await ref.set({
      'weekId': weekId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final cfg = <String, dynamic>{
      ...config,
      // normalize into fields the hub/builder also understand
      if (config.containsKey('activeMode') == false && config.containsKey('mode') == false)
        'activeMode': 'week',
      if (config.containsKey('daysToPlan') == false) 'daysToPlan': 7,
      // legacy + new pointers
      if (sourcePlanId != null && sourcePlanId.trim().isNotEmpty) 'sourcePlanId': sourcePlanId.trim(),
    };

    // NOTE: cfg should not contain FieldValue.delete nested values.
    // If you need deletes, do dotted-path updates instead.
    await ref.update({
      'days': newDays,
      'config': cfg,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteWeek({
    required String uid,
    required String weekId,
  }) async {
    await weekDoc(uid: uid, weekId: weekId).delete();
  }

  // -------------------------------------------------------
  // Clear helpers
  // -------------------------------------------------------

  Future<void> clearWeekDays({
    required String uid,
    required String weekId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    final dayKeys = MealPlanKeys.weekDayKeys(weekId);

    await ref.set({
      'weekId': weekId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final updates = <String, dynamic>{
      for (final dk in dayKeys) 'days.$dk': <String, dynamic>{},
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await ref.update(updates);
  }

  // -------------------------------------------------------
  // Read helpers (Hub uses these)
  // -------------------------------------------------------

  static Map<String, dynamic> _readConfig(Map<String, dynamic>? weekData) {
    final cfg = weekData?['config'];
    if (cfg is Map) return Map<String, dynamic>.from(cfg);
    return <String, dynamic>{};
  }

  static String readMode(Map<String, dynamic>? weekData) {
    final cfg = _readConfig(weekData);
    final mode = (cfg['mode'] ?? '').toString().trim().toLowerCase();
    if (mode.isNotEmpty) return mode;
    // fallback to legacy
    final activeMode = (cfg['activeMode'] ?? '').toString().trim().toLowerCase();
    if (activeMode.isNotEmpty) return activeMode;
    return 'empty';
  }

  static String? readSourceWeekPlanId(Map<String, dynamic>? weekData) {
    final cfg = _readConfig(weekData);
    final id = (cfg['sourceWeekPlanId'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  static Map<String, String> readDaySources(Map<String, dynamic>? weekData) {
    final cfg = _readConfig(weekData);
    final raw = cfg['daySources'];
    if (raw is! Map) return {};

    final out = <String, String>{};
    for (final e in raw.entries) {
      final k = e.key.toString().trim();
      final v = (e.value ?? '').toString().trim();
      if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
    }
    return out;
  }

  // -------------------------------------------------------
  // Static helper used by controller (must exist)
  // -------------------------------------------------------

  static Map<String, dynamic>? dayMapFromWeek(
    Map<String, dynamic> weekData,
    String dayKey,
  ) {
    final days = weekData['days'];
    if (days is! Map) return null;
    final d = days[dayKey];
    if (d is! Map) return null;
    return Map<String, dynamic>.from(d);
  }

  // -------------------------------------------------------
  // Optional: meaningful content detection (prevents ghost plans)
  // -------------------------------------------------------

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static bool _validRecipeId(dynamic v) {
    final n = _asInt(v);
    return (n ?? 0) > 0;
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static bool _isClearType(String t) => t == 'clear' || t == 'cleared';

  static bool _entryHasRealContent(
    Map<String, dynamic> entry, {
    required Map<String, dynamic> weekData,
    required String dayKey,
    required String slotKey,
    Set<String>? visiting,
  }) {
    visiting ??= <String>{};
    final visitKey = '$dayKey|$slotKey';
    if (visiting.contains(visitKey)) return false; // cycle guard
    visiting.add(visitKey);

    final type = (entry['type'] ?? entry['kind'] ?? '').toString().trim().toLowerCase();

    if (_isClearType(type)) return false;

    if (type == 'note') {
      final text = (entry['text'] ?? '').toString().trim();
      return text.isNotEmpty;
    }

    if (type == 'recipe') {
      return _validRecipeId(entry['recipeId']) || _validRecipeId(entry['id']);
    }

    if (type == 'reuse') {
      final fromDayKey = (entry['fromDayKey'] ?? '').toString().trim();
      final fromSlot = (entry['fromSlot'] ?? '').toString().trim();
      if (fromDayKey.isEmpty || fromSlot.isEmpty) return false;

      final fromDay = dayMapFromWeek(weekData, fromDayKey);
      if (fromDay == null) return false;

      dynamic raw = fromDay[fromSlot];
      if (raw == null && fromSlot == 'snack1') raw = fromDay['snack_1'];
      if (raw == null && fromSlot == 'snack2') raw = fromDay['snack_2'];

      final fromEntry = _asMap(raw);
      if (fromEntry == null) return false;

      return _entryHasRealContent(
        fromEntry,
        weekData: weekData,
        dayKey: fromDayKey,
        slotKey: fromSlot,
        visiting: visiting,
      );
    }

    if (_validRecipeId(entry['recipeId']) || _validRecipeId(entry['id'])) return true;
    final text = (entry['text'] ?? entry['note'] ?? '').toString().trim();
    return text.isNotEmpty;
  }

  static bool hasAnyPlannedEntries(Map<String, dynamic>? weekData) {
    if (weekData == null) return false;

    final days = weekData['days'];
    if (days is! Map) return false;

    for (final dayEntry in days.entries) {
      final dayKey = dayEntry.key.toString();
      final dayMap = _asMap(dayEntry.value);
      if (dayMap == null || dayMap.isEmpty) continue;

      for (final slotEntry in dayMap.entries) {
        final slotKey = slotEntry.key.toString();
        final slotMap = _asMap(slotEntry.value);
        if (slotMap == null) continue;

        if (_entryHasRealContent(
          slotMap,
          weekData: weekData,
          dayKey: dayKey,
          slotKey: slotKey,
        )) {
          return true;
        }
      }
    }

    return false;
  }
}

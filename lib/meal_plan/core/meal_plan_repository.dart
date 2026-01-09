// lib/meal_plan/core/meal_plan_repository.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'meal_plan_keys.dart';

// ✅ DEFINED HERE to prevent circular imports with Manager
class DayWriteTarget {
  final String weekId;
  final String dayKey;
  const DayWriteTarget({required this.weekId, required this.dayKey});
}

class MealPlanRepository {
  final FirebaseFirestore _firestore;
  MealPlanRepository(this._firestore);

  // -------------------------------------------------------
  // Week / Saved Plans / Settings Refs (LEGACY)
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

  CollectionReference<Map<String, dynamic>> savedPlansCol({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('savedMealPlans');
  }

  DocumentReference<Map<String, dynamic>> savedPlanDoc({
    required String uid,
    required String planId,
  }) {
    return savedPlansCol(uid: uid).doc(planId);
  }

  /// ✅ This is what MealPlanScreen currently listens to for activeProgramId
  DocumentReference<Map<String, dynamic>> settingsDoc({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('mealPlan').doc('settings');
  }

  // -------------------------------------------------------
  // ✅ Program Refs (NEW)
  // -------------------------------------------------------

  /// ⚠️ Legacy “state” doc you previously used.
  /// Keep it for backwards compatibility, but don’t rely on it only.
  DocumentReference<Map<String, dynamic>> programStateDoc({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('mealPlan').doc('state');
  }

  CollectionReference<Map<String, dynamic>> programsCol({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('mealPrograms');
  }

  DocumentReference<Map<String, dynamic>> programDoc({
    required String uid,
    required String programId,
  }) {
    return programsCol(uid: uid).doc(programId);
  }

  /// ✅ Correct program-days location for MealPlanScreen:
  /// users/{uid}/mealPrograms/{programId}/mealProgramDays/{dateKey}
  CollectionReference<Map<String, dynamic>> programDaysColForProgram({
    required String uid,
    required String programId,
  }) {
    return programsCol(uid: uid).doc(programId).collection('mealProgramDays');
  }

  DocumentReference<Map<String, dynamic>> programDayDocForProgram({
    required String uid,
    required String programId,
    required String dateKey,
  }) {
    return programDaysColForProgram(uid: uid, programId: programId).doc(dateKey);
  }

  /// ✅ COMPAT: older code expects `programDayDoc(...)`
  /// (builder service currently calls this)
  DocumentReference<Map<String, dynamic>> programDayDoc({
    required String uid,
    required String programId,
    required String dateKey,
  }) {
    return programDayDocForProgram(uid: uid, programId: programId, dateKey: dateKey);
  }

  /// ⚠️ Legacy flat location you previously used:
  /// users/{uid}/mealProgramDays/{dateKey}
  /// Kept so older code won’t break.
  CollectionReference<Map<String, dynamic>> programDaysColLegacy({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('mealProgramDays');
  }

  DocumentReference<Map<String, dynamic>> programDayDocLegacy({
    required String uid,
    required String dateKey,
  }) {
    return programDaysColLegacy(uid: uid).doc(dateKey);
  }

  // -------------------------------------------------------
  // ✅ Ad-hoc One-off Day Refs (NEW)
  // -------------------------------------------------------
  /// ✅ Standalone one-off days that should NOT affect the recurring programme.
  /// users/{uid}/mealAdhocDays/{dateKey}
  CollectionReference<Map<String, dynamic>> adhocDaysCol({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('mealAdhocDays');
  }

  DocumentReference<Map<String, dynamic>> adhocDayDoc({
    required String uid,
    required String dateKey,
  }) {
    return adhocDaysCol(uid: uid).doc(dateKey);
  }

  // -------------------------------------------------------
  // Core Read/Write (LEGACY WEEK)
  // -------------------------------------------------------
  Stream<Map<String, dynamic>?> watchWeek({
    required String uid,
    required String weekId,
  }) {
    return weekDoc(uid: uid, weekId: weekId).snapshots().map((snap) => snap.data());
  }

  /// DUMB & SIMPLE: Just create an empty shell if it doesn't exist.
  Future<void> ensureWeekExists({
    required String uid,
    required String weekId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    final snap = await ref.get();

    if (!snap.exists) {
      final dayKeys = MealPlanKeys.weekDayKeys(weekId);
      final baseDays = {for (final dk in dayKeys) dk: <String, dynamic>{}};

      await ref.set({
        'weekId': weekId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'days': baseDays,
        'config': {'mode': 'empty', 'daysToPlan': 7},
      });
    }
  }

  /// Force Write a Week (Used by Manager)
  Future<void> forceWriteWeek({
    required String uid,
    required String weekId,
    required Map<String, dynamic> daysData,
    required Map<String, dynamic> configData,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    await ref.set({
      'weekId': weekId,
      'days': daysData,
      'config': configData,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // -------------------------------------------------------
  // ✅ RESTORED METHODS (Required by Controller/UI) (LEGACY)
  // -------------------------------------------------------
  Future<void> deleteWeek({required String uid, required String weekId}) async {
    await weekDoc(uid: uid, weekId: weekId).delete();
  }

  Future<void> saveDay({
    required String uid,
    required String weekId,
    required String dayKey,
    required Map<String, dynamic> daySlots,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    await ensureWeekExists(uid: uid, weekId: weekId);
    await ref.update({
      'days.$dayKey': daySlots,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> overrideWeekPlan({
    required String uid,
    required String weekId,
    required Map<String, Map<String, dynamic>> newDays,
    required Map<String, dynamic> config,
    String? sourcePlanId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    await ensureWeekExists(uid: uid, weekId: weekId);

    final cfg = <String, dynamic>{
      ...config,
      if (sourcePlanId != null) 'sourcePlanId': sourcePlanId,
    };

    await ref.update({
      'days': newDays,
      'config': cfg,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // -------------------------------------------------------
  // Saved Plans / Recurring Helpers (LEGACY)
  // -------------------------------------------------------
  Future<void> deleteSavedPlan({required String uid, required String planId}) async {
    await savedPlanDoc(uid: uid, planId: planId).delete();
  }

  Future<Map<String, dynamic>?> getSavedPlan({
    required String uid,
    required String planId,
  }) async {
    final snap = await savedPlanDoc(uid: uid, planId: planId).get();
    return snap.data();
  }

  Future<List<Map<String, dynamic>>> listRecurringDayPlans({required String uid}) async {
    final qs = await savedPlansCol(uid: uid)
        .where('recurringEnabled', isEqualTo: true)
        .where('planType', isEqualTo: 'day')
        .get();
    return qs.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  Future<void> setSavedPlanRecurring({
    required String uid,
    required String planId,
    required bool enabled,
    String? planType,
    String? weekAnchorDateKey,
    List<int>? weekdays,
  }) async {
    final ref = savedPlanDoc(uid: uid, planId: planId);
    final update = <String, dynamic>{
      'recurringEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Clean inputs
    if (planType != null) update['planType'] = planType;
    if (weekAnchorDateKey != null) {
      update['recurringWeekAnchorDate'] = weekAnchorDateKey;
    }

    if (!enabled) {
      update['recurringWeekdays'] = FieldValue.delete();
    } else if (weekdays != null) {
      update['recurringWeekdays'] = weekdays;
    }

    await ref.set(update, SetOptions(merge: true));
  }

  Future<void> setActiveRecurringWeekPlanId({required String uid, String? planId}) async {
    final ref = settingsDoc(uid: uid);
    await ref.set(
      {'activeRecurringWeekPlanId': planId ?? FieldValue.delete()},
      SetOptions(merge: true),
    );
  }

  Future<String?> getActiveRecurringWeekPlanId({required String uid}) async {
    final snap = await settingsDoc(uid: uid).get();
    return snap.data()?['activeRecurringWeekPlanId']?.toString();
  }

  // -------------------------------------------------------
  // ✅ Program Read/Write (NEW)
  // -------------------------------------------------------

  /// ✅ Watch active program id from settings (MealPlanScreen source of truth)
  /// Falls back to legacy state doc if needed.
  Stream<String?> watchActiveProgramId({required String uid}) {
    return settingsDoc(uid: uid).snapshots().asyncMap((s) async {
      final v = s.data()?['activeProgramId']?.toString();
      if (v != null && v.trim().isNotEmpty) return v.trim();

      // fallback to legacy state doc
      final fallback = await programStateDoc(uid: uid).get();
      final fb = fallback.data()?['activeProgramId']?.toString();
      return (fb == null || fb.trim().isEmpty) ? null : fb.trim();
    });
  }

  Future<String?> getActiveProgramId({required String uid}) async {
    final snap = await settingsDoc(uid: uid).get();
    final v = snap.data()?['activeProgramId']?.toString();
    if (v != null && v.trim().isNotEmpty) return v.trim();

    final fallback = await programStateDoc(uid: uid).get();
    final fb = fallback.data()?['activeProgramId']?.toString();
    return (fb == null || fb.trim().isEmpty) ? null : fb.trim();
  }

  /// ✅ IMPORTANT: write to BOTH settings + legacy state so everything stays in sync
  Future<void> setActiveProgramId({required String uid, String? programId}) async {
    final payload = <String, dynamic>{
      if (programId == null) 'activeProgramId': FieldValue.delete() else 'activeProgramId': programId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await settingsDoc(uid: uid).set(payload, SetOptions(merge: true));
    await programStateDoc(uid: uid).set(payload, SetOptions(merge: true));
  }

  Stream<Map<String, dynamic>?> watchProgram({
    required String uid,
    required String programId,
  }) {
    return programDoc(uid: uid, programId: programId).snapshots().map((s) => s.data());
  }

  Future<Map<String, dynamic>?> getProgram({
    required String uid,
    required String programId,
  }) async {
    final snap = await programDoc(uid: uid, programId: programId).get();
    return snap.data();
  }

  /// Create a program doc and return programId.
  Future<String> createProgram({
    required String uid,
    required String name,
    required String startDateKey,
    required String endDateKey,
    required int weeks,
    required List<int> weekdays, // Mon=1..Sun=7
    required List<String> scheduledDates, // YYYY-MM-DD
  }) async {
    final ref = programsCol(uid: uid).doc();
    await ref.set({
      'name': name.trim().isEmpty ? 'My Plan' : name.trim(),
      // keep your existing field names (fine)
      'startDate': startDateKey,
      'endDate': endDateKey,
      'weeks': weeks,
      'weekdays': weekdays,
      'scheduledDates': scheduledDates,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateProgram({
    required String uid,
    required String programId,
    Map<String, dynamic>? patch,
  }) async {
    if (patch == null || patch.isEmpty) return;
    await programDoc(uid: uid, programId: programId).set(
      {
        ...patch,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteProgram({required String uid, required String programId}) async {
    await programDoc(uid: uid, programId: programId).delete();
  }

  /// ✅ New: watch a day within a specific program (correct path)
  Stream<Map<String, dynamic>?> watchProgramDayInProgram({
    required String uid,
    required String programId,
    required String dateKey,
  }) {
    return programDayDocForProgram(uid: uid, programId: programId, dateKey: dateKey)
        .snapshots()
        .map((s) => s.data());
  }

  /// ✅ Legacy: watch from flat collection (kept)
  Stream<Map<String, dynamic>?> watchProgramDay({
    required String uid,
    required String dateKey,
  }) {
    return programDayDocLegacy(uid: uid, dateKey: dateKey).snapshots().map((s) => s.data());
  }

  Future<Map<String, dynamic>?> getProgramDayInProgram({
    required String uid,
    required String programId,
    required String dateKey,
  }) async {
    final snap = await programDayDocForProgram(uid: uid, programId: programId, dateKey: dateKey).get();
    return snap.data();
  }

  Future<Map<String, dynamic>?> getProgramDay({
    required String uid,
    required String dateKey,
  }) async {
    final snap = await programDayDocLegacy(uid: uid, dateKey: dateKey).get();
    return snap.data();
  }

  /// ✅ CRITICAL FIX: write program day into the nested collection MealPlanScreen reads
  /// Also optionally mirror into legacy flat collection so nothing else breaks.
  Future<void> upsertProgramDay({
    required String uid,
    required String programId,
    required String dateKey,
    required Map<String, dynamic> daySlots,
  }) async {
    final payload = <String, dynamic>{
      'programId': programId,
      // MealPlanScreen doesn’t care about this name, but your UI helpers do:
      'dayKey': dateKey,
      'dateKey': dateKey,
      'slots': daySlots,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    // ✅ Correct location
    await programDayDocForProgram(uid: uid, programId: programId, dateKey: dateKey).set(
      payload,
      SetOptions(merge: true),
    );

    // ✅ Legacy mirror (safe)
    await programDayDocLegacy(uid: uid, dateKey: dateKey).set(
      payload,
      SetOptions(merge: true),
    );
  }

  Future<void> deleteProgramDayInProgram({
    required String uid,
    required String programId,
    required String dateKey,
  }) async {
    await programDayDocForProgram(uid: uid, programId: programId, dateKey: dateKey).delete();
  }

  Future<void> deleteProgramDay({required String uid, required String dateKey}) async {
    await programDayDocLegacy(uid: uid, dateKey: dateKey).delete();
  }

  // -------------------------------------------------------
  // ✅ Ad-hoc One-off Day Read/Write (NEW)
  // -------------------------------------------------------

  Stream<Map<String, dynamic>?> watchAdhocDay({
    required String uid,
    required String dateKey,
  }) {
    return adhocDayDoc(uid: uid, dateKey: dateKey).snapshots().map((s) => s.data());
  }

  Future<Map<String, dynamic>?> getAdhocDay({
    required String uid,
    required String dateKey,
  }) async {
    final snap = await adhocDayDoc(uid: uid, dateKey: dateKey).get();
    return snap.data();
  }

  /// ✅ Write a one-off day that does NOT affect any program.
  /// Structure mirrors program day docs enough for UI reuse: { dateKey, slots, ... }
  Future<void> upsertAdhocDay({
    required String uid,
    required String dateKey,
    required Map<String, dynamic> daySlots,
    String? title, // optional label if you want it later
  }) async {
    final payload = <String, dynamic>{
      'type': 'adhoc',
      'dayKey': dateKey,
      'dateKey': dateKey,
      if (title != null) 'title': title,
      'slots': daySlots,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    await adhocDayDoc(uid: uid, dateKey: dateKey).set(
      payload,
      SetOptions(merge: true),
    );
  }

  Future<void> deleteAdhocDay({
    required String uid,
    required String dateKey,
  }) async {
    await adhocDayDoc(uid: uid, dateKey: dateKey).delete();
  }

  /// ✅ Convenience: a single stream that yields the "effective" day:
  /// - if ad-hoc exists => return it (with meta)
  /// - else if program day exists => return it (with meta)
  /// - else => null
  ///
  /// This keeps MealPlanScreen simple without RxDart.
  Stream<Map<String, dynamic>?> watchEffectiveDay({
    required String uid,
    required String dateKey,
    required String? programId,
  }) {
    final controller = StreamController<Map<String, dynamic>?>();

    Map<String, dynamic>? adhoc;
    Map<String, dynamic>? program;

    void emit() {
      if (adhoc != null) {
        controller.add({
          ...adhoc!,
          '_effectiveSource': 'adhoc',
        });
        return;
      }
      if (program != null) {
        controller.add({
          ...program!,
          '_effectiveSource': 'program',
        });
        return;
      }
      controller.add(null);
    }

    late final StreamSubscription subA;
    StreamSubscription? subP;

    subA = watchAdhocDay(uid: uid, dateKey: dateKey).listen((a) {
      adhoc = a;
      emit();
    });

    if (programId != null && programId.trim().isNotEmpty) {
      subP = watchProgramDayInProgram(uid: uid, programId: programId, dateKey: dateKey).listen((p) {
        program = p;
        emit();
      });
    } else {
      // no program
      program = null;
      emit();
    }

    controller.onCancel = () async {
      await subA.cancel();
      await subP?.cancel();
    };

    return controller.stream;
  }

  // -------------------------------------------------------
  // Static Helpers (LEGACY)
  // -------------------------------------------------------
  static bool hasAnyPlannedEntries(Map<String, dynamic> weekData) {
    final days = weekData['days'];
    if (days is! Map) return false;

    for (final dayVal in days.values) {
      if (dayVal is Map) {
        for (final slotVal in dayVal.values) {
          if (slotVal is Map) {
            final type = slotVal['type'] ?? slotVal['kind'];
            if (type == 'recipe' || type == 'note') return true;
          }
        }
      }
    }
    return false;
  }

  static Map<String, String> readDaySources(Map<String, dynamic>? weekData) {
    final cfg = weekData?['config'];
    if (cfg is Map && cfg['daySources'] is Map) {
      return Map<String, String>.from(cfg['daySources']);
    }
    return {};
  }

  static Map<String, dynamic>? dayMapFromWeek(Map<String, dynamic> weekData, String dayKey) {
    final days = weekData['days'];
    if (days is! Map) return null;
    final v = days[dayKey];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  // Legacy support wrapper (LEGACY)
  Future<void> applyDayPlanToManyDays({
    required String uid,
    required List<DayWriteTarget> targets,
    required Map<String, dynamic> daySlots,
    required String sourcePlanId,
    required String title,
    bool overwrite = true,
  }) async {
    if (targets.isEmpty) return;
    final batch = _firestore.batch();

    for (final t in targets) {
      final ref = weekDoc(uid: uid, weekId: t.weekId);
      final dayKeys = MealPlanKeys.weekDayKeys(t.weekId);
      final baseDays = {for (final dk in dayKeys) dk: <String, dynamic>{}};

      batch.set(
        ref,
        {
          'weekId': t.weekId,
          'days': baseDays,
          'config': {'mode': 'empty', 'daysToPlan': 7}
        },
        SetOptions(merge: true),
      );

      batch.update(ref, {
        'days.${t.dayKey}': daySlots,
        'config.daySources.${t.dayKey}': sourcePlanId,
        'config.dayPlanTitles.${t.dayKey}': title,
      });
    }
    await batch.commit();
  }
}

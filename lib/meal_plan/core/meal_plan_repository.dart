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
  // ✅ Legacy write switches (turn off dual-write)
  // -------------------------------------------------------
  static const bool kWriteLegacyProgramStateDoc = false; // mealPlan/state
  static const bool kWriteLegacyFlatProgramDays = false; // users/{uid}/mealProgramDays/{dateKey}

  // -------------------------------------------------------
  // ✅ Day Docs (NEW - optional helper for controller migration)
  // -------------------------------------------------------
  CollectionReference<Map<String, dynamic>> daysCol({required String uid}) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('mealPlan')
        .doc('days')
        .collection('items');
  }

  DocumentReference<Map<String, dynamic>> dayDoc({
    required String uid,
    required String dayKey,
  }) {
    return daysCol(uid: uid).doc(dayKey);
  }

  /// Watches all day docs and returns a map keyed by dayKey.
  /// Each doc is assumed to have a 'dayKey' field OR doc id is the dayKey.
  Stream<Map<String, dynamic>> watchDays({required String uid}) {
    return daysCol(uid: uid).snapshots().map((snap) {
      final out = <String, dynamic>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final dk = (data['dayKey'] is String &&
                (data['dayKey'] as String).trim().isNotEmpty)
            ? (data['dayKey'] as String).trim()
            : doc.id;
        out[dk] = data;
      }
      return out;
    });
  }

  Future<Map<String, dynamic>?> getDay({
    required String uid,
    required String dayKey,
  }) async {
    final snap = await dayDoc(uid: uid, dayKey: dayKey).get();
    return snap.data();
  }

  Future<void> saveDayDoc({
    required String uid,
    required String dayKey,
    required Map<String, dynamic> dayData,
  }) async {
    await dayDoc(uid: uid, dayKey: dayKey).set(
      {
        ...dayData,
        'dayKey': dayKey,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteDayDoc({
    required String uid,
    required String dayKey,
  }) async {
    await dayDoc(uid: uid, dayKey: dayKey).delete();
  }

  // -------------------------------------------------------
  // Settings (SOURCE OF TRUTH)
  // -------------------------------------------------------
  /// ✅ Source of truth for activeProgramId
  /// users/{uid}/mealPlan/settings
  DocumentReference<Map<String, dynamic>> settingsDoc({required String uid}) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('mealPlan')
        .doc('settings');
  }

  // -------------------------------------------------------
  // Program Refs (NEW)
  // -------------------------------------------------------
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
  DocumentReference<Map<String, dynamic>> programDayDoc({
    required String uid,
    required String programId,
    required String dateKey,
  }) {
    return programDayDocForProgram(
      uid: uid,
      programId: programId,
      dateKey: dateKey,
    );
  }

  // -------------------------------------------------------
  // Ad-hoc One-off Day Refs (NEW)
  // -------------------------------------------------------
  /// ✅ Standalone one-off days:
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
  // ✅ Active Program (NEW) – no more relying on legacy state
  // -------------------------------------------------------
  Stream<String?> watchActiveProgramId({required String uid}) {
    return settingsDoc(uid: uid).snapshots().map((s) {
      final v = s.data()?['activeProgramId']?.toString();
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    });
  }

  Future<String?> getActiveProgramId({required String uid}) async {
    final snap = await settingsDoc(uid: uid).get();
    final v = snap.data()?['activeProgramId']?.toString();
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  /// ✅ IMPORTANT: writes to settings only (legacy state is OFF by default)
  Future<void> setActiveProgramId({
    required String uid,
    String? programId,
  }) async {
    final payload = <String, dynamic>{
      if (programId == null)
        'activeProgramId': FieldValue.delete()
      else
        'activeProgramId': programId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await settingsDoc(uid: uid).set(payload, SetOptions(merge: true));

    // Optional legacy mirror (disabled by default)
    if (kWriteLegacyProgramStateDoc) {
      await programStateDoc(uid: uid).set(payload, SetOptions(merge: true));
    }
  }

  Stream<Map<String, dynamic>?> watchProgram({
    required String uid,
    required String programId,
  }) {
    return programDoc(uid: uid, programId: programId)
        .snapshots()
        .map((s) => s.data());
  }

  Future<Map<String, dynamic>?> getProgram({
    required String uid,
    required String programId,
  }) async {
    final snap = await programDoc(uid: uid, programId: programId).get();
    return snap.data();
  }

  /// Create a program doc and return programId.
  ///
  /// ✅ Updated: store SSOT household snapshot (adults/kids) + optional childrenSnapshot
  Future<String> createProgram({
    required String uid,
    required String name,
    required String startDateKey,
    required String endDateKey,
    required int weeks,
    required List<int> weekdays, // Mon=1..Sun=7
    required List<String> scheduledDates, // YYYY-MM-DD

    // ✅ NEW (SSOT snapshot)
    required int adults,
    required int kids,

    // Optional: stash an immutable snapshot of children at creation time
    // (handy for debugging / future “this plan was made for…” UI)
    List<Map<String, dynamic>>? childrenSnapshot,
  }) async {
    final ref = programsCol(uid: uid).doc();

    await ref.set({
      'name': name.trim().isEmpty ? 'My Plan' : name.trim(),
      'startDate': startDateKey,
      'endDate': endDateKey,
      'weeks': weeks,
      'weekdays': weekdays,
      'scheduledDates': scheduledDates,

      // ✅ SSOT snapshot
      'adults': adults,
      'kids': kids,
      if (childrenSnapshot != null) 'childrenSnapshot': childrenSnapshot,

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

  Future<void> deleteProgram({
    required String uid,
    required String programId,
  }) async {
    await programDoc(uid: uid, programId: programId).delete();
  }

  // -------------------------------------------------------
  // Program Day Read/Write (NEW)
  // -------------------------------------------------------
  Stream<Map<String, dynamic>?> watchProgramDayInProgram({
    required String uid,
    required String programId,
    required String dateKey,
  }) {
    return programDayDocForProgram(
      uid: uid,
      programId: programId,
      dateKey: dateKey,
    ).snapshots().map((s) => s.data());
  }

  Future<Map<String, dynamic>?> getProgramDayInProgram({
    required String uid,
    required String programId,
    required String dateKey,
  }) async {
    final snap = await programDayDocForProgram(
      uid: uid,
      programId: programId,
      dateKey: dateKey,
    ).get();
    return snap.data();
  }

  /// ✅ Source-of-truth write: nested programme day doc
  /// Legacy flat mirror is OFF by default.
  Future<void> upsertProgramDay({
    required String uid,
    required String programId,
    required String dateKey,
    required Map<String, dynamic> daySlots,
  }) async {
    final payload = <String, dynamic>{
      'programId': programId,
      'dayKey': dateKey,
      'dateKey': dateKey,
      'slots': daySlots,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    // ✅ Correct location
    await programDayDocForProgram(
      uid: uid,
      programId: programId,
      dateKey: dateKey,
    ).set(payload, SetOptions(merge: true));

    // Optional legacy mirror (disabled by default)
    if (kWriteLegacyFlatProgramDays) {
      await programDayDocLegacy(uid: uid, dateKey: dateKey).set(
        payload,
        SetOptions(merge: true),
      );
    }
  }

  Future<void> deleteProgramDayInProgram({
    required String uid,
    required String programId,
    required String dateKey,
  }) async {
    await programDayDocForProgram(
      uid: uid,
      programId: programId,
      dateKey: dateKey,
    ).delete();
  }

  // -------------------------------------------------------
  // Ad-hoc One-off Day Read/Write (NEW)
  // -------------------------------------------------------
  Stream<Map<String, dynamic>?> watchAdhocDay({
    required String uid,
    required String dateKey,
  }) {
    return adhocDayDoc(uid: uid, dateKey: dateKey)
        .snapshots()
        .map((s) => s.data());
  }

  Future<Map<String, dynamic>?> getAdhocDay({
    required String uid,
    required String dateKey,
  }) async {
    final snap = await adhocDayDoc(uid: uid, dateKey: dateKey).get();
    return snap.data();
  }

  Future<void> upsertAdhocDay({
    required String uid,
    required String dateKey,
    required Map<String, dynamic> daySlots,
    String? title,
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

  /// ✅ Convenience: yields the "effective" day:
  /// - ad-hoc exists => return it
  /// - else program day exists => return it
  /// - else null
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
        controller.add({...adhoc!, '_effectiveSource': 'adhoc'});
        return;
      }
      if (program != null) {
        controller.add({...program!, '_effectiveSource': 'program'});
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
      subP = watchProgramDayInProgram(
        uid: uid,
        programId: programId,
        dateKey: dateKey,
      ).listen((p) {
        program = p;
        emit();
      });
    } else {
      program = null;
      emit();
    }

    controller.onCancel = () async {
      await subA.cancel();
      await subP?.cancel();
      await controller.close();
    };

    return controller.stream;
  }

  // =======================================================
  // LEGACY SECTION (kept ONLY so other files still compile)
  // Next step: remove callers, then delete this block.
  // =======================================================

  // -------------------------------------------------------
  // Week / Saved Plans / Settings Refs (LEGACY)
  // -------------------------------------------------------
  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
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

  @Deprecated('Legacy: savedMealPlans are no longer used. Remove callers then delete.')
  CollectionReference<Map<String, dynamic>> savedPlansCol({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('savedMealPlans');
  }

  @Deprecated('Legacy: savedMealPlans are no longer used. Remove callers then delete.')
  DocumentReference<Map<String, dynamic>> savedPlanDoc({
    required String uid,
    required String planId,
  }) {
    return savedPlansCol(uid: uid).doc(planId);
  }

  /// ⚠️ Legacy “state” doc you previously used:
  /// users/{uid}/mealPlan/state
  /// Kept for compatibility only (writes disabled by default).
  @Deprecated('Legacy: do not rely on mealPlan/state. Use mealPlan/settings only.')
  DocumentReference<Map<String, dynamic>> programStateDoc({required String uid}) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('mealPlan')
        .doc('state');
  }

  /// ⚠️ Legacy flat location:
  /// users/{uid}/mealProgramDays/{dateKey}
  /// Kept so older code won’t break (writes disabled by default).
  @Deprecated('Legacy: programme days are nested under mealPrograms/{id}/mealProgramDays.')
  CollectionReference<Map<String, dynamic>> programDaysColLegacy({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('mealProgramDays');
  }

  @Deprecated('Legacy: programme days are nested under mealPrograms/{id}/mealProgramDays.')
  DocumentReference<Map<String, dynamic>> programDayDocLegacy({
    required String uid,
    required String dateKey,
  }) {
    return programDaysColLegacy(uid: uid).doc(dateKey);
  }

  @Deprecated('Legacy: do not watch flat programme days; use watchProgramDayInProgram.')
  Stream<Map<String, dynamic>?> watchProgramDay({
    required String uid,
    required String dateKey,
  }) {
    return programDayDocLegacy(uid: uid, dateKey: dateKey)
        .snapshots()
        .map((s) => s.data());
  }

  @Deprecated('Legacy: do not read flat programme days; use getProgramDayInProgram.')
  Future<Map<String, dynamic>?> getProgramDay({
    required String uid,
    required String dateKey,
  }) async {
    final snap = await programDayDocLegacy(uid: uid, dateKey: dateKey).get();
    return snap.data();
  }

  @Deprecated('Legacy: delete the nested program day instead.')
  Future<void> deleteProgramDay({required String uid, required String dateKey}) async {
    await programDayDocLegacy(uid: uid, dateKey: dateKey).delete();
  }

  // -------------------------------------------------------
  // Core Read/Write (LEGACY WEEK)
  // -------------------------------------------------------
  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
  Stream<Map<String, dynamic>?> watchWeek({
    required String uid,
    required String weekId,
  }) {
    return weekDoc(uid: uid, weekId: weekId).snapshots().map((snap) => snap.data());
  }

  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
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

  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
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

  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
  Future<void> deleteWeek({required String uid, required String weekId}) async {
    await weekDoc(uid: uid, weekId: weekId).delete();
  }

  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
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

  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
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
  @Deprecated('Legacy: savedMealPlans are no longer used. Remove callers then delete.')
  Future<void> deleteSavedPlan({required String uid, required String planId}) async {
    await savedPlanDoc(uid: uid, planId: planId).delete();
  }

  @Deprecated('Legacy: savedMealPlans are no longer used. Remove callers then delete.')
  Future<Map<String, dynamic>?> getSavedPlan({
    required String uid,
    required String planId,
  }) async {
    final snap = await savedPlanDoc(uid: uid, planId: planId).get();
    return snap.data();
  }

  @Deprecated('Legacy: recurring saved plans are no longer used. Remove callers then delete.')
  Future<List<Map<String, dynamic>>> listRecurringDayPlans({required String uid}) async {
    final qs = await savedPlansCol(uid: uid)
        .where('recurringEnabled', isEqualTo: true)
        .where('planType', isEqualTo: 'day')
        .get();
    return qs.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  @Deprecated('Legacy: recurring saved plans are no longer used. Remove callers then delete.')
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

    if (planType != null) update['planType'] = planType;
    if (weekAnchorDateKey != null) update['recurringWeekAnchorDate'] = weekAnchorDateKey;

    if (!enabled) {
      update['recurringWeekdays'] = FieldValue.delete();
    } else if (weekdays != null) {
      update['recurringWeekdays'] = weekdays;
    }

    await ref.set(update, SetOptions(merge: true));
  }

  @Deprecated('Legacy: recurring week plan id no longer used. Remove callers then delete.')
  Future<void> setActiveRecurringWeekPlanId({required String uid, String? planId}) async {
    final ref = settingsDoc(uid: uid);
    await ref.set(
      {'activeRecurringWeekPlanId': planId ?? FieldValue.delete()},
      SetOptions(merge: true),
    );
  }

  @Deprecated('Legacy: recurring week plan id no longer used. Remove callers then delete.')
  Future<String?> getActiveRecurringWeekPlanId({required String uid}) async {
    final snap = await settingsDoc(uid: uid).get();
    return snap.data()?['activeRecurringWeekPlanId']?.toString();
  }

  // -------------------------------------------------------
  // Static Helpers (LEGACY WEEK)
  // -------------------------------------------------------
  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
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

  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
  static Map<String, String> readDaySources(Map<String, dynamic>? weekData) {
    final cfg = weekData?['config'];
    if (cfg is Map && cfg['daySources'] is Map) {
      return Map<String, String>.from(cfg['daySources']);
    }
    return {};
  }

  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
  static Map<String, dynamic>? dayMapFromWeek(
    Map<String, dynamic> weekData,
    String dayKey,
  ) {
    final days = weekData['days'];
    if (days is! Map) return null;
    final v = days[dayKey];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  @Deprecated('Legacy: week docs are no longer used. Remove callers then delete.')
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
          'config': {'mode': 'empty', 'daysToPlan': 7},
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

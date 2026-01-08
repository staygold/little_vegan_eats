// lib/meal_plan/services/meal_plan_manager.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';

class MealPlanManager {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  late final MealPlanRepository _repo;

  MealPlanManager({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance {
    _repo = MealPlanRepository(_firestore);
  }

  String _uid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');
    return uid;
  }

  // -------------------------------------------------------
  // PUBLISH (Timeline Writer)
  // -------------------------------------------------------

  /// Writes a plan into the calendar timeline weeks.
  ///
  /// - Day plan:
  ///   - recurring (activeWeekdays provided): fills matching weekdays forward for [weeksToFill] weeks.
  ///   - non-recurring: writes ONLY the [startDate] day.
  ///
  /// - Week plan:
  ///   - ALWAYS writes 7 consecutive days starting at [startDate].
  ///   - If [weeksToFill] > 1, repeats that 7-day block weekly (i.e. 7 * weeksToFill consecutive days),
  ///     which is how "recurring week plan" fills future weeks.
  ///
  /// ✅ FIX: Week plans now spill across week boundaries properly (e.g. start Thu → continues into next week).
  Future<void> publishPlanToCalendar({
    required String title,
    required DateTime startDate,
    required Map<String, dynamic> planData,
    required bool isWeekPlan,
    String? sourcePlanId,
    List<int>? activeWeekdays,
    int weeksToFill = 52,
  }) async {
    final uid = _uid();

    // Normalize start (date-only)
    final start = DateTime(startDate.year, startDate.month, startDate.day);

    // -------------------------------
    // WEEK PLAN: write consecutive days across week docs
    // -------------------------------
    if (isWeekPlan) {
      // We expect planData keys to be dayKeys (yyyy-mm-dd) for week plans.
      final sourceKeys = planData.keys.map((e) => e.toString()).toList()..sort();

      // Total days = 7 for one-off, or 7*weeksToFill for recurring week plan.
      final totalDays = 7 * (weeksToFill.clamp(1, 52));

      WriteBatch batch = _firestore.batch();
      int opCount = 0;

      for (int i = 0; i < totalDays; i++) {
        final dt = start.add(Duration(days: i));
        final dayKey = MealPlanKeys.dayKey(dt);
        final weekId = MealPlanKeys.weekIdForDate(dt);
        final weekRef = _repo.weekDoc(uid: uid, weekId: weekId);

        // Determine which "day payload" to apply:
        // - The saved week plan contains exactly 7 days keyed by their dayKeys.
        // - For recurring, we repeat that 7-day pattern weekly.
        final patternIndex = i % 7;
        Map<String, dynamic> dayPayload = <String, dynamic>{};

        if (sourceKeys.isNotEmpty && patternIndex < sourceKeys.length) {
          final sourceKey = sourceKeys[patternIndex];
          final raw = planData[sourceKey];

          if (raw is Map) {
            dayPayload = Map<String, dynamic>.from(raw as Map);
          }
        }

        // If something is off and we didn't get a payload, skip writing this day.
        if (dayPayload.isEmpty) continue;

        // Build update using merge so we don't overwrite other days.
        // Also ensure the week meta is detectable by Hub for "week plan" labelling,
        // even when only some days are present in that week.
        final writeData = <String, dynamic>{
          'weekId': weekId,
          'updatedAt': FieldValue.serverTimestamp(),
          'days': {dayKey: dayPayload},
          'config': {
            'mode': 'week',
            'activeMode': 'week',
            'sourceWeekPlanId': sourcePlanId,
            'title': title,
            'daysToPlan': 7,
            'weekPlanStartDayKey': MealPlanKeys.dayKey(start),
            // Also keep per-day links for wiping and hub display consistency
            'daySources': {dayKey: sourcePlanId ?? ''},
            'dayPlanTitles': {dayKey: title},
          },
        };

        batch.set(weekRef, writeData, SetOptions(merge: true));
        opCount++;

        if (opCount >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          opCount = 0;
        }
      }

      if (opCount > 0) await batch.commit();

      // Only mark as active recurring week plan if we actually intend it to recur.
      if (weeksToFill > 1 && sourcePlanId != null) {
        await _repo.setActiveRecurringWeekPlanId(uid: uid, planId: sourcePlanId);
      }

      return;
    }

    // -------------------------------
    // DAY PLAN: recurring or one-off
    // -------------------------------
    WriteBatch batch = _firestore.batch();
    int opCount = 0;

    // Template day payload (saved day plan stores a "template" map)
    Map<String, dynamic> template = <String, dynamic>{};
    if (planData.isNotEmpty) {
      final raw = planData.values.first;
      if (raw is Map) template = Map<String, dynamic>.from(raw as Map);
    }
    if (template.isEmpty) return;

    // Non-recurring day plan: write ONLY startDate day.
    final isRecurringDay = (activeWeekdays != null && activeWeekdays.isNotEmpty);
    if (!isRecurringDay) {
      final dayKey = MealPlanKeys.dayKey(start);
      final weekId = MealPlanKeys.weekIdForDate(start);
      final weekRef = _repo.weekDoc(uid: uid, weekId: weekId);

      final writeData = <String, dynamic>{
        'weekId': weekId,
        'updatedAt': FieldValue.serverTimestamp(),
        'days': {dayKey: template},
        'config': {
          'daySources': {dayKey: sourcePlanId ?? ''},
          'dayPlanTitles': {dayKey: title},
        },
      };

      batch.set(weekRef, writeData, SetOptions(merge: true));
      await batch.commit();
      return;
    }

    // Recurring day plan: fill matching weekdays forward for N weeks
    final weeks = weeksToFill.clamp(1, 52);

    for (int i = 0; i < weeks; i++) {
      final dateInWeek = start.add(Duration(days: i * 7));
      final weekId = MealPlanKeys.weekIdForDate(dateInWeek);
      final weekRef = _repo.weekDoc(uid: uid, weekId: weekId);
      final weekDayKeys = MealPlanKeys.weekDayKeys(weekId);

      final daysPayload = <String, dynamic>{};
      final daySourcesPayload = <String, dynamic>{};
      final dayTitlesPayload = <String, dynamic>{};

      bool weekModified = false;

      for (final dateKey in weekDayKeys) {
        final dt = MealPlanKeys.parseDayKey(dateKey);
        if (dt == null) continue;

        // Skip history
        if (dt.isBefore(start)) continue;

        if (activeWeekdays.contains(dt.weekday)) {
          daysPayload[dateKey] = template;
          daySourcesPayload[dateKey] = sourcePlanId ?? '';
          dayTitlesPayload[dateKey] = title;
          weekModified = true;
        }
      }

      if (!weekModified) continue;

      final writeData = <String, dynamic>{
        'weekId': weekId,
        'updatedAt': FieldValue.serverTimestamp(),
        'days': daysPayload,
        'config': {
          if (daySourcesPayload.isNotEmpty) 'daySources': daySourcesPayload,
          if (dayTitlesPayload.isNotEmpty) 'dayPlanTitles': dayTitlesPayload,
        },
      };

      batch.set(weekRef, writeData, SetOptions(merge: true));
      opCount++;

      if (opCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) await batch.commit();
  }

  // -------------------------------------------------------
  // MANAGE SAVED PLANS
  // -------------------------------------------------------

  Future<void> deleteSavedPlan({required String planId, required Map<String, dynamic> planData}) async {
    final uid = _uid();
    await _repo.deleteSavedPlan(uid: uid, planId: planId);

    final activeId = await _repo.getActiveRecurringWeekPlanId(uid: uid);
    if (activeId == planId) {
      await _repo.setActiveRecurringWeekPlanId(uid: uid, planId: null);
    }
    await _wipeFutureInstances(planId, stopFromDate: DateTime.now());
  }

  Future<void> setSavedPlanRecurring({
    required String planId,
    required String planType,
    required bool enabled,
    List<int>? weekdays,
    String? weekAnchorDateKey,
    DateTime? stopFromDate,
  }) async {
    final uid = _uid();

    // 1. Update Saved Plan Document
    await _repo.setSavedPlanRecurring(
      uid: uid,
      planId: planId,
      enabled: enabled,
      planType: planType,
      weekdays: weekdays,
      weekAnchorDateKey: weekAnchorDateKey,
    );

    // 2. Adjust Calendar
    if (!enabled) {
      // Wipe from the stop date onwards
      await _wipeFutureInstances(planId, stopFromDate: stopFromDate ?? DateTime.now());
      if (planType == 'week') await _repo.setActiveRecurringWeekPlanId(uid: uid, planId: null);
    } else {
      // Re-publish (Enable)
      final plan = await _repo.getSavedPlan(uid: uid, planId: planId);
      if (plan == null) return;

      final title = plan['title'] ?? 'Recurring Plan';
      final days = plan['days'] as Map<String, dynamic>;

      if (planType == 'day' && weekdays != null) {
        await publishPlanToCalendar(
          title: title,
          startDate: DateTime.now(),
          planData: days,
          isWeekPlan: false,
          sourcePlanId: planId,
          activeWeekdays: weekdays,
          weeksToFill: 52,
        );
      } else if (planType == 'week' && weekAnchorDateKey != null) {
        final start = MealPlanKeys.parseDayKey(weekAnchorDateKey);
        if (start != null) {
          await publishPlanToCalendar(
            title: title,
            startDate: start,
            planData: days,
            isWeekPlan: true,
            sourcePlanId: planId,
            weeksToFill: 52,
          );
        }
      }
    }
  }

  Future<void> stopRecurringDayPlan({required String savedPlanId, required List<int> weekdays}) async {
    await setSavedPlanRecurring(planId: savedPlanId, planType: 'day', enabled: false, weekdays: weekdays);
  }

  Future<void> applyRecurringDayPlanForward({required String savedDayPlanId, required List<int> weekdays}) async {
    final uid = _uid();
    final plan = await _repo.getSavedPlan(uid: uid, planId: savedDayPlanId);
    if (plan == null) return;

    await publishPlanToCalendar(
      title: plan['title'],
      startDate: DateTime.now(),
      planData: plan['days'],
      isWeekPlan: false,
      sourcePlanId: savedDayPlanId,
      activeWeekdays: weekdays,
      weeksToFill: 52,
    );
  }

  // ✅ NEW ROBUST WIPER: Uses Iteration instead of Query
  // This fixes the "Gap" bug by explicitly checking every week against the stop date
  Future<void> _wipeFutureInstances(String planId, {required DateTime stopFromDate}) async {
    final uid = _uid();
    final batch = _firestore.batch();
    int opCount = 0;

    // Iterate 52 weeks from the stop date.
    final start = DateTime(stopFromDate.year, stopFromDate.month, stopFromDate.day);

    for (int i = 0; i < 52; i++) {
      final dateInWeek = start.add(Duration(days: i * 7));
      final weekId = MealPlanKeys.weekIdForDate(dateInWeek);
      final docRef = _repo.weekDoc(uid: uid, weekId: weekId);

      // Read doc to see what's in it
      final docSnap = await docRef.get();
      if (!docSnap.exists) continue;

      final data = docSnap.data()!;
      final config = data['config'] as Map? ?? {};
      final weekDayKeys = MealPlanKeys.weekDayKeys(weekId);

      bool modified = false;
      final updateData = <String, dynamic>{};

      // 1. Check Week Link
      if (config['sourceWeekPlanId'] == planId) {
        // Detach the week config
        updateData['config.sourceWeekPlanId'] = FieldValue.delete();
        updateData['config.title'] = FieldValue.delete();
        updateData['config.weekPlanStartDayKey'] = FieldValue.delete();
        updateData['config.startDayKey'] = FieldValue.delete();

        // Clear days that are ON or AFTER the stop date
        for (final dk in weekDayKeys) {
          final dt = MealPlanKeys.parseDayKey(dk);
          if (dt != null && !dt.isBefore(start)) {
            updateData['days.$dk'] = {};
            updateData['config.daySources.$dk'] = FieldValue.delete();
            updateData['config.dayPlanTitles.$dk'] = FieldValue.delete();
          }
        }
        modified = true;
      }
      // 2. Check Day Links
      else if (config['daySources'] is Map) {
        final sources = Map<String, dynamic>.from(config['daySources']);

        sources.forEach((dayKey, sourceId) {
          if (sourceId == planId) {
            final dt = MealPlanKeys.parseDayKey(dayKey);
            // Only wipe if this specific day is ON or AFTER the stop date
            if (dt != null && !dt.isBefore(start)) {
              updateData['days.$dayKey'] = {};
              updateData['config.daySources.$dayKey'] = FieldValue.delete();
              updateData['config.dayPlanTitles.$dayKey'] = FieldValue.delete();
              modified = true;
            }
          }
        });
      }

      if (modified) {
        updateData['updatedAt'] = FieldValue.serverTimestamp();
        batch.update(docRef, updateData);
        opCount++;
      }

      if (opCount >= 400) {
        await batch.commit();
        opCount = 0;
      }
    }

    if (opCount > 0) await batch.commit();
  }

  Future<void> clearWeekCompletely({required String weekId}) async {
    final ref = _repo.weekDoc(uid: _uid(), weekId: weekId);
    await ref.set({
      'weekId': weekId,
      'days': {},
      'config': {'mode': 'empty', 'daysToPlan': 7},
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeDayFromWeek({required String weekId, required String dayKey}) async {
    final ref = _repo.weekDoc(uid: _uid(), weekId: weekId);
    await ref.update({
      'days.$dayKey': {},
      'config.daySources.$dayKey': FieldValue.delete(),
      'config.dayPlanTitles.$dayKey': FieldValue.delete(),
    });
  }
}

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
    final batch = _firestore.batch();
    int opCount = 0;

    // Normalize Start Date
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final sourceKeys = planData.keys.toList()..sort(); 

    for (int i = 0; i < weeksToFill; i++) {
      final targetDateInWeek = start.add(Duration(days: i * 7));
      final weekId = MealPlanKeys.weekIdForDate(targetDateInWeek);
      final weekRef = _repo.weekDoc(uid: uid, weekId: weekId);
      final weekDayKeys = MealPlanKeys.weekDayKeys(weekId);

      // Check partial start (e.g. starting mid-week)
      final weekMonday = MealPlanKeys.weekStartMonday(targetDateInWeek);
      final isPartialStartWeek = start.isAfter(weekMonday) && start.isBefore(weekMonday.add(const Duration(days: 7)));

      final daysPayload = <String, dynamic>{};
      final configPayload = <String, dynamic>{};
      final daySourcesPayload = <String, dynamic>{};
      final dayTitlesPayload = <String, dynamic>{};
      
      bool weekModified = false;

      for (int d = 0; d < 7; d++) {
        final dateKey = weekDayKeys[d];
        final dt = MealPlanKeys.parseDayKey(dateKey)!;

        // SKIP HISTORY: If this day is before our Start Date, don't touch it.
        if (dt.isBefore(start)) continue;

        if (isWeekPlan) {
          if (d < sourceKeys.length) {
             final sourceKey = sourceKeys[d];
             daysPayload[dateKey] = planData[sourceKey];
             weekModified = true;
             daySourcesPayload[dateKey] = sourcePlanId ?? '';
             dayTitlesPayload[dateKey] = title;
          }
        } else {
          if (activeWeekdays != null && activeWeekdays.contains(dt.weekday)) {
             final template = planData.values.first;
             daysPayload[dateKey] = template;
             daySourcesPayload[dateKey] = sourcePlanId ?? '';
             dayTitlesPayload[dateKey] = title;
             weekModified = true;
          }
        }
      }

      if (!weekModified) continue;

      // Construct Payload
      if (isWeekPlan && !isPartialStartWeek) {
        configPayload['mode'] = 'week';
        configPayload['activeMode'] = 'week';
        configPayload['sourceWeekPlanId'] = sourcePlanId;
        configPayload['title'] = title;
        configPayload['daysToPlan'] = 7;
        configPayload['startDayKey'] = MealPlanKeys.dayKey(start);
        configPayload['daySources'] = FieldValue.delete();
        configPayload['dayPlanTitles'] = FieldValue.delete();
      } else {
        if (daySourcesPayload.isNotEmpty) configPayload['daySources'] = daySourcesPayload;
        if (dayTitlesPayload.isNotEmpty) configPayload['dayPlanTitles'] = dayTitlesPayload;
      }

      final writeData = <String, dynamic>{
        'weekId': weekId,
        'updatedAt': FieldValue.serverTimestamp(),
        'days': daysPayload, 
        'config': configPayload,
      };

      batch.set(weekRef, writeData, SetOptions(merge: true));
      opCount++;

      if (opCount >= 400) {
        await batch.commit();
        opCount = 0;
      }
    }

    if (opCount > 0) await batch.commit();
    
    if (isWeekPlan && sourcePlanId != null) {
      await _repo.setActiveRecurringWeekPlanId(uid: uid, planId: sourcePlanId);
    }
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
      weekAnchorDateKey: weekAnchorDateKey
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
          activeWeekdays: weekdays
        );
      }
      else if (planType == 'week' && weekAnchorDateKey != null) {
        final start = MealPlanKeys.parseDayKey(weekAnchorDateKey);
        if (start != null) {
          await publishPlanToCalendar(
            title: title, 
            startDate: start, 
            planData: days, 
            isWeekPlan: true, 
            sourcePlanId: planId
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
      activeWeekdays: weekdays
    );
  }

  // ✅ NEW ROBUST WIPER: Uses Iteration instead of Query
  // This fixes the "Gap" bug by explicitly checking every week against the stop date
  Future<void> _wipeFutureInstances(String planId, {required DateTime stopFromDate}) async {
    final uid = _uid();
    final batch = _firestore.batch();
    int opCount = 0;

    // Iterate 52 weeks from the stop date. 
    // This matches the "Timeline" architecture perfectly.
    
    final start = DateTime(stopFromDate.year, stopFromDate.month, stopFromDate.day);

    for (int i = 0; i < 52; i++) {
      final dateInWeek = start.add(Duration(days: i * 7));
      final weekId = MealPlanKeys.weekIdForDate(dateInWeek);
      final docRef = _repo.weekDoc(uid: uid, weekId: weekId);
      
      // We read the doc to see what's in it
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
        
        // Clear days that are ON or AFTER the stop date
        for (final dk in weekDayKeys) {
          final dt = MealPlanKeys.parseDayKey(dk);
          if (dt != null && !dt.isBefore(start)) {
             updateData['days.$dk'] = {};
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
      'weekId': weekId, 'days': {}, 
      'config': {'mode': 'empty', 'daysToPlan': 7},
      'updatedAt': FieldValue.serverTimestamp()
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
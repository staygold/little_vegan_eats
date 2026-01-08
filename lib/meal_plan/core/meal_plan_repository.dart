// lib/meal_plan/core/meal_plan_repository.dart
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
  // Refs
  // -------------------------------------------------------
  DocumentReference<Map<String, dynamic>> weekDoc({required String uid, required String weekId}) {
    return _firestore.collection('users').doc(uid).collection('mealPlansWeeks').doc(weekId);
  }

  CollectionReference<Map<String, dynamic>> savedPlansCol({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('savedMealPlans');
  }

  DocumentReference<Map<String, dynamic>> savedPlanDoc({required String uid, required String planId}) {
    return savedPlansCol(uid: uid).doc(planId);
  }

  DocumentReference<Map<String, dynamic>> settingsDoc({required String uid}) {
    return _firestore.collection('users').doc(uid).collection('mealPlan').doc('settings');
  }

  // -------------------------------------------------------
  // Core Read/Write
  // -------------------------------------------------------

  Stream<Map<String, dynamic>?> watchWeek({required String uid, required String weekId}) {
    return weekDoc(uid: uid, weekId: weekId).snapshots().map((snap) => snap.data());
  }

  /// DUMB & SIMPLE: Just create an empty shell if it doesn't exist.
  Future<void> ensureWeekExists({required String uid, required String weekId}) async {
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
  // ✅ RESTORED METHODS (Required by Controller/UI)
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
  // Saved Plans / Recurring Helpers
  // -------------------------------------------------------
  
  Future<void> deleteSavedPlan({required String uid, required String planId}) async {
    await savedPlanDoc(uid: uid, planId: planId).delete();
  }

  Future<Map<String, dynamic>?> getSavedPlan({required String uid, required String planId}) async {
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
    if (weekAnchorDateKey != null) update['recurringWeekAnchorDate'] = weekAnchorDateKey;
    
    if (!enabled) {
      update['recurringWeekdays'] = FieldValue.delete();
    } else if (weekdays != null) {
      update['recurringWeekdays'] = weekdays;
    }

    await ref.set(update, SetOptions(merge: true));
  }

  Future<void> setActiveRecurringWeekPlanId({required String uid, String? planId}) async {
    final ref = settingsDoc(uid: uid);
    await ref.set({'activeRecurringWeekPlanId': planId ?? FieldValue.delete()}, SetOptions(merge: true));
  }
  
  Future<String?> getActiveRecurringWeekPlanId({required String uid}) async {
    final snap = await settingsDoc(uid: uid).get();
    return snap.data()?['activeRecurringWeekPlanId']?.toString();
  }

  // -------------------------------------------------------
  // Static Helpers
  // -------------------------------------------------------
  static bool hasAnyPlannedEntries(Map<String, dynamic>? weekData) {
    if (weekData == null) return false;
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
    return (weekData['days']?[dayKey] as Map<String, dynamic>?);
  }
  
  // Legacy support wrapper
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
      
      batch.set(ref, {
        'weekId': t.weekId,
        'days': baseDays,
        'config': {'mode': 'empty', 'daysToPlan': 7}
      }, SetOptions(merge: true));

      batch.update(ref, {
        'days.${t.dayKey}': daySlots,
        'config.daySources.${t.dayKey}': sourcePlanId,
        'config.dayPlanTitles.${t.dayKey}': title,
      });
    }
    await batch.commit();
  }
}
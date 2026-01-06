import 'package:cloud_firestore/cloud_firestore.dart';

class MealPlanRepository {
  final FirebaseFirestore _firestore;

  MealPlanRepository(this._firestore);

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

  Stream<Map<String, dynamic>?> watchWeek({
    required String uid,
    required String weekId,
  }) {
    return weekDoc(uid: uid, weekId: weekId).snapshots().map((snap) => snap.data());
  }

  Future<void> ensureWeekExists({
    required String uid,
    required String weekId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'weekId': weekId,
        'createdAt': FieldValue.serverTimestamp(),
        'days': <String, dynamic>{},
      });
    }
  }

  /// Replaces the current week's schedule with a new set of days.
  /// ✅ IMPORTANT: replaces the entire `days` map (not a merge).
  Future<void> overrideWeekPlan({
    required String uid,
    required String weekId,
    required Map<String, Map<String, dynamic>> newDays,
    required Map<String, dynamic> config,
    String? sourcePlanId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    final snap = await ref.get();

    final cfg = <String, dynamic>{
      ...config,
      if (sourcePlanId != null && sourcePlanId.trim().isNotEmpty)
        'sourcePlanId': sourcePlanId.trim(),
    };

    if (!snap.exists) {
      await ref.set({
        'weekId': weekId,
        'createdAt': FieldValue.serverTimestamp(),
        'days': newDays,
        'config': cfg,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    // ✅ Replaces the whole map (fixes "only first day populated" + stale days)
    await ref.update({
      'days': newDays,
      'config': cfg,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveDay({
    required String uid,
    required String weekId,
    required String dayKey,
    required Map<String, dynamic> daySlots,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    await ref.update({
      'days.$dayKey': daySlots,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteWeek({
    required String uid,
    required String weekId,
  }) async {
    await weekDoc(uid: uid, weekId: weekId).delete();
  }

  // --- Static Helpers ---

  static bool hasAnyPlannedEntries(Map<String, dynamic>? weekData) {
    if (weekData == null) return false;
    final days = weekData['days'];
    if (days is! Map) return false;

    for (final d in days.values) {
      if (d is Map && d.isNotEmpty) {
        for (final slot in d.values) {
          if (slot is Map) {
            final type = slot['type'];
            if (type == 'recipe' || type == 'note' || type == 'reuse') return true;
          }
        }
      }
    }
    return false;
  }

  static Map<String, dynamic>? dayMapFromWeek(Map<String, dynamic> weekData, String dayKey) {
    final days = weekData['days'];
    if (days is! Map) return null;
    final d = days[dayKey];
    if (d is! Map) return null;
    return Map<String, dynamic>.from(d);
  }
}

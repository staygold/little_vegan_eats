import 'package:cloud_firestore/cloud_firestore.dart';

class MealPlanRepository {
  MealPlanRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> weekDoc({
    required String uid,
    required String weekId,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('mealPlansWeeks')
        .doc(weekId);
  }

  Stream<Map<String, dynamic>?> watchWeek({
    required String uid,
    required String weekId,
  }) {
    return weekDoc(uid: uid, weekId: weekId).snapshots().map((d) => d.data());
  }

  Future<Map<String, dynamic>?> loadWeek({
    required String uid,
    required String weekId,
  }) async {
    final snap = await weekDoc(uid: uid, weekId: weekId).get();
    return snap.data();
  }

  /// Ensures a week doc exists with a skeleton { days: {} }.
  Future<void> ensureWeekExists({
    required String uid,
    required String weekId,
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set({
      'days': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'weekId': weekId,
    }, SetOptions(merge: true));
  }

  /// Writes only one day: days.{dayKey} = updatedDayMap
  Future<void> saveDay({
    required String uid,
    required String weekId,
    required String dayKey,
    required Map<String, dynamic> daySlots, // slot -> recipeId (int)
  }) async {
    final ref = weekDoc(uid: uid, weekId: weekId);
    await ref.set({
      'days': {dayKey: daySlots},
      'updatedAt': FieldValue.serverTimestamp(),
      'weekId': weekId,
    }, SetOptions(merge: true));
  }

  /// Writes multiple days at once: days.{dayKey} = map(slot -> recipeId)
  /// Merge=true so it never overwrites other days/fields.
  Future<void> upsertDays({
    required String uid,
    required String weekId,
    required Map<String, Map<String, dynamic>> days,
  }) async {
    if (days.isEmpty) return;

    final ref = weekDoc(uid: uid, weekId: weekId);
    await ref.set({
      'days': days,
      'updatedAt': FieldValue.serverTimestamp(),
      'weekId': weekId,
    }, SetOptions(merge: true));
  }

  /// Convenience: read day map from weekData
  static Map<String, dynamic>? dayMapFromWeek(
    Map<String, dynamic> weekData,
    String dayKey,
  ) {
    final days = weekData['days'];
    if (days is Map) {
      final raw = days[dayKey];
      if (raw is Map) return Map<String, dynamic>.from(raw);
    }
    return null;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MealPlanManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Helper to get current user doc ref
  DocumentReference _userRef() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(uid);
  }

  /// ✅ FIX 1: Remove Day
  /// Clears the meals for the day AND removes the 'daySource' link
  Future<void> removeDayFromWeek({
    required String weekId,
    required String dayKey,
  }) async {
    final weekRef = _userRef().collection('mealPlansWeeks').doc(weekId);

    // We use a Map to update multiple fields at once
    final updates = <String, dynamic>{
      // 1. Delete the actual food/slots for this day
      'days.$dayKey': FieldValue.delete(),
      
      // 2. THIS WAS MISSING: Delete the "Active Link" for this day
      'config.daySources.$dayKey': FieldValue.delete(),
      
      // 3. Mark as updated
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await weekRef.update(updates);
  }

  /// ✅ FIX 2: Clear Entire Week
  /// Wipes all days AND all source configurations (Week or Day sources)
  Future<void> removeActiveWeekPlan(String weekId) async {
    final weekRef = _userRef().collection('mealPlansWeeks').doc(weekId);

    // We effectively reset the document to a blank slate, 
    // but keep the 'config' map structure alive to avoid null errors.
    await weekRef.set({
      'days': {}, // Clear all days
      'config': {
        'title': '', // Clear title
        'sourceWeekPlanId': FieldValue.delete(), // Remove week link
        'daySources': FieldValue.delete(),       // Remove all day links
        'updatedAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }
}
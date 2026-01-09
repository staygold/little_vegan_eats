// lib/meal_plan/services/meal_plan_manager.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ✅ LEGACY STUB
/// We are migrating to the Programs model:
/// - users/{uid}/mealPrograms/{programId}
/// - users/{uid}/mealPrograms/{programId}/mealProgramDays/{dateKey}
///
/// This manager previously wrote into week docs + saved plans + recurring.
/// It is intentionally stubbed so legacy paths cannot be called accidentally.
///
/// Once migration is complete, delete this file and remove all imports.
class MealPlanManager {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  MealPlanManager({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String _uid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');
    return uid;
  }

  // -------------------------------------------------------
  // LEGACY METHODS (kept for compilation; intentionally disabled)
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
    // If this fires, it means a screen is still using the old system.
    throw StateError(
      'MealPlanManager.publishPlanToCalendar is legacy and disabled. '
      'Use Programs model (mealPrograms + mealProgramDays).',
    );
  }

  Future<void> deleteSavedPlan({
    required String planId,
    required Map<String, dynamic> planData,
  }) async {
    // No-op in Programs model.
    // If you still call this, you should remove that code path.
    return;
  }

  Future<void> setSavedPlanRecurring({
    required String planId,
    required String planType,
    required bool enabled,
    List<int>? weekdays,
    String? weekAnchorDateKey,
    DateTime? stopFromDate,
  }) async {
    // No-op in Programs model.
    return;
  }

  Future<void> stopRecurringDayPlan({
    required String savedPlanId,
    required List<int> weekdays,
  }) async {
    return;
  }

  Future<void> applyRecurringDayPlanForward({
    required String savedDayPlanId,
    required List<int> weekdays,
  }) async {
    return;
  }

  Future<void> clearWeekCompletely({required String weekId}) async {
    // Legacy no-op
    return;
  }

  Future<void> removeDayFromWeek({required String weekId, required String dayKey}) async {
    // Legacy no-op
    return;
  }

  // -------------------------------------------------------
  // Optional: sanity helper (can be removed later)
  // -------------------------------------------------------
  Future<bool> hasLoggedInUser() async {
    try {
      _uid();
      return true;
    } catch (_) {
      return false;
    }
  }
}

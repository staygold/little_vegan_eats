// lib/meal_plan/core/meal_plan_review_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'meal_plan_controller.dart';
import 'meal_plan_keys.dart';
import 'meal_plan_slots.dart';

class MealPlanReviewService {
  // ------------------------------------------------------------
  // Firestore helpers
  // ------------------------------------------------------------

  static DocumentReference<Map<String, dynamic>>? _userDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  static Map<String, dynamic> _asStringDynamicMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  /// ✅ Decide if a plan is actually active/existing.
  /// Conservative: return true if *any* known plan signal exists.
  static bool _hasActivePlanFromUserDoc(Map<String, dynamic> data) {
    // Preferred: program-based
    final activeProgramId = data['activeProgramId'];
    if (activeProgramId != null && activeProgramId.toString().trim().isNotEmpty) {
      return true;
    }

    // Sometimes weekId is used as "current plan week"
    final weekId = data['weekId'];
    if (weekId != null && weekId.toString().trim().isNotEmpty) {
      return true;
    }

    // Some apps store a top-level mealPlan object when any plan exists
    final mealPlan = data['mealPlan'];
    if (mealPlan is Map && mealPlan.isNotEmpty) return true;

    // Some apps store programs list/map
    final programs = data['programs'];
    if (programs is List && programs.isNotEmpty) return true;
    if (programs is Map && programs.isNotEmpty) return true;

    // Legacy / fallback
    final weeks = data['weeks'];
    if (weeks is Map && weeks.isNotEmpty) return true;

    return false;
  }

  // ------------------------------------------------------------
  // Core logic
  // ------------------------------------------------------------

  /// Returns true if any currently planned recipe is no longer allowed
  /// (e.g. allergy changes).
  ///
  /// NOTE: This reads only Firestore entries (not drafts).
  static bool mealPlanHasConflicts({
    required MealPlanController ctrl,
    required Map<String, dynamic>? Function(int id) recipeById,
  }) {
    final dayKeys = MealPlanKeys.weekDayKeys(ctrl.weekId);

    for (final dayKey in dayKeys) {
      for (final slot in MealPlanSlots.order) {
        final entry = ctrl.firestoreEntry(dayKey, slot);
        final rid = ctrl.entryRecipeId(entry);
        if (rid == null) continue;

        final recipe = recipeById(rid);
        if (recipe == null) continue;

        // ✅ Single source of truth (controller wraps unified engine)
        if (!ctrl.recipeAllowed(recipe)) return true;
      }
    }

    return false;
  }

  // ------------------------------------------------------------
  // Persistence
  // ------------------------------------------------------------

  /// Marks the meal plan as needing review.
  /// ✅ Only triggers if a plan is active.
  /// ✅ Must never be allowed to crash profile saving.
  static Future<void> markNeedsReview({
    required String changedForLabel,
  }) async {
    final doc = _userDoc();
    if (doc == null) return;

    try {
      // ✅ Gate: only set review flag if there's an active/existing plan
      final snap = await doc.get();
      final data = snap.data() ?? <String, dynamic>{};

      final hasPlan = _hasActivePlanFromUserDoc(data);
      if (!hasPlan) return;

      await doc.set(
        {
          'mealPlanReview': {
            'needed': true,
            'reason': 'Allergies updated for $changedForLabel',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      // Never crash caller (profile save).
      debugPrint('MealPlanReviewService.markNeedsReview ignored error: $e');
    }
  }

  // ------------------------------------------------------------
  // UI prompt
  // ------------------------------------------------------------

  /// Safe: will never throw, never prompts during route transitions,
  /// and clears the review flag without crashing.
  static Future<void> checkAndPromptIfNeeded(BuildContext context) async {
    final doc = _userDoc();
    if (doc == null) return;

    try {
      // If we're not on an active route, bail early.
      final route = ModalRoute.of(context);
      if (route == null || !route.isCurrent) return;

      final snap = await doc.get();
      final data = snap.data() ?? <String, dynamic>{};

      // ✅ Gate: if no plan, we shouldn't prompt (and we should clear any stale flag)
      final hasPlan = _hasActivePlanFromUserDoc(data);

      final review = _asStringDynamicMap(data['mealPlanReview']);
      final needed = review['needed'] == true;

      if (!hasPlan) {
        if (needed) {
          // Clear stale flag quietly
          await doc.set(
            {
              'mealPlanReview': {'needed': false},
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        return;
      }

      if (!needed) return;

      final reason =
          (review['reason'] is String && (review['reason'] as String).trim().isNotEmpty)
              ? (review['reason'] as String).trim()
              : 'Allergies have changed. Your meal plan may need reviewing.';

      if (!context.mounted) return;

      // Re-check route status right before showing UI
      final r2 = ModalRoute.of(context);
      if (r2 == null || !r2.isCurrent) return;

      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Meal plan needs review'),
          content: Text(
            '$reason\n\n'
            'You can keep your plan as-is (affected meals will be flagged), '
            'or review and update your meals.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: const Text('Keep existing'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'review'),
              child: const Text('Review now'),
            ),
          ],
        ),
      );

      if (!context.mounted) return;

      if (action == 'review') {
        // Only navigate if we’re still on the active route.
        final r3 = ModalRoute.of(context);
        if (r3 != null && r3.isCurrent) {
          Navigator.of(context).pushNamed(
            '/meal-plan',
            arguments: {'review': true},
          );
        }
      }

      // Clear flag (do not overwrite reason/updatedAt)
      await doc.set(
        {
          'mealPlanReview': {'needed': false},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('MealPlanReviewService.checkAndPromptIfNeeded ignored error: $e');
    }
  }
}

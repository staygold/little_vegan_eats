import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'meal_plan_controller.dart';

class MealPlanReviewService {
  // ------------------------------------------------------------
  // Firestore helpers
  // ------------------------------------------------------------

  static DocumentReference<Map<String, dynamic>>? _userDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  // ------------------------------------------------------------
  // Core logic
  // ------------------------------------------------------------

  /// Checks whether the current meal plan contains
  /// any recipes that are no longer allowed under
  /// the current allergy rules.
  static bool mealPlanHasConflicts({
    required MealPlanController ctrl,
    required Map<String, dynamic>? Function(int id) recipeById,
  }) {
    final week = ctrl.weekData;
    if (week == null) return false;

    for (final day in week.values) {
      if (day is! Map) continue;

      for (final entry in day.values) {
        final rid = ctrl.entryRecipeId(entry);
        if (rid == null) continue;

        final recipe = recipeById(rid);
        if (recipe == null) continue;

        if (!ctrl.recipeAllowed(recipe)) {
          return true; // 🔴 conflict found
        }
      }
    }

    return false;
  }

  // ------------------------------------------------------------
  // Persistence
  // ------------------------------------------------------------

  /// Marks the meal plan as needing review.
  /// This is cheap, idempotent, and safe to call.
  static Future<void> markNeedsReview({
    required String changedForLabel,
  }) async {
    final doc = _userDoc();
    if (doc == null) return;

    await doc.set({
      'mealPlanReview': {
        'needed': true,
        'reason': 'Allergies updated for $changedForLabel',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ------------------------------------------------------------
  // UI prompt
  // ------------------------------------------------------------

  /// Checks Firestore and prompts the user if a review
  /// has been marked as needed.
  ///
  /// Call this from:
  /// - App home
  /// - Meal plan screen
  /// - After login
  static Future<void> checkAndPromptIfNeeded(BuildContext context) async {
    final doc = _userDoc();
    if (doc == null) return;

    final snap = await doc.get();
    final data = snap.data() ?? {};
    final review = data['mealPlanReview'];

    final needed = (review is Map && review['needed'] == true);
    if (!needed) return;

    final reason = (review is Map && review['reason'] is String)
        ? review['reason'] as String
        : 'Allergies have changed. Your meal plan may need reviewing.';

    if (!context.mounted) return;

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
      Navigator.of(context).pushNamed(
        '/meal-plan',
        arguments: {'review': true},
      );
    }

    // Clear the flag so it doesn't nag
    await doc.set({
      'mealPlanReview': {
        'needed': false,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

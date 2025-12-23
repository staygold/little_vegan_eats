import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MealPlanReviewService {
  static DocumentReference<Map<String, dynamic>>? _userDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  static Future<void> markNeedsReview({required String changedForLabel}) async {
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

  static Future<void> checkAndPromptIfNeeded(BuildContext context) async {
    final doc = _userDoc();
    if (doc == null) return;

    final snap = await doc.get();
    final data = snap.data() ?? {};
    final review = data['mealPlanReview'];

    final needed = (review is Map && review['needed'] == true);
    if (!needed) return;

    final reason = (review is Map && review['reason'] is String)
        ? (review['reason'] as String)
        : 'Allergies have changed. Your meal plan may need reviewing.';

    if (!context.mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Meal plan needs review'),
        content: Text(reason),
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
      Navigator.of(context).pushNamed('/meal-plan');
    }

    // Clear the flag so it doesn't nag.
    await doc.set({
      'mealPlanReview': {'needed': false},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

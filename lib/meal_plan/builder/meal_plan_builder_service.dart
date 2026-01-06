// lib/meal_plan/builder/meal_plan_builder_service.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/meal_plan_controller.dart';

class MealPlanBuilderService {
  final MealPlanController controller;

  MealPlanBuilderService(this.controller);

  /// Converts any Map (often _Map<dynamic,dynamic> from Firestore) into Map<String,dynamic>.
  /// Safe to use on null / non-map.
  Map<String, dynamic> _stringKeyMap(Object? v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    return <String, dynamic>{};
  }

  Future<void> buildAndActivate({
    required String title,
    required List<Map<String, dynamic>> availableRecipes,
    required int daysToPlan,
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required bool includeSnacks,
    required int snackCount, // 0..2

    /// ✅ NEW: For day plans, specify which date in the current planning horizon to activate.
    /// Must be a YYYY-MM-DD dayKey.
    String? targetDayKey,
  }) async {
    final builtDays = <String, Map<String, dynamic>>{};
    final random = Random();

    Map<String, dynamic>? getRandomRecipe(String slot) {
      final candidates = controller.getCandidatesForSlot(slot, availableRecipes);
      if (candidates.isEmpty) return null;

      final id = candidates[random.nextInt(candidates.length)];
      return <String, dynamic>{
        'recipeId': id,
        'type': 'recipe',
        'kind': 'recipe', // backwards compat
        'source': 'auto builder',
      };
    }

    final effectiveSnackCount = includeSnacks ? snackCount.clamp(0, 2) : 0;

    for (int i = 0; i < daysToPlan; i++) {
      final daySlots = <String, dynamic>{};

      daySlots['breakfast'] = includeBreakfast
          ? (getRandomRecipe('breakfast') ?? <String, dynamic>{'type': 'clear'})
          : <String, dynamic>{'type': 'clear'};

      daySlots['lunch'] = includeLunch
          ? (getRandomRecipe('lunch') ?? <String, dynamic>{'type': 'clear'})
          : <String, dynamic>{'type': 'clear'};

      daySlots['dinner'] = includeDinner
          ? (getRandomRecipe('dinner') ?? <String, dynamic>{'type': 'clear'})
          : <String, dynamic>{'type': 'clear'};

      // Snacks (0..2)
      if (effectiveSnackCount == 0) {
        daySlots['snack1'] = <String, dynamic>{'type': 'clear'};
        // don't write snack2
      } else {
        daySlots['snack1'] =
            getRandomRecipe('snack') ?? <String, dynamic>{'type': 'clear'};

        if (effectiveSnackCount >= 2) {
          daySlots['snack2'] =
              getRandomRecipe('snack') ?? <String, dynamic>{'type': 'clear'};
        }
      }

      builtDays[i.toString()] = daySlots;
    }

    // Save as a new document in savedMealPlans
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(controller.uid);
    final newPlanRef = userRef.collection('savedMealPlans').doc();

    final planDoc = <String, dynamic>{
      'title': title,
      'days': builtDays, // template days: "0".."6"
      'type': daysToPlan == 1 ? 'day' : 'week',
      'savedAt': FieldValue.serverTimestamp(),
      'config': <String, dynamic>{
        // ✅ CRITICAL: used by Home + MealPlanScreen to decide day vs week view
        'daysToPlan': daysToPlan,

        // ✅ Snacks
        'snacksPerDay': effectiveSnackCount,

        // ✅ For day plans, capture the intended date
        if (daysToPlan == 1 && targetDayKey != null && targetDayKey.trim().isNotEmpty)
          'targetDayKey': targetDayKey.trim(),
      },
    };

    await newPlanRef.set(planDoc);

    // Activate it (write to the current week schedule)
    final baseConfig = _stringKeyMap(planDoc['config']);

    final savedPlan = <String, dynamic>{
      ...planDoc,
      'config': <String, dynamic>{
        ...baseConfig,
        // ✅ CRITICAL: MealPlanScreen sync reads config.sourcePlanId
        'sourcePlanId': newPlanRef.id,
      },
    };

    await controller.activateSavedPlan(savedPlan: savedPlan);
  }
}

// lib/meal_plan/builder/meal_plan_builder_service.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/meal_plan_controller.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';
import '../services/meal_plan_manager.dart';

class MealPlanBuilderService {
  final MealPlanController controller;
  MealPlanBuilderService(this.controller);

  Future<void> buildAndActivate({
    required String title,
    required List<Map<String, dynamic>> availableRecipes,
    required bool isDayPlan,
    String? targetDayKey,
    String? weekPlanStartDayKey,
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required bool includeSnacks,
    required int snackCount,
    bool makeRecurring = false,
    List<int>? recurringWeekdays,
  }) async {
    final random = Random();

    Map<String, dynamic> _pick(String slot) {
      final candidates = controller.getCandidatesForSlot(slot, availableRecipes);
      if (candidates.isEmpty) return {'type': 'clear'};
      final id = candidates[random.nextInt(candidates.length)];
      return {'type': 'recipe', 'recipeId': id, 'source': 'auto-builder'};
    }

    Map<String, dynamic> _buildDay() {
      final slots = <String, dynamic>{};
      slots['breakfast'] = includeBreakfast ? _pick('breakfast') : {'type': 'clear'};
      slots['lunch'] = includeLunch ? _pick('lunch') : {'type': 'clear'};
      slots['dinner'] = includeDinner ? _pick('dinner') : {'type': 'clear'};

      final effectiveSnacks = includeSnacks ? snackCount.clamp(0, 2) : 0;
      slots['snack1'] = (effectiveSnacks >= 1) ? _pick('snack') : {'type': 'clear'};
      slots['snack2'] = (effectiveSnacks >= 2) ? _pick('snack') : {'type': 'clear'};

      return slots;
    }

    // ----------------------------
    // Build plan days
    // ----------------------------
    final builtDays = <String, Map<String, dynamic>>{};

    if (isDayPlan) {
      builtDays['template'] = _buildDay();
      builtDays['template']!['title'] = title;
    } else {
      if (weekPlanStartDayKey == null || weekPlanStartDayKey.trim().isEmpty) {
        throw Exception('Missing weekPlanStartDayKey for week plan.');
      }
      final start = MealPlanKeys.parseDayKey(weekPlanStartDayKey)!;
      for (int i = 0; i < 7; i++) {
        final d = start.add(Duration(days: i));
        builtDays[MealPlanKeys.dayKey(d)] = _buildDay();
      }
    }

    // ----------------------------
    // Save template in library
    // ----------------------------
    final userRef = FirebaseFirestore.instance.collection('users').doc(controller.uid);
    final savedPlanRef = userRef.collection('savedMealPlans').doc();
    final planId = savedPlanRef.id;

    final planData = <String, dynamic>{
      'title': title,
      'planType': isDayPlan ? 'day' : 'week',
      'days': builtDays,
      'savedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'recurringEnabled': makeRecurring,
      if (isDayPlan) 'recurringWeekdays': recurringWeekdays ?? [],
      if (!isDayPlan) 'recurringWeekAnchorDate': weekPlanStartDayKey,
    };

    await savedPlanRef.set(planData);

    // ----------------------------
    // Publish into calendar weeks
    // ----------------------------
    final manager = MealPlanManager(
      auth: FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
    );

    DateTime startDate;
    if (isDayPlan) {
      if (targetDayKey == null || targetDayKey.trim().isEmpty) {
        throw Exception('Missing targetDayKey for day plan.');
      }
      startDate = MealPlanKeys.parseDayKey(targetDayKey)!;
    } else {
      startDate = MealPlanKeys.parseDayKey(weekPlanStartDayKey!)!;
    }

    // ✅ KEY FIX:
    // For "once" day plans, we still must tell the publisher which weekday to apply.
    // Otherwise activeWeekdays=null => apply nowhere.
    final List<int>? effectiveActiveWeekdays;
    if (isDayPlan) {
      if (makeRecurring) {
        effectiveActiveWeekdays = (recurringWeekdays ?? <int>[]);
      } else {
        // apply only to the selected day
        effectiveActiveWeekdays = <int>[startDate.weekday];
      }
    } else {
      effectiveActiveWeekdays = null;
    }

    final weeksToFill = makeRecurring ? 52 : 1;

    await manager.publishPlanToCalendar(
      title: title,
      startDate: startDate,
      planData: builtDays,
      isWeekPlan: !isDayPlan,
      sourcePlanId: planId,
      activeWeekdays: effectiveActiveWeekdays,
      weeksToFill: weeksToFill,
    );
  }
}

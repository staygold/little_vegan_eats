import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/meal_plan_controller.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';

class MealPlanBuilderService {
  final MealPlanController controller;
  MealPlanBuilderService(this.controller);

  /// SCENARIO 1 & 2: Generate New Plan (Day or Week)
  Future<void> buildAndActivate({
    required String title,
    required List<Map<String, dynamic>> availableRecipes,
    required int daysToPlan, // 1 or 7
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required bool includeSnacks,
    required int snackCount, 
    String? targetDayKey, // required if daysToPlan == 1
  }) async {
    final random = Random();
    final isDayPlan = daysToPlan == 1;

    if (isDayPlan && (targetDayKey == null || targetDayKey.trim().isEmpty)) {
      throw Exception('Day plan requires a targetDayKey');
    }

    // --- Helper: Pick Random ---
    Map<String, dynamic> _pick(String slot) {
      final candidates = controller.getCandidatesForSlot(slot, availableRecipes);
      if (candidates.isEmpty) return <String, dynamic>{'type': 'clear'};
      
      final id = candidates[random.nextInt(candidates.length)];
      return {
        'type': 'recipe',
        'kind': 'recipe', // backward compat
        'recipeId': id,
        'source': 'auto-builder',
      };
    }

    // --- Helper: Build 1 Day ---
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

    // 1. Generate Data
    final builtDays = <String, Map<String, dynamic>>{};
    
    if (isDayPlan) {
      final d = _buildDay();
      d['title'] = title; // Store title on the day slot itself for easy lookup
      builtDays[targetDayKey!] = d;
    } else {
      final weekKeys = MealPlanKeys.weekDayKeys(controller.weekId);
      for (final dk in weekKeys) {
        builtDays[dk] = _buildDay();
      }
    }

    // 2. Save to History (The "Library")
    final userRef = FirebaseFirestore.instance.collection('users').doc(controller.uid);
    final savedPlanRef = userRef.collection('savedMealPlans').doc();
    
    await savedPlanRef.set({
      'title': title,
      'type': isDayPlan ? 'day' : 'week',
      'days': builtDays,
      'savedAt': FieldValue.serverTimestamp(),
    });

    // 3. Activate (Write to "Calendar")
    final repo = MealPlanRepository(FirebaseFirestore.instance);
    await repo.ensureWeekExists(uid: controller.uid, weekId: controller.weekId);

    if (isDayPlan) {
      // SCENARIO 1: DAY PLAN
      // - Update ONLY the specific day slots
      // - Update config.daySources to track this specific day's origin
      // - Do NOT touch other days
      
      await repo.applyDayPlan(
        uid: controller.uid,
        weekId: controller.weekId,
        dayKey: targetDayKey!,
        daySlots: builtDays[targetDayKey!]!,
        sourceDayPlanId: savedPlanRef.id,
      );

      // Force update the daySource tracker
      await userRef.collection('mealPlansWeeks').doc(controller.weekId).set({
        'config': {
          'daySources': {
            targetDayKey: savedPlanRef.id
          }
        }
      }, SetOptions(merge: true));

    } else {
      // SCENARIO 2: WEEK PLAN
      // - Overwrite ALL days
      // - Set config.title
      // - Set config.sourceWeekPlanId
      
      await repo.activateWeekPlan(
        uid: controller.uid,
        weekId: controller.weekId,
        days: builtDays,
        sourceWeekPlanId: savedPlanRef.id,
      );
      
      // Force config update
      await userRef.collection('mealPlansWeeks').doc(controller.weekId).update({
         'config.title': title,
         'config.sourceWeekPlanId': savedPlanRef.id,
         'config.daySources': FieldValue.delete(), // Clear individual day sources
      });
    }
  }

  /// SCENARIO 3: Convert Active Days -> Saved Week Plan
  Future<void> saveCurrentWeekAsPlan(String title) async {
    // 1. Get current active data
    final weekDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(controller.uid)
        .collection('mealPlansWeeks')
        .doc(controller.weekId)
        .get();

    if (!weekDoc.exists) throw Exception("No active week to save");
    
    final data = weekDoc.data()!;
    final days = data['days'] as Map<String, dynamic>? ?? {};

    // 2. Save to History
    final userRef = FirebaseFirestore.instance.collection('users').doc(controller.uid);
    final savedPlanRef = userRef.collection('savedMealPlans').doc();

    await savedPlanRef.set({
      'title': title,
      'type': 'week', // It is now a week plan
      'days': days,   // Contains the mixed day plans
      'savedAt': FieldValue.serverTimestamp(),
    });

    // 3. Update Active Week to point to this new "Master" plan
    await userRef.collection('mealPlansWeeks').doc(controller.weekId).update({
      'config.title': title,
      'config.sourceWeekPlanId': savedPlanRef.id,
      'config.daySources': FieldValue.delete(), // It's no longer a mix of sources
    });
  }
}
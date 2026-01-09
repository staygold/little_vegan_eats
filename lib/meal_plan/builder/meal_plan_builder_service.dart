// lib/meal_plan/builder/meal_plan_builder_service.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/meal_plan_controller.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';

class MealPlanBuilderService {
  final MealPlanController controller;
  MealPlanBuilderService(this.controller);

  // -------------------------------------------------------
  // Date helpers (YYYY-MM-DD)
  // -------------------------------------------------------
  DateTime _parseDateKey(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) throw ArgumentError('Invalid dateKey: $dateKey');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime(y, m, d);
  }

  String _toDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  List<String> _buildScheduledDates({
    required String startDateKey,
    required int weeks, // 1..4
    required List<int> weekdays, // Mon=1..Sun=7
  }) {
    final start = _parseDateKey(startDateKey);
    final totalDays = (weeks.clamp(1, 4)) * 7;
    final allowed = weekdays.where((d) => d >= 1 && d <= 7).toSet();

    final out = <String>[];
    for (int i = 0; i < totalDays; i++) {
      final dt = start.add(Duration(days: i));
      if (allowed.contains(dt.weekday)) {
        out.add(_toDateKey(dt));
      }
    }
    return out;
  }

  String _computeEndDateKey({
    required String startDateKey,
    required int weeks,
  }) {
    final start = _parseDateKey(startDateKey);
    final totalDays = (weeks.clamp(1, 4)) * 7;
    final end = start.add(Duration(days: totalDays - 1));
    return _toDateKey(end);
  }

  // -------------------------------------------------------
  // Slot generation helpers (shared by program + adhoc)
  // -------------------------------------------------------
  Map<String, dynamic> _pick(
    Random random,
    String slot,
    List<Map<String, dynamic>> availableRecipes,
  ) {
    final candidates = controller.getCandidatesForSlot(slot, availableRecipes);
    if (candidates.isEmpty) return {'type': 'clear'};
    final id = candidates[random.nextInt(candidates.length)];
    return {'type': 'recipe', 'recipeId': id, 'source': 'auto-builder'};
  }

  Map<String, dynamic> _buildDaySlots({
    required Random random,
    required List<Map<String, dynamic>> availableRecipes,
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required bool includeSnacks,
    required int snackCount,
  }) {
    final slots = <String, dynamic>{};

    slots['breakfast'] = includeBreakfast
        ? _pick(random, 'breakfast', availableRecipes)
        : {'type': 'clear'};
    slots['lunch'] =
        includeLunch ? _pick(random, 'lunch', availableRecipes) : {'type': 'clear'};
    slots['dinner'] =
        includeDinner ? _pick(random, 'dinner', availableRecipes) : {'type': 'clear'};

    final effectiveSnacks = includeSnacks ? snackCount.clamp(0, 2) : 0;
    slots['snack1'] = (effectiveSnacks >= 1)
        ? _pick(random, 'snack', availableRecipes)
        : {'type': 'clear'};
    slots['snack2'] = (effectiveSnacks >= 2)
        ? _pick(random, 'snack', availableRecipes)
        : {'type': 'clear'};

    return slots;
  }

  // -------------------------------------------------------
  // ✅ Backfill new program-day docs when schedule changes
  // -------------------------------------------------------
  ///
  /// Behaviour:
  /// - Takes old/new scheduledDates
  /// - Finds newly-added dates (optionally skipping past)
  /// - Creates missing users/{uid}/mealPrograms/{programId}/mealProgramDays/{dateKey}
  ///
  Future<int> backfillNewProgramDays({
    required String programId,
    required List<String> oldScheduledDates,
    required List<String> newScheduledDates,
    required List<Map<String, dynamic>> availableRecipes,
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required bool includeSnacks,
    required int snackCount,
    bool skipPast = true,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final repo = MealPlanRepository(firestore);
    final random = Random();

    final oldSet = oldScheduledDates.map((e) => e.toString()).toSet();
    final todayKey = MealPlanKeys.todayKey();

    final added = <String>[];
    for (final dk in newScheduledDates) {
      final clean = dk.toString().trim();
      if (clean.isEmpty) continue;
      if (oldSet.contains(clean)) continue;
      if (skipPast && clean.compareTo(todayKey) < 0) continue;
      added.add(clean);
    }

    if (added.isEmpty) return 0;
    if (availableRecipes.isEmpty) return 0;

    int created = 0;

    for (final dateKey in added) {
      // Validate format
      if (MealPlanKeys.parseDayKey(dateKey) == null) continue;

      // Only create if missing
      final docRef = repo.programDayDoc(
        uid: controller.uid,
        programId: programId,
        dateKey: dateKey,
      );

      final snap = await docRef.get();
      if (snap.exists) continue;

      final daySlots = _buildDaySlots(
        random: random,
        availableRecipes: availableRecipes,
        includeBreakfast: includeBreakfast,
        includeLunch: includeLunch,
        includeDinner: includeDinner,
        includeSnacks: includeSnacks,
        snackCount: snackCount,
      );

      await repo.upsertProgramDay(
        uid: controller.uid,
        programId: programId,
        dateKey: dateKey,
        daySlots: daySlots,
      );

      created++;
    }

    return created;
  }

  // -------------------------------------------------------
  // ✅ ONE-OFF (ad-hoc) day only (NO program activation)
  // -------------------------------------------------------
  ///
  /// Behaviour:
  /// - Generates a day plan for exactly ONE dateKey
  /// - Writes to users/{uid}/mealAdhocDays/{dateKey}
  /// - DOES NOT touch activeProgramId
  ///
  Future<void> buildAdhocDay({
    required String dateKey, // YYYY-MM-DD
    required List<Map<String, dynamic>> availableRecipes,

    // Meal structure prefs
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required int snackCount,

    // Optional
    String? title,
    bool overwrite = true,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final repo = MealPlanRepository(firestore);
    final random = Random();

    final cleanDateKey = dateKey.trim();
    if (cleanDateKey.isEmpty) throw Exception('Invalid day key.');

    // Validate format
    if (MealPlanKeys.parseDayKey(cleanDateKey) == null) {
      throw Exception('Invalid day key.');
    }

    if (availableRecipes.isEmpty) {
      throw Exception('No recipes available.');
    }

    final docRef = repo.adhocDayDoc(uid: controller.uid, dateKey: cleanDateKey);

    if (!overwrite) {
      final existing = await docRef.get();
      if (existing.exists) return;
    }

    final daySlots = _buildDaySlots(
      random: random,
      availableRecipes: availableRecipes,
      includeBreakfast: includeBreakfast,
      includeLunch: includeLunch,
      includeDinner: includeDinner,
      includeSnacks: snackCount > 0,
      snackCount: snackCount,
    );

    await repo.upsertAdhocDay(
      uid: controller.uid,
      dateKey: cleanDateKey,
      daySlots: daySlots,
      title: title,
    );
  }

  // -------------------------------------------------------
  // ✅ Programs-only: Build + Activate
  // -------------------------------------------------------
  ///
  /// Behaviour:
  /// - Creates a finite "Program" (1-4 weeks) with chosen weekdays
  /// - Writes generated meals into mealPrograms/{programId}/mealProgramDays/{dateKey}
  /// - ✅ Sets users/{uid}/mealPlan/settings.activeProgramId
  ///
  Future<void> buildAndActivate({
    required String title,
    required List<Map<String, dynamic>> availableRecipes,

    // Programs model
    required String startDayKey, // YYYY-MM-DD
    required int weeks, // 1..4
    required List<int> weekdays, // Mon=1..Sun=7

    // Meal structure prefs
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required bool includeSnacks,
    required int snackCount,
  }) async {
    final random = Random();
    final firestore = FirebaseFirestore.instance;
    final repo = MealPlanRepository(firestore);

    final cleanTitle = title.trim().isEmpty ? 'My Plan' : title.trim();
    final cleanWeekdays = weekdays
        .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
        .where((e) => e >= 1 && e <= 7)
        .toSet()
        .toList()
      ..sort();

    if (cleanWeekdays.isEmpty) {
      throw Exception('Please select at least one weekday.');
    }

    final startDateKey = startDayKey.trim();

    final scheduledDates = _buildScheduledDates(
      startDateKey: startDateKey,
      weeks: weeks,
      weekdays: cleanWeekdays,
    );

    if (scheduledDates.isEmpty) {
      throw Exception('No planned days found for that schedule.');
    }

    final endDateKey = _computeEndDateKey(
      startDateKey: startDateKey,
      weeks: weeks,
    );

    final programId = await repo.createProgram(
      uid: controller.uid,
      name: cleanTitle,
      startDateKey: startDateKey,
      endDateKey: endDateKey,
      weeks: weeks.clamp(1, 4),
      weekdays: cleanWeekdays,
      scheduledDates: scheduledDates,
    );

    await repo.setActiveProgramId(uid: controller.uid, programId: programId);

    for (final dateKey in scheduledDates) {
      final daySlots = _buildDaySlots(
        random: random,
        availableRecipes: availableRecipes,
        includeBreakfast: includeBreakfast,
        includeLunch: includeLunch,
        includeDinner: includeDinner,
        includeSnacks: includeSnacks,
        snackCount: snackCount,
      );

      await repo.upsertProgramDay(
        uid: controller.uid,
        programId: programId,
        dateKey: dateKey,
        daySlots: daySlots,
      );
    }
  }
}

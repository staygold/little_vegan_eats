// lib/meal_plan/builder/meal_plan_builder_service.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/meal_plan_age_engine.dart';
import '../core/meal_plan_controller.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';
import '../core/meal_plan_log.dart' as mplog;

// -------------------------------------------------------
// Leftovers ledger model (top-level; Dart forbids nested classes)
// -------------------------------------------------------
class _LeftoverBatch {
  final int recipeId;
  final String audience; // family|kids
  final DateTime cookedOn;
  final DateTime expiresOn;
  int remainingItems;

  _LeftoverBatch({
    required this.recipeId,
    required this.audience,
    required this.cookedOn,
    required this.expiresOn,
    required this.remainingItems,
  });
}

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

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _addDays(DateTime d, int days) => d.add(Duration(days: days));

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
  // Audience helpers
  // -------------------------------------------------------
  static const String _audFamily = 'family';
  static const String _audKids = 'kids';

  String _normalizeAudience(String? raw, {required String fallback}) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v == _audKids) return _audKids;
    if (v == _audFamily) return _audFamily;
    return fallback;
  }

  Map<String, String> _normalizeMealAudiences(Map<String, String>? input) {
    final inMap = input ?? const <String, String>{};

    final breakfast =
        _normalizeAudience(inMap['breakfast'], fallback: _audFamily);
    final lunch = _normalizeAudience(inMap['lunch'], fallback: _audFamily);
    final dinner = _normalizeAudience(inMap['dinner'], fallback: _audFamily);

    final snackFallback = _normalizeAudience(inMap['snack'], fallback: _audKids);
    final snack1 = _normalizeAudience(inMap['snack1'], fallback: snackFallback);
    final snack2 = _normalizeAudience(inMap['snack2'], fallback: snackFallback);

    return <String, String>{
      'breakfast': breakfast,
      'lunch': lunch,
      'dinner': dinner,
      'snack': snackFallback,
      'snack1': snack1,
      'snack2': snack2,
    };
  }

  // -------------------------------------------------------
  // Batch cooking reuse tracking
  // recipeId -> first served date
  // -------------------------------------------------------
  Map<int, DateTime> _firstUsedDates = {};

  void _noteFirstUseIfMissing(int recipeId, DateTime servingDate) {
    _firstUsedDates.putIfAbsent(recipeId, () => servingDate);
  }

  void _resetReuseTracking() {
    _firstUsedDates = {};
  }

  // -------------------------------------------------------
  // Leftovers ledger (ITEM serving_mode only)
  // -------------------------------------------------------
  static const String _servingModeItem = 'item';
  final List<_LeftoverBatch> _leftovers = <_LeftoverBatch>[];

  void _resetLeftovers() => _leftovers.clear();

  Map<String, dynamic> _recipeRoot(Map<String, dynamic> recipe) {
    final r = (recipe['recipe'] is Map)
        ? Map<String, dynamic>.from(recipe['recipe'] as Map)
        : recipe;
    return r;
  }

  String _extractServingMode(Map<String, dynamic> recipe) {
    final r = _recipeRoot(recipe);
    final v = (r['serving_mode'] ?? r['servingMode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return v;
  }

  int _extractServingsAdults(Map<String, dynamic> recipe) {
    final r = _recipeRoot(recipe);
    final v = r['servings'] ?? r['servingCount'];
    if (v is int) return max(1, v);
    final parsed = int.tryParse(v?.toString().trim() ?? '');
    return max(1, parsed ?? 1);
  }

  int _extractItemsPerPerson(Map<String, dynamic> recipe) {
    final r = _recipeRoot(recipe);
    final v = r['items_per_person'] ?? r['itemsPerPerson'];
    if (v is int) return max(1, v);
    final parsed = int.tryParse(v?.toString().trim() ?? '');
    return max(1, parsed ?? 1);
  }

  double _extractKidsItemFactor(Map<String, dynamic> recipe) {
    final r = _recipeRoot(recipe);
    final v = r['kids_item_factor'] ?? r['kidsItemFactor'];
    if (v is num) return v.toDouble();
    final parsed = double.tryParse(v?.toString().trim() ?? '');
    return (parsed ?? 0.5).clamp(0.1, 2.0);
  }

  Map<String, dynamic>? _findRecipeById(
    List<Map<String, dynamic>> availableRecipes,
    int recipeId,
  ) {
    for (final r in availableRecipes) {
      final id = controller.recipeIdFromAny(r['id']);
      if (id == recipeId) return r;
    }
    return null;
  }

  int _itemsMadeBase(Map<String, dynamic> recipe) {
    final servings = _extractServingsAdults(recipe);
    final itemsPerPerson = _extractItemsPerPerson(recipe);
    return max(1, servings * itemsPerPerson);
  }

  int _itemsNeededForSlotDay({
    required Map<String, dynamic> recipe,
    required String audience,
    required int adultCount,
    required int kidCount,
  }) {
    final itemsPerPerson = _extractItemsPerPerson(recipe);
    final kidsFactor = _extractKidsItemFactor(recipe);

    if (audience == _audKids) {
      final raw = kidCount * itemsPerPerson * kidsFactor;
      return max(1, raw.ceil());
    } else {
      final adultRaw = adultCount * itemsPerPerson;
      final kidRaw = kidCount * itemsPerPerson * kidsFactor;
      final total = adultRaw + kidRaw;
      return max(1, total.ceil());
    }
  }

  _LeftoverBatch? _findUsableLeftover({
    required int recipeId,
    required String audience,
    required DateTime servingDate,
    required int itemsNeeded,
  }) {
    final day = _dateOnly(servingDate);

    final candidates = _leftovers.where((b) {
      if (b.recipeId != recipeId) return false;
      if (b.audience != audience) return false;
      if (b.remainingItems < itemsNeeded) return false;
      return !day.isAfter(_dateOnly(b.expiresOn));
    }).toList();

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => a.cookedOn.compareTo(b.cookedOn));
    return candidates.first;
  }

  Map<String, dynamic>? _tryUseLeftoversForRecipe({
    required int recipeId,
    required String audience,
    required DateTime servingDate,
    required int itemsNeeded,
  }) {
    final batch = _findUsableLeftover(
      recipeId: recipeId,
      audience: audience,
      servingDate: servingDate,
      itemsNeeded: itemsNeeded,
    );
    if (batch == null) return null;

    batch.remainingItems -= itemsNeeded;

    mplog.MealPlanLog.i(
      'LEFTOVER_HIT recipe=$recipeId audience=$audience day=${_toDateKey(servingDate)} '
      'used=$itemsNeeded remaining=${batch.remainingItems} expires=${_toDateKey(batch.expiresOn)}',
      key: 'leftoverHit:$recipeId:$audience:${_toDateKey(servingDate)}',
    );

    return <String, dynamic>{
      'type': 'recipe',
      'recipeId': recipeId,
      'source': 'leftover',
      'audience': audience,
      'leftover': true,
      'leftoverFromDay': _toDateKey(batch.cookedOn),
      'itemsUsed': itemsNeeded,
    };
  }

  void _createLeftoversIfAny({
    required int recipeId,
    required String audience,
    required DateTime servingDate,
    required int itemsMade,
    required int itemsUsed,
    required int storageDays,
  }) {
    final remaining = max(0, itemsMade - itemsUsed);
    if (remaining <= 0) return;

    final cooked = _dateOnly(servingDate);
    final expires = _addDays(cooked, storageDays);

    _leftovers.add(
      _LeftoverBatch(
        recipeId: recipeId,
        audience: audience,
        cookedOn: cooked,
        expiresOn: expires,
        remainingItems: remaining,
      ),
    );

    mplog.MealPlanLog.i(
      'LEFTOVER_CREATE recipe=$recipeId audience=$audience cooked=${_toDateKey(cooked)} '
      'made=$itemsMade used=$itemsUsed left=$remaining expires=${_toDateKey(expires)}',
      key: 'leftoverCreate:$recipeId:$audience:${_toDateKey(cooked)}',
    );
  }

  // -------------------------------------------------------
  // Baby snack rule markers (entries)
  // -------------------------------------------------------
  bool _isSnackSlot(String slot) =>
      slot == 'snack' || slot == 'snack1' || slot == 'snack2';

  Map<String, dynamic> _firstFoodsSnackEntry({
    required String childKey,
    required String childName,
    required String audience,
  }) =>
      <String, dynamic>{
        'type': 'first_foods',
        'source': 'auto-builder',
        'audience': audience,
        'childKey': childKey,
        if (childName.trim().isNotEmpty) 'childName': childName.trim(),
      };

  Map<String, dynamic> _noSuitableForBabyEntry({
    required String childKey,
    required String childName,
    required String audience,
  }) =>
      <String, dynamic>{
        'type': 'clear',
        'source': 'auto-builder',
        'audience': audience,
        'childKey': childKey,
        if (childName.trim().isNotEmpty) 'childName': childName.trim(),
        'reason': 'no_suitable_meals_baby',
      };

  ({String childKey, String childName})? _youngestBabyChild(
    List<dynamic>? children,
    DateTime servingDate, {
    required int babyThresholdMonths,
  }) {
    if (children == null || children.isEmpty) return null;

    int? bestAgeMonths;
    String? bestChildKey;
    String bestChildName = '';

    for (final c in children) {
      if (c is! Map) continue;
      final m = Map<String, dynamic>.from(c);

      final key = (m['childKey'] ?? m['id'] ?? m['key'] ?? m['uid'] ?? '')
          .toString()
          .trim();
      if (key.isEmpty) continue;

      // Let the AgeEngine parse (dobYear/dobMonth OR timestamp/string)
      final age = MealPlanAgeEngine.ageInMonths(child: m, now: servingDate);
      if (age == null) continue;

      if (bestAgeMonths == null || age < bestAgeMonths!) {
        bestAgeMonths = age;
        bestChildKey = key;
        bestChildName = (m['name'] ?? m['childName'] ?? '').toString().trim();
      }
    }

    if (bestAgeMonths == null || bestChildKey == null) return null;
    if (bestAgeMonths! < babyThresholdMonths) {
      return (childKey: bestChildKey, childName: bestChildName);
    }
    return null;
  }

  // -------------------------------------------------------
  // Slot generation
  // -------------------------------------------------------
  Map<String, dynamic> _pick(
    Random random,
    String slot,
    DateTime servingDate,
    List<Map<String, dynamic>> availableRecipes, {
    required String audience,
    required List<dynamic>? children,
    required int adultCount,
    required int kidCount,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
  }) {
    final baby = _youngestBabyChild(
      children,
      servingDate,
      babyThresholdMonths: babyThresholdMonths,
    );

    final isSnack = _isSnackSlot(slot);

    // Baby snack behaviour
    if (baby != null && isSnack) {
      mplog.MealPlanLog.i(
        'PICK_BABY_SNACK slot=$slot audience=$audience day=${_toDateKey(servingDate)} '
        'youngestChild=${baby.childName}(${baby.childKey}) threshold=$babyThresholdMonths',
        key: 'pickBabySnack:$slot:${_toDateKey(servingDate)}',
      );

      final candidates = controller.getCandidatesForSlotUnified(
        slot,
        availableRecipes,
        audience: audience,
        servingDate: servingDate,
        firstUsedDates: _firstUsedDates,
        babyThresholdMonths: babyThresholdMonths,
        childrenOverride: children,
      );

      mplog.MealPlanLog.i(
        'BABY_SNACK_CANDIDATES slot=$slot day=${_toDateKey(servingDate)} count=${candidates.length}',
        key: 'babySnackCandidates:$slot:${_toDateKey(servingDate)}',
      );

      if (candidates.isNotEmpty) {
        final id = candidates[random.nextInt(candidates.length)];
        _noteFirstUseIfMissing(id, servingDate);

        final full = _findRecipeById(availableRecipes, id);
        if (full != null && _extractServingMode(full) == _servingModeItem) {
          final storageDays = controller.extractStorageDays(full) ?? 0;
          if (storageDays > 0) {
            final itemsNeeded = _itemsNeededForSlotDay(
              recipe: full,
              audience: audience,
              adultCount: adultCount,
              kidCount: kidCount,
            );

            final leftoverEntry = _tryUseLeftoversForRecipe(
              recipeId: id,
              audience: audience,
              servingDate: servingDate,
              itemsNeeded: itemsNeeded,
            );
            if (leftoverEntry != null) {
              leftoverEntry['childKey'] = baby.childKey;
              if (baby.childName.trim().isNotEmpty) {
                leftoverEntry['childName'] = baby.childName.trim();
              }
              return leftoverEntry;
            }

            final made = _itemsMadeBase(full);
            _createLeftoversIfAny(
              recipeId: id,
              audience: audience,
              servingDate: servingDate,
              itemsMade: made,
              itemsUsed: itemsNeeded,
              storageDays: storageDays,
            );

            return <String, dynamic>{
              'type': 'recipe',
              'recipeId': id,
              'source': 'auto-builder',
              'audience': audience,
              'childKey': baby.childKey,
              if (baby.childName.trim().isNotEmpty)
                'childName': baby.childName.trim(),
              'itemsMade': made,
              'itemsUsed': itemsNeeded,
              'storageDays': storageDays,
            };
          }
        }

        return <String, dynamic>{
          'type': 'recipe',
          'recipeId': id,
          'source': 'auto-builder',
          'audience': audience,
          'childKey': baby.childKey,
          if (baby.childName.trim().isNotEmpty) 'childName': baby.childName.trim(),
        };
      }

      // No candidates -> first foods marker entry
      return _firstFoodsSnackEntry(
        childKey: baby.childKey,
        childName: baby.childName,
        audience: audience,
      );
    }

    // Baby + kids-audience + non-snack => blocked
    if (baby != null && !isSnack && audience == _audKids) {
      mplog.MealPlanLog.i(
        'PICK_BABY_BLOCK slot=$slot audience=$audience day=${_toDateKey(servingDate)} nonSnack',
        key: 'pickBabyBlock:$slot:${_toDateKey(servingDate)}',
      );

      return _noSuitableForBabyEntry(
        childKey: baby.childKey,
        childName: baby.childName,
        audience: audience,
      );
    }

    // Normal pick (ONE ENGINE)
    final candidates = controller.getCandidatesForSlotUnified(
      slot,
      availableRecipes,
      audience: audience,
      servingDate: servingDate,
      firstUsedDates: _firstUsedDates,
      babyThresholdMonths: babyThresholdMonths,
      childrenOverride: children,
    );

    mplog.MealPlanLog.d(
      'PICK slot=$slot audience=$audience day=${_toDateKey(servingDate)} candidates=${candidates.length}',
      key: 'pick:$slot:${_toDateKey(servingDate)}',
    );

    if (candidates.isEmpty) {
      return <String, dynamic>{
        'type': 'clear',
        'source': 'auto-builder',
        'audience': audience,
        'reason': 'no_candidates',
      };
    }

    final id = candidates[random.nextInt(candidates.length)];
    _noteFirstUseIfMissing(id, servingDate);

    final full = _findRecipeById(availableRecipes, id);
    if (full != null && _extractServingMode(full) == _servingModeItem) {
      final storageDays = controller.extractStorageDays(full) ?? 0;
      if (storageDays > 0) {
        final itemsNeeded = _itemsNeededForSlotDay(
          recipe: full,
          audience: audience,
          adultCount: adultCount,
          kidCount: kidCount,
        );

        final leftoverEntry = _tryUseLeftoversForRecipe(
          recipeId: id,
          audience: audience,
          servingDate: servingDate,
          itemsNeeded: itemsNeeded,
        );
        if (leftoverEntry != null) return leftoverEntry;

        final made = _itemsMadeBase(full);
        _createLeftoversIfAny(
          recipeId: id,
          audience: audience,
          servingDate: servingDate,
          itemsMade: made,
          itemsUsed: itemsNeeded,
          storageDays: storageDays,
        );

        return <String, dynamic>{
          'type': 'recipe',
          'recipeId': id,
          'source': 'auto-builder',
          'audience': audience,
          'itemsMade': made,
          'itemsUsed': itemsNeeded,
          'storageDays': storageDays,
        };
      }
    }

    return <String, dynamic>{
      'type': 'recipe',
      'recipeId': id,
      'source': 'auto-builder',
      'audience': audience,
    };
  }

  Map<String, dynamic> _buildDaySlots({
    required Random random,
    required DateTime servingDate,
    required List<Map<String, dynamic>> availableRecipes,
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required bool includeSnacks,
    required int snackCount,
    required Map<String, String> mealAudiences,
    required List<dynamic>? children,
    required int adultCount,
    required int kidCount,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
  }) {
    final slots = <String, dynamic>{};

    final aBreakfast = mealAudiences['breakfast'] ?? _audFamily;
    final aLunch = mealAudiences['lunch'] ?? _audFamily;
    final aDinner = mealAudiences['dinner'] ?? _audFamily;
    final aSnack1 =
        mealAudiences['snack1'] ?? (mealAudiences['snack'] ?? _audKids);
    final aSnack2 =
        mealAudiences['snack2'] ?? (mealAudiences['snack'] ?? _audKids);

    slots['breakfast'] = includeBreakfast
        ? _pick(
            random,
            'breakfast',
            servingDate,
            availableRecipes,
            audience: aBreakfast,
            children: children,
            adultCount: adultCount,
            kidCount: kidCount,
            babyThresholdMonths: babyThresholdMonths,
          )
        : {'type': 'clear', 'source': 'auto-builder', 'reason': 'disabled'};

    slots['lunch'] = includeLunch
        ? _pick(
            random,
            'lunch',
            servingDate,
            availableRecipes,
            audience: aLunch,
            children: children,
            adultCount: adultCount,
            kidCount: kidCount,
            babyThresholdMonths: babyThresholdMonths,
          )
        : {'type': 'clear', 'source': 'auto-builder', 'reason': 'disabled'};

    slots['dinner'] = includeDinner
        ? _pick(
            random,
            'dinner',
            servingDate,
            availableRecipes,
            audience: aDinner,
            children: children,
            adultCount: adultCount,
            kidCount: kidCount,
            babyThresholdMonths: babyThresholdMonths,
          )
        : {'type': 'clear', 'source': 'auto-builder', 'reason': 'disabled'};

    final effectiveSnacks = includeSnacks ? snackCount.clamp(0, 2) : 0;

    slots['snack1'] = (effectiveSnacks >= 1)
        ? _pick(
            random,
            'snack1',
            servingDate,
            availableRecipes,
            audience: aSnack1,
            children: children,
            adultCount: adultCount,
            kidCount: kidCount,
            babyThresholdMonths: babyThresholdMonths,
          )
        : {'type': 'clear', 'source': 'auto-builder', 'reason': 'disabled'};

    slots['snack2'] = (effectiveSnacks >= 2)
        ? _pick(
            random,
            'snack2',
            servingDate,
            availableRecipes,
            audience: aSnack2,
            children: children,
            adultCount: adultCount,
            kidCount: kidCount,
            babyThresholdMonths: babyThresholdMonths,
          )
        : {'type': 'clear', 'source': 'auto-builder', 'reason': 'disabled'};

    return slots;
  }

  // -------------------------------------------------------
  // Backfill new program-day docs when schedule changes
  // -------------------------------------------------------
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
    Map<String, String>? mealAudiences,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
  }) async {
    final repo = MealPlanRepository(FirebaseFirestore.instance);
    final random = Random();
    final aud = _normalizeMealAudiences(mealAudiences);

    final childrenProfile = controller.childrenEffectiveOrNull;
    final adultCount = controller.adultCount;
    final kidCount = controller.kidCount;

    final oldSet = oldScheduledDates
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final todayKey = MealPlanKeys.todayKey();

    final added = <String>[];
    for (final dk in newScheduledDates) {
      final clean = dk.trim();
      if (clean.isNotEmpty &&
          !oldSet.contains(clean) &&
          (!skipPast || clean.compareTo(todayKey) >= 0) &&
          MealPlanKeys.parseDayKey(clean) != null) {
        added.add(clean);
      }
    }

    if (added.isEmpty) return 0;
    if (availableRecipes.isEmpty) return 0;

    added.sort();

    mplog.MealPlanLog.i(
      'BACKFILL program=$programId added=${added.length} recipes=${availableRecipes.length} '
      'includeSnacks=$includeSnacks snackCount=$snackCount threshold=$babyThresholdMonths',
      key: 'backfill:$programId',
    );

    _resetReuseTracking();
    _resetLeftovers();

    int created = 0;

    for (final dateKey in added) {
      final docRef = repo.programDayDoc(
        uid: controller.uid,
        programId: programId,
        dateKey: dateKey,
      );

      final snap = await docRef.get();
      if (snap.exists) continue;

      final dt = _parseDateKey(dateKey);

      final daySlots = _buildDaySlots(
        random: random,
        servingDate: dt,
        availableRecipes: availableRecipes,
        includeBreakfast: includeBreakfast,
        includeLunch: includeLunch,
        includeDinner: includeDinner,
        includeSnacks: includeSnacks,
        snackCount: snackCount,
        mealAudiences: aud,
        children: childrenProfile,
        adultCount: adultCount,
        kidCount: kidCount,
        babyThresholdMonths: babyThresholdMonths,
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
  // ONE-OFF (ad-hoc) day only
  // -------------------------------------------------------
  Future<void> buildAdhocDay({
    required String dateKey,
    required List<Map<String, dynamic>> availableRecipes,
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required int snackCount,
    Map<String, String>? mealAudiences,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
    String? title,
    bool overwrite = true,
  }) async {
    final repo = MealPlanRepository(FirebaseFirestore.instance);
    final random = Random();
    final aud = _normalizeMealAudiences(mealAudiences);

    final childrenProfile = controller.childrenEffectiveOrNull;
    final adultCount = controller.adultCount;
    final kidCount = controller.kidCount;

    final cleanDateKey = dateKey.trim();
    if (cleanDateKey.isEmpty) throw Exception('Invalid day key.');
    if (MealPlanKeys.parseDayKey(cleanDateKey) == null) {
      throw Exception('Invalid day key.');
    }
    if (availableRecipes.isEmpty) throw Exception('No recipes available.');

    final docRef = repo.adhocDayDoc(uid: controller.uid, dateKey: cleanDateKey);

    if (!overwrite) {
      final existing = await docRef.get();
      if (existing.exists) return;
    }

    _resetReuseTracking();
    _resetLeftovers();

    final dt = _parseDateKey(cleanDateKey);

    final daySlots = _buildDaySlots(
      random: random,
      servingDate: dt,
      availableRecipes: availableRecipes,
      includeBreakfast: includeBreakfast,
      includeLunch: includeLunch,
      includeDinner: includeDinner,
      includeSnacks: snackCount > 0,
      snackCount: snackCount,
      mealAudiences: aud,
      children: childrenProfile,
      adultCount: adultCount,
      kidCount: kidCount,
      babyThresholdMonths: babyThresholdMonths,
    );

    await repo.upsertAdhocDay(
      uid: controller.uid,
      dateKey: cleanDateKey,
      daySlots: daySlots,
      title: title,
    );
  }

  // -------------------------------------------------------
  // Programs-only: Build + Activate
  // -------------------------------------------------------
  Future<void> buildAndActivate({
    required String title,
    required List<Map<String, dynamic>> availableRecipes,
    required String startDayKey,
    required int weeks,
    required List<int> weekdays,
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required bool includeSnacks,
    required int snackCount,
    Map<String, String>? mealAudiences,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
  }) async {
    final random = Random();
    final repo = MealPlanRepository(FirebaseFirestore.instance);
    final aud = _normalizeMealAudiences(mealAudiences);

    final childrenProfile = controller.childrenEffectiveOrNull;
    final adultCount = controller.adultCount;
    final kidCount = controller.kidCount;

    final cleanTitle = title.trim().isEmpty ? 'My Plan' : title.trim();
    final cleanWeekdays =
        weekdays.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();

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

    _resetReuseTracking();
    _resetLeftovers();

    for (final dateKey in scheduledDates) {
      final dt = _parseDateKey(dateKey);

      final daySlots = _buildDaySlots(
        random: random,
        servingDate: dt,
        availableRecipes: availableRecipes,
        includeBreakfast: includeBreakfast,
        includeLunch: includeLunch,
        includeDinner: includeDinner,
        includeSnacks: includeSnacks,
        snackCount: snackCount,
        mealAudiences: aud,
        children: childrenProfile,
        adultCount: adultCount,
        kidCount: kidCount,
        babyThresholdMonths: babyThresholdMonths,
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

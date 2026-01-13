// lib/meal_plan/builder/meal_plan_builder_service.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/meal_plan_age_engine.dart';
import '../core/meal_plan_controller.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';
import '../core/meal_plan_log.dart' as mplog;

// -------------------------------------------------------
// ✅ Debug toggle
// -------------------------------------------------------
class MealPlanDebug {
  static bool enabled = true; 
  static int sampleIds = 6;

  static void i(String msg, {String? key}) {
    if (!enabled) return;
    mplog.MealPlanLog.i(msg, key: key);
  }

  static void d(String msg, {String? key}) {
    if (!enabled) return;
    mplog.MealPlanLog.d(msg, key: key);
  }

  static void w(String msg, {String? key}) {
    if (!enabled) return;
    mplog.MealPlanLog.w(msg, key: key);
  }

  static void e(String msg, {String? key}) {
    if (!enabled) return;
    mplog.MealPlanLog.e(msg, key: key);
  }
}

// -------------------------------------------------------
// ✅ Leftovers ledger model
// -------------------------------------------------------
class _LeftoverBatch {
  final int recipeId;
  final String audience; 
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

  Future<void> _awaitProfileReadySafe() async {
    try {
      await controller.profileReady.timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } catch (_) {}
  }

  // -------------------------------------------------------
  // Date helpers
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
    required int weeks,
    required List<int> weekdays,
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

    final snackFallback =
        _normalizeAudience(inMap['snack'], fallback: _audKids);
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
  // -------------------------------------------------------
  Map<int, DateTime> _firstUsedDates = {};

  void _noteFirstUseIfMissing(int recipeId, DateTime servingDate) {
    _firstUsedDates.putIfAbsent(recipeId, () => servingDate);
  }

  void _resetReuseTracking() {
    _firstUsedDates = {};
  }

  // -------------------------------------------------------
  // Leftovers ledger
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

    MealPlanDebug.i(
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

    MealPlanDebug.i(
      'LEFTOVER_CREATE recipe=$recipeId audience=$audience cooked=${_toDateKey(cooked)} '
      'made=$itemsMade used=$itemsUsed left=$remaining expires=${_toDateKey(expires)}',
      key: 'leftoverCreate:$recipeId:$audience:${_toDateKey(cooked)}',
    );
  }

  // -------------------------------------------------------
  // ✅ SSOT snapshot helpers
  // -------------------------------------------------------
  int _adultCountSSOT() => max(1, controller.adultCount);

  List<Map<String, dynamic>> _childrenSnapshotSSOT() {
    return controller.childrenEffectiveOrNull
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
  }

  String _kidsLine(List<Map<String, dynamic>> kids, DateTime dt) {
    return kids.map((c) {
      final name = (c['name'] ?? c['childName'] ?? 'child').toString();
      final age = MealPlanAgeEngine.childAgeMonths(c, dt);
      final key = (c['childKey'] ?? c['key'] ?? c['id'] ?? '').toString();
      return '$name($key):${age ?? "?"}m';
    }).join(', ');
  }

  void _logBuilderCtx(
    String where,
    DateTime dt,
    Map<String, String> aud,
    int adults,
    List<Map<String, dynamic>> kids,
  ) {
    MealPlanDebug.i(
      'BUILDER_CTX where=$where day=${_toDateKey(dt)} adults=$adults kids=${kids.length} '
      'kidsAges=[${_kidsLine(kids, dt)}] aud=$aud',
      key: 'builderCtx:$where:${_toDateKey(dt)}',
    );
  }

  // -------------------------------------------------------
  // ✅ Warning helpers
  // -------------------------------------------------------
  String _childKeyFromMap(Map<String, dynamic> c) {
    final v =
        (c['childKey'] ?? c['key'] ?? c['id'] ?? c['uid'] ?? '').toString().trim();
    return v;
  }

  String _childNameFromMap(Map<String, dynamic> c) {
    return (c['name'] ?? c['childName'] ?? '').toString().trim();
  }

  Map<String, dynamic> _attachWarnings(
    Map<String, dynamic> entry,
    List<Map<String, dynamic>> warnings,
  ) {
    if (warnings.isEmpty) return entry;
    final first = warnings.first;
    return <String, dynamic>{
      ...entry,
      'warnings': warnings,
      'warning': first,
    };
  }

  // -------------------------------------------------------
  // ✅ Warning Generation (NOW INCLUDES ALLERGY SWAPS)
  // -------------------------------------------------------
  List<Map<String, dynamic>> _buildWarningsForPick({
    required String slotKey,
    required String audience,
    required int recipeId,
    required List<Map<String, dynamic>> children,
    required DateTime servingDate,
  }) {
    final out = <Map<String, dynamic>>[];

    // ------------------------------------
    // 1. ALLERGY SWAP CHECK
    // ------------------------------------
    // Since the recipe was picked, we know it's either safe OR needs swaps.
    // If it needs swaps, the Controller will tell us via the label.
    final swapLabel = controller.allergySubtitleForRecipeId(recipeId);
    
    if (swapLabel != null && swapLabel.toLowerCase().contains('swap')) {
      out.add({
        'type': 'allergy_swap',
        'slot': slotKey,
        'message': swapLabel, // e.g. "Needs swap (Dairy)"
        'isSwap': true,
        // The UI will see this warning and suppress "Safe for whole family"
      });
    }

    // ------------------------------------
    // 2. AGE SUITABILITY CHECKS (Existing)
    // ------------------------------------
    if (children.isEmpty) return out;

    final ix = controller.indexForId(recipeId);
    if (ix == null) {
      return out;
    }

    final minAge = ix.minAgeMonths;
    final normAudience = audience.trim().toLowerCase();
    
    // Missing Data Check
    if (minAge == null || minAge <= 0) {
      final youngest = MealPlanAgeEngine.youngestChild(children, servingDate);
      if (youngest != null) {
        final name = _childNameFromMap(youngest);
        out.add(_createWarningMap(
          slotKey, 
          youngest, 
          0, 
          messageOverride: 'Check suitability for $name (no age tag)',
        ));
      }
      return out;
    }

    // Age Logic
    if (normAudience == _audKids) {
      final youngest = MealPlanAgeEngine.youngestChild(children, servingDate);
      if (youngest != null) {
        final target = MealPlanAgeEngine.targetChildForKidsAudience(children, servingDate);
        final youngestKey = _childKeyFromMap(youngest);
        final targetKey = target != null ? _childKeyFromMap(target) : '';

        // Only warn if youngest is NOT the target we picked for
        if (youngestKey != targetKey) {
          final age = MealPlanAgeEngine.childAgeMonths(youngest, servingDate);
          if (age != null && minAge > age) {
             out.add(_createWarningMap(slotKey, youngest, minAge));
          }
        }
      }
    } else {
      // Family
      for (final child in children) {
        final age = MealPlanAgeEngine.childAgeMonths(child, servingDate);
        if (age != null && minAge > age) {
          out.add(_createWarningMap(slotKey, child, minAge));
        }
      }
    }

    return out;
  }

  Map<String, dynamic> _createWarningMap(
    String slot, 
    Map<String, dynamic> child, 
    int minAge, 
    {String? messageOverride}
  ) {
    final name = _childNameFromMap(child);
    return {
      'type': 'not_suitable_for_child',
      'slot': slot,
      'childKey': _childKeyFromMap(child),
      'childName': name,
      'minAgeMonths': minAge,
      'message': messageOverride ?? 'Not suitable for $name yet', 
    };
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
    required List<Map<String, dynamic>> childrenSSOT,
    required int adultCount,
    required int kidCount,
    int babyThresholdMonths =
        MealPlanAgeEngine.defaultBabyThresholdMonths,
  }) {
    final normAudience = audience.trim().toLowerCase();

    var candidates = controller.getCandidatesForSlotUnified(
      slot,
      availableRecipes,
      audience: normAudience,
      servingDate: servingDate,
      firstUsedDates: _firstUsedDates,
      babyThresholdMonths: babyThresholdMonths,
      childrenOverride: childrenSSOT,
    );

    if (candidates.isEmpty) {
      return <String, dynamic>{
        'type': 'clear',
        'source': 'auto-builder',
        'audience': normAudience,
        'reason': 'no_candidates',
      };
    }

    if (normAudience == _audKids && childrenSSOT.length > 1) {
      final youngest = MealPlanAgeEngine.youngestChild(childrenSSOT, servingDate);
      final target = MealPlanAgeEngine.targetChildForKidsAudience(childrenSSOT, servingDate);
      final youngestKey = youngest != null ? _childKeyFromMap(youngest) : '';
      final targetKey = target != null ? _childKeyFromMap(target) : '';

      if (youngest != null && youngestKey != targetKey) {
        final youngestAge = MealPlanAgeEngine.childAgeMonths(youngest, servingDate);
        if (youngestAge != null) {
          final safeForBaby = candidates.where((id) {
            final ix = controller.indexForId(id);
            if (ix == null) return false;
            final minAge = ix.minAgeMonths;
            if (minAge == null || minAge <= 0) return false;
            return minAge <= youngestAge;
          }).toList();

          if (safeForBaby.isNotEmpty) {
             candidates = safeForBaby;
          }
        }
      }
    }

    final pickedId = candidates[random.nextInt(candidates.length)];
    _noteFirstUseIfMissing(pickedId, servingDate);

    Map<String, dynamic> entry;

    final full = _findRecipeById(availableRecipes, pickedId);
    if (full != null && _extractServingMode(full) == _servingModeItem) {
      final storageDays = controller.extractStorageDays(full) ?? 0;
      if (storageDays > 0) {
        final itemsNeeded = _itemsNeededForSlotDay(
          recipe: full,
          audience: normAudience,
          adultCount: adultCount,
          kidCount: kidCount,
        );

        final leftoverEntry = _tryUseLeftoversForRecipe(
          recipeId: pickedId,
          audience: normAudience,
          servingDate: servingDate,
          itemsNeeded: itemsNeeded,
        );

        if (leftoverEntry != null) {
          entry = leftoverEntry;
        } else {
          final made = _itemsMadeBase(full);
          _createLeftoversIfAny(
            recipeId: pickedId,
            audience: normAudience,
            servingDate: servingDate,
            itemsMade: made,
            itemsUsed: itemsNeeded,
            storageDays: storageDays,
          );

          entry = <String, dynamic>{
            'type': 'recipe',
            'recipeId': pickedId,
            'source': 'auto-builder',
            'audience': normAudience,
            'itemsMade': made,
            'itemsUsed': itemsNeeded,
            'storageDays': storageDays,
          };
        }
      } else {
        entry = <String, dynamic>{
          'type': 'recipe',
          'recipeId': pickedId,
          'source': 'auto-builder',
          'audience': normAudience,
        };
      }
    } else {
      entry = <String, dynamic>{
        'type': 'recipe',
        'recipeId': pickedId,
        'source': 'auto-builder',
        'audience': normAudience,
      };
    }

    final warnings = _buildWarningsForPick(
      slotKey: slot,
      audience: normAudience,
      recipeId: pickedId,
      children: childrenSSOT,
      servingDate: servingDate,
    );

    return _attachWarnings(entry, warnings);
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
    required List<Map<String, dynamic>> childrenSSOT,
    required int adultCount,
    required int kidCount,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
  }) {
    final slots = <String, dynamic>{};

    final aBreakfast = mealAudiences['breakfast'] ?? _audFamily;
    final aLunch = mealAudiences['lunch'] ?? _audFamily;
    final aDinner = mealAudiences['dinner'] ?? _audFamily;
    final aSnack1 = mealAudiences['snack1'] ?? (mealAudiences['snack'] ?? _audKids);
    final aSnack2 = mealAudiences['snack2'] ?? (mealAudiences['snack'] ?? _audKids);

    slots['breakfast'] = includeBreakfast
        ? _pick(
            random,
            'breakfast',
            servingDate,
            availableRecipes,
            audience: aBreakfast,
            childrenSSOT: childrenSSOT,
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
            childrenSSOT: childrenSSOT,
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
            childrenSSOT: childrenSSOT,
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
            childrenSSOT: childrenSSOT,
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
            childrenSSOT: childrenSSOT,
            adultCount: adultCount,
            kidCount: kidCount,
            babyThresholdMonths: babyThresholdMonths,
          )
        : {'type': 'clear', 'source': 'auto-builder', 'reason': 'disabled'};

    return slots;
  }

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

    await _awaitProfileReadySafe();

    final childrenSSOT = _childrenSnapshotSSOT();
    final adultCount = _adultCountSSOT();
    final kidCount = childrenSSOT.length;

    final oldSet =
        oldScheduledDates.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
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

    MealPlanDebug.i(
      'BACKFILL program=$programId added=${added.length} recipes=${availableRecipes.length}',
      key: 'backfill:$programId',
    );

    _resetReuseTracking();
    _resetLeftovers();

    int created = 0;

    for (final dateKey in added) {
      final docRef =
          repo.programDayDoc(uid: controller.uid, programId: programId, dateKey: dateKey);

      final snap = await docRef.get();
      if (snap.exists) continue;

      final dt = _parseDateKey(dateKey);

      _logBuilderCtx('backfill', dt, aud, adultCount, childrenSSOT);

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
        childrenSSOT: childrenSSOT,
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

    await _awaitProfileReadySafe();

    final childrenSSOT = _childrenSnapshotSSOT();
    final adultCount = _adultCountSSOT();
    final kidCount = childrenSSOT.length;

    final cleanDateKey = dateKey.trim();
    if (cleanDateKey.isEmpty) throw Exception('Invalid day key.');
    if (MealPlanKeys.parseDayKey(cleanDateKey) == null) {
      throw Exception('Invalid day key.');
    }
    if (availableRecipes.isEmpty) throw Exception('No recipes available.');

    MealPlanDebug.i(
      'ADHOC_BUILD day=$cleanDateKey recipes=${availableRecipes.length} snackCount=$snackCount',
      key: 'adhocBuild:$cleanDateKey',
    );

    final docRef = repo.adhocDayDoc(uid: controller.uid, dateKey: cleanDateKey);

    if (!overwrite) {
      final existing = await docRef.get();
      if (existing.exists) return;
    }

    _resetReuseTracking();
    _resetLeftovers();

    final dt = _parseDateKey(cleanDateKey);

    _logBuilderCtx('adhoc', dt, aud, adultCount, childrenSSOT);

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
      childrenSSOT: childrenSSOT,
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
    MealPlanDebug.i(
      'BUILD_START title="${title.trim()}" start=$startDayKey weeks=$weeks weekdays=$weekdays '
      'includeB=$includeBreakfast includeL=$includeLunch includeD=$includeDinner '
      'includeSnacks=$includeSnacks snackCount=$snackCount recipes=${availableRecipes.length}',
      key: 'buildStart:$startDayKey',
    );

    final random = Random();
    final repo = MealPlanRepository(FirebaseFirestore.instance);
    final aud = _normalizeMealAudiences(mealAudiences);

    await _awaitProfileReadySafe();

    final childrenSSOT = _childrenSnapshotSSOT();
    final adultCount = _adultCountSSOT();
    final kidCount = childrenSSOT.length;

    final cleanTitle = title.trim().isEmpty ? 'My Plan' : title.trim();
    final cleanWeekdays =
        weekdays.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
    if (cleanWeekdays.isEmpty) throw Exception('Please select at least one weekday.');

    final startDateKey = startDayKey.trim();
    final scheduledDates = _buildScheduledDates(
      startDateKey: startDateKey,
      weeks: weeks,
      weekdays: cleanWeekdays,
    );

    if (scheduledDates.isEmpty) throw Exception('No planned days found for that schedule.');

    _logBuilderCtx('program:create', _parseDateKey(startDateKey), aud, adultCount, childrenSSOT);

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final dateKey in scheduledDates) {
        final adhocRef = repo.adhocDayDoc(uid: controller.uid, dateKey: dateKey);
        batch.delete(adhocRef);
      }
      await batch.commit();
      MealPlanDebug.i('ADHOC_CLEANUP cleaned ${scheduledDates.length} days', key: 'adhocCleanup');
    } catch (e) {
      MealPlanDebug.e('ADHOC_CLEANUP_FAIL $e');
    }

    final endDateKey = _computeEndDateKey(startDateKey: startDateKey, weeks: weeks);

    final programId = await repo.createProgram(
      uid: controller.uid,
      name: cleanTitle,
      startDateKey: startDateKey,
      endDateKey: endDateKey,
      weeks: weeks.clamp(1, 4),
      weekdays: cleanWeekdays,
      scheduledDates: scheduledDates,
      adults: adultCount,
      kids: kidCount,
      childrenSnapshot: childrenSSOT,
    );

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
        childrenSSOT: childrenSSOT,
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

    await repo.setActiveProgramId(uid: controller.uid, programId: programId);
  }
}
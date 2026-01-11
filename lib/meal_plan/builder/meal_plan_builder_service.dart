// lib/meal_plan/builder/meal_plan_builder_service.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/meal_plan_age_engine.dart';
import '../core/meal_plan_controller.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';
import '../core/meal_plan_log.dart' as mplog;

// -------------------------------------------------------
// ✅ Leftovers ledger model (top-level; Dart forbids nested classes)
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
  // Batch cooking reuse tracking (existing)
  // -------------------------------------------------------
  // recipeId -> first served date (DateTime)
  Map<int, DateTime> _firstUsedDates = {};

  void _noteFirstUseIfMissing(int recipeId, DateTime servingDate) {
    _firstUsedDates.putIfAbsent(recipeId, () => servingDate);
  }

  void _resetReuseTracking() {
    _firstUsedDates = {};
  }

  // -------------------------------------------------------
  // ✅ Leftovers ledger (ITEM serving_mode only)
  // -------------------------------------------------------
  static const String _servingModeItem = 'item';

  final List<_LeftoverBatch> _leftovers = <_LeftoverBatch>[];

  void _resetLeftovers() {
    _leftovers.clear();
  }

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

  // Household counts
  Future<int> _loadAdultCount() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(controller.uid)
          .get();
      final d = snap.data();
      final v = d?['adultCount'] ?? d?['adults'] ?? d?['householdAdults'];
      if (v is int) return max(1, v);
      final parsed = int.tryParse(v?.toString().trim() ?? '');
      return max(1, parsed ?? 2);
    } catch (_) {
      return 2;
    }
  }

  int _kidCountFromChildren(List<dynamic>? children) {
    if (children == null) return 0;
    return children.where((c) => c is Map).length;
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
  // ✅ Child profile loading (program children only had childKey)
  // -------------------------------------------------------
  bool _childrenHaveDob(List<dynamic>? children) {
    if (children == null) return false;
    for (final c in children) {
      if (c is! Map) continue;
      final hasDobYear = c['dobYear'] is int;
      final hasDobMonth = c['dobMonth'] is int;
      if (hasDobYear && hasDobMonth) return true;

      final raw = c['birthDate'] ??
          c['birthdate'] ??
          c['dob'] ??
          c['dateOfBirth'] ??
          c['date_of_birth'];
      if (raw != null) return true;
    }
    return false;
  }

  Future<List<dynamic>?> _resolveChildrenProfile(List<dynamic>? children) async {
    if (_childrenHaveDob(children)) return children;

    final fs = FirebaseFirestore.instance;
    final uid = controller.uid;

    // 0) users/{uid}
    try {
      final userSnap = await fs.collection('users').doc(uid).get();
      final data = userSnap.data();
      final c = data?['children'];
      if (c is List && _childrenHaveDob(c)) return c;
    } catch (_) {}

    // 2) mealPlan/settings
    try {
      final settingsSnap =
          await fs.collection('users').doc(uid).collection('mealPlan').doc(
                'settings',
              ).get();

      final data = settingsSnap.data();
      final c = data?['children'];
      if (c is List && _childrenHaveDob(c)) return c;
    } catch (_) {}

    // 3) mealPlansWeeks/{currentWeekId}
    try {
      final weekId = MealPlanKeys.currentWeekId();
      final weekSnap =
          await fs.collection('users').doc(uid).collection('mealPlansWeeks').doc(
                weekId,
              ).get();

      final data = weekSnap.data();
      final c = data?['children'];
      if (c is List && _childrenHaveDob(c)) return c;
    } catch (_) {}

    return children;
  }

  Future<void> _persistChildrenSnapshotToProgram({
    required String programId,
    required List<dynamic>? children,
  }) async {
    if (children == null || children.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(controller.uid)
          .collection('mealPrograms')
          .doc(programId)
          .set(
        {'children': children},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  // -------------------------------------------------------
  // Baby snack rule (first foods)
  // -------------------------------------------------------
  bool _isSnackSlot(String slot) =>
      slot == 'snack' || slot == 'snack1' || slot == 'snack2';

  int _ageInMonthsLocal({
    required int dobYear,
    required int dobMonth,
    required DateTime onDate,
  }) {
    return (onDate.year - dobYear) * 12 + (onDate.month - dobMonth);
  }

  ({int year, int month})? _extractDobYearMonth(Map c) {
    final y = c['dobYear'];
    final m = c['dobMonth'];
    if (y is int && m is int && m >= 1 && m <= 12) return (year: y, month: m);

    final y2 = c['dob_year'];
    final m2 = c['dob_month'];
    if (y2 is int && m2 is int && m2 >= 1 && m2 <= 12) return (year: y2, month: m2);

    final raw = c['birthDate'] ??
        c['birthdate'] ??
        c['dob'] ??
        c['dateOfBirth'] ??
        c['date_of_birth'];

    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    if (raw is DateTime) dt = raw;
    if (raw is String) {
      try {
        dt = DateTime.parse(raw.length == 7 ? '$raw-01' : raw);
      } catch (_) {
        dt = null;
      }
    }
    if (raw is Map) {
      final ry = raw['year'];
      final rm = raw['month'];
      if (ry is int && rm is int && rm >= 1 && rm <= 12) {
        return (year: ry, month: rm);
      }
    }

    if (dt == null) return null;
    return (year: dt.year, month: dt.month);
  }

  String? _extractChildKey(Map c) {
    final v = (c['childKey'] ?? c['id'] ?? c['key'] ?? c['uid'] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }

  String _extractChildName(Map c) =>
      (c['name'] ?? c['childName'] ?? '').toString().trim();

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

      final childKey = _extractChildKey(c);
      if (childKey == null) continue;

      final dob = _extractDobYearMonth(c);
      if (dob == null) continue;

      final ageMonths = _ageInMonthsLocal(
        dobYear: dob.year,
        dobMonth: dob.month,
        onDate: servingDate,
      );

      if (bestAgeMonths == null || ageMonths < bestAgeMonths!) {
        bestAgeMonths = ageMonths;
        bestChildKey = childKey;
        bestChildName = _extractChildName(c);
      }
    }

    if (bestAgeMonths == null || bestChildKey == null) return null;

    if (bestAgeMonths! < babyThresholdMonths) {
      return (childKey: bestChildKey, childName: bestChildName);
    }
    return null;
  }

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

  // -------------------------------------------------------
  // Slot generation helpers
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

    if (baby != null && isSnack) {
      mplog.MealPlanLog.i(
        'PICK_BABY_SNACK slot=$slot audience=$audience day=${_toDateKey(servingDate)} '
        'youngestChild=${baby.childName}(${baby.childKey}) threshold=$babyThresholdMonths',
        key: 'pickBabySnack:$slot:${_toDateKey(servingDate)}',
      );

      final candidates = controller.getCandidatesForSlot(
        slot,
        availableRecipes,
        audience: audience,
        servingDate: servingDate,
        firstUsedDates: _firstUsedDates,
        babyThresholdMonths: babyThresholdMonths,
        children: children,
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

      return _firstFoodsSnackEntry(
        childKey: baby.childKey,
        childName: baby.childName,
        audience: audience,
      );
    }

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

    final candidates = controller.getCandidatesForSlot(
      slot,
      availableRecipes,
      audience: audience,
      servingDate: servingDate,
      firstUsedDates: _firstUsedDates,
      babyThresholdMonths: babyThresholdMonths,
      children: children,
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
  // ✅ Backfill new program-day docs when schedule changes
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
    List<dynamic>? children,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
  }) async {
    final repo = MealPlanRepository(FirebaseFirestore.instance);
    final random = Random();
    final aud = _normalizeMealAudiences(mealAudiences);

    final childrenProfile = await _resolveChildrenProfile(children);
    final adultCount = await _loadAdultCount();
    final kidCount = _kidCountFromChildren(childrenProfile);

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

      final slots = (daySlots['slots'] is Map)
          ? Map<String, dynamic>.from(daySlots['slots'] as Map)
          : daySlots;

      final typeCounts = <String, int>{};
      for (final v in slots.values) {
        if (v is Map) {
          final t = (v['type'] ?? 'unknown').toString();
          typeCounts[t] = (typeCounts[t] ?? 0) + 1;
        }
      }

      mplog.MealPlanLog.i(
        'BACKFILL_WRITE program=$programId day=$dateKey types=$typeCounts',
        key: 'backfillWrite:$programId:$dateKey',
      );

      created++;
    }

    await _persistChildrenSnapshotToProgram(
      programId: programId,
      children: childrenProfile,
    );

    return created;
  }

  // -------------------------------------------------------
  // ✅ ONE-OFF (ad-hoc) day only (NO program activation)
  // -------------------------------------------------------
  Future<void> buildAdhocDay({
    required String dateKey,
    required List<Map<String, dynamic>> availableRecipes,
    required bool includeBreakfast,
    required bool includeLunch,
    required bool includeDinner,
    required int snackCount,
    Map<String, String>? mealAudiences,
    List<dynamic>? children,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
    String? title,
    bool overwrite = true,
  }) async {
    final repo = MealPlanRepository(FirebaseFirestore.instance);
    final random = Random();
    final aud = _normalizeMealAudiences(mealAudiences);

    final childrenProfile = await _resolveChildrenProfile(children);
    final adultCount = await _loadAdultCount();
    final kidCount = _kidCountFromChildren(childrenProfile);

    final cleanDateKey = dateKey.trim();
    if (cleanDateKey.isEmpty) throw Exception('Invalid day key.');
    if (MealPlanKeys.parseDayKey(cleanDateKey) == null) {
      throw Exception('Invalid day key.');
    }
    if (availableRecipes.isEmpty) throw Exception('No recipes available.');

    mplog.MealPlanLog.i(
      'ADHOC_BUILD day=$cleanDateKey recipes=${availableRecipes.length} snackCount=$snackCount threshold=$babyThresholdMonths',
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

    final slots = (daySlots['slots'] is Map)
        ? Map<String, dynamic>.from(daySlots['slots'] as Map)
        : daySlots;

    final typeCounts = <String, int>{};
    for (final v in slots.values) {
      if (v is Map) {
        final t = (v['type'] ?? 'unknown').toString();
        typeCounts[t] = (typeCounts[t] ?? 0) + 1;
      }
    }

    mplog.MealPlanLog.i(
      'ADHOC_WRITE day=$cleanDateKey types=$typeCounts',
      key: 'adhocWrite:$cleanDateKey',
    );
  }

  // -------------------------------------------------------
  // ✅ Programs-only: Build + Activate
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
    List<dynamic>? children,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
  }) async {
    mplog.MealPlanLog.i(
      'BUILD_START title="${title.trim()}" start=$startDayKey weeks=$weeks weekdays=$weekdays '
      'includeB=$includeBreakfast includeL=$includeLunch includeD=$includeDinner '
      'includeSnacks=$includeSnacks snackCount=$snackCount threshold=$babyThresholdMonths recipes=${availableRecipes.length}',
      key: 'buildStart:$startDayKey',
    );

    final random = Random();
    final repo = MealPlanRepository(FirebaseFirestore.instance);
    final aud = _normalizeMealAudiences(mealAudiences);

    mplog.MealPlanLog.i(
      'MEAL_AUDIENCES normalized=$aud raw=${mealAudiences ?? {}}',
      key: 'mealAudiences:$startDayKey',
    );

    final childrenProfile = await _resolveChildrenProfile(children);
    final adultCount = await _loadAdultCount();
    final kidCount = _kidCountFromChildren(childrenProfile);

    final ffHeuristic = availableRecipes.where((r) {
      final s = r.toString().toLowerCase();
      return s.contains('first-foods') ||
          s.contains('first foods') ||
          s.contains('first_foods');
    }).length;

    mplog.MealPlanLog.d(
      'RECIPE_POOL total=${availableRecipes.length} firstFoodsHeuristic=$ffHeuristic '
      'includeSnacks=$includeSnacks snackCount=$snackCount threshold=$babyThresholdMonths',
      key: 'recipePool:$startDayKey',
    );

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

    mplog.MealPlanLog.i(
      'PROGRAM_CREATED id=$programId title="$cleanTitle" start=$startDateKey end=$endDateKey '
      'scheduled=${scheduledDates.length} weekdays=$cleanWeekdays includeSnacks=$includeSnacks snackCount=$snackCount',
      key: 'programCreated:$programId',
    );

    await _persistChildrenSnapshotToProgram(
      programId: programId,
      children: childrenProfile,
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

      final slots = (daySlots['slots'] is Map)
          ? Map<String, dynamic>.from(daySlots['slots'] as Map)
          : daySlots;

      final typeCounts = <String, int>{};
      for (final v in slots.values) {
        if (v is Map) {
          final t = (v['type'] ?? 'unknown').toString();
          typeCounts[t] = (typeCounts[t] ?? 0) + 1;
        }
      }

      mplog.MealPlanLog.i(
        'PROGRAM_WRITE program=$programId day=$dateKey types=$typeCounts',
        key: 'programWrite:$programId:$dateKey',
      );
    }

    mplog.MealPlanLog.i(
      'BUILD_DONE program=$programId daysWritten=${scheduledDates.length}',
      key: 'buildDone:$programId',
    );
  }
}

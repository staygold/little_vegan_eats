import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'allergy_keys.dart';
import 'meal_plan_keys.dart';
import 'meal_plan_repository.dart';
import 'meal_plan_slots.dart';
import '../../recipes/allergy_engine.dart';

class MealPlanController extends ChangeNotifier {
  MealPlanController({
    required FirebaseAuth auth,
    required MealPlanRepository repo,
    String? initialWeekId,
  })  : _auth = auth,
        _repo = repo,
        weekId = (initialWeekId != null && initialWeekId.trim().isNotEmpty)
            ? initialWeekId.trim()
            : MealPlanKeys.currentWeekId();

  final FirebaseAuth _auth;
  final MealPlanRepository _repo;

  String weekId;
  Map<String, dynamic>? weekData;

  /// Draft edits: dayKey -> slot -> entryMap
  final Map<String, Map<String, Map<String, dynamic>>> _draft = {};

  StreamSubscription<Map<String, dynamic>?>? _sub;

  bool _populateInFlight = false;
  String? _lastPopulatedWeekId;

  // -------------------------------------------------------
  // Allergies (profile-driven)
  // -------------------------------------------------------

  Set<String> _excludedAllergens = {};
  Set<String> _childAllergens = {};

  Set<String> get excludedAllergens => _excludedAllergens;
  Set<String> get childAllergens => _childAllergens;

  void setAllergySets({
    required Set<String> excludedAllergens,
    required Set<String> childAllergens,
  }) {
    _excludedAllergens = excludedAllergens;
    _childAllergens = childAllergens;
    notifyListeners(); // important for card refresh
  }

  // -------------------------------------------------------
  // Ingredient text (MATCHES recipe list)
  // -------------------------------------------------------

  String _ingredientsTextOf(Map<String, dynamic> recipe) {
    final recipeData = recipe['recipe'];
    if (recipeData is! Map<String, dynamic>) return '';

    final flat = recipeData['ingredients_flat'];
    if (flat is! List) return '';

    final buf = StringBuffer();
    for (final row in flat) {
      if (row is! Map) continue;
      buf.write('${row['name'] ?? ''} ');
      buf.write('${row['notes'] ?? ''} ');
    }

    return buf.toString().trim();
  }

  // -------------------------------------------------------
  // Allergy engine helpers (NO NEW TYPES / NO swapAvailable enum)
  // -------------------------------------------------------

  /// Returns the raw engine response (dynamic) or null if we should "fail open".
  dynamic evaluateRecipe(
    Map<String, dynamic> recipe, {
    required bool includeSwapRecipes,
  }) {
    if (_excludedAllergens.isEmpty && _childAllergens.isEmpty) return null;

    final ingredientsText = _ingredientsTextOf(recipe);
    if (ingredientsText.isEmpty) return null;

    final allAllergies = <String>{
      ..._excludedAllergens,
      ..._childAllergens,
    };

    return AllergyEngine.evaluateRecipe(
      ingredientsText: ingredientsText,
      childAllergies: allAllergies.toList(),
      includeSwapRecipes: includeSwapRecipes,
    );
  }

  /// ✅ Safe-only (this is what your meal plan generation + inspire pool uses)
  bool recipeAllowed(Map<String, dynamic> recipe) {
    if (_excludedAllergens.isEmpty && _childAllergens.isEmpty) return true;

    final ingredientsText = _ingredientsTextOf(recipe);
    if (ingredientsText.isEmpty) return true;

    final allAllergies = <String>{
      ..._excludedAllergens,
      ..._childAllergens,
    };

    final res = AllergyEngine.evaluateRecipe(
      ingredientsText: ingredientsText,
      childAllergies: allAllergies.toList(),
      includeSwapRecipes: false, // ✅ SAFE ONLY
    );

    return res.status == AllergyStatus.safe;
  }

  /// ✅ “Swap available” style signal for Meal Plan UI
  /// (works even though your AllergyStatus enum does NOT have swapAvailable)
  bool recipeHasSwap(Map<String, dynamic> recipe) {
    // No allergies set -> nothing to swap for
    if (_excludedAllergens.isEmpty && _childAllergens.isEmpty) return false;

    final res = evaluateRecipe(recipe, includeSwapRecipes: true);
    if (res == null) return false;

    // If it's safe, we don't treat it as "needs swap"
    try {
      final st = (res as dynamic).status;
      if (st == AllergyStatus.safe) return false;
    } catch (_) {
      // ignore
    }

    // 1) Status might be a string/enum containing "swap"
    try {
      final st = (res as dynamic).status;
      final s = st?.toString().toLowerCase() ?? '';
      if (s.contains('swap')) return true;
    } catch (_) {
      // ignore
    }

    // 2) Engine might return explicit lists of swaps/suggestions
    bool hasNonEmptyList(dynamic v) =>
        v is List && v.where((e) => e != null).isNotEmpty;

    try {
      final v = (res as dynamic).swapRecipes;
      if (hasNonEmptyList(v)) return true;
    } catch (_) {}

    try {
      final v = (res as dynamic).swaps;
      if (hasNonEmptyList(v)) return true;
    } catch (_) {}

    try {
      final v = (res as dynamic).suggestions;
      if (hasNonEmptyList(v)) return true;
    } catch (_) {}

    try {
      final v = (res as dynamic).swapSuggestions;
      if (hasNonEmptyList(v)) return true;
    } catch (_) {}

    return false;
  }

  // -------------------------------------------------------
  // Auth
  // -------------------------------------------------------

  String get uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError('User not logged in');
    return u.uid;
  }

  // -------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------

  void start() {
    _sub?.cancel();
    _sub = _repo.watchWeek(uid: uid, weekId: weekId).listen((data) {
      weekData = data;
      notifyListeners();
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> ensureWeek() async {
    await _repo.ensureWeekExists(uid: uid, weekId: weekId);
  }

  Future<void> setWeek(String newWeekId) async {
    final cleaned = newWeekId.trim();
    if (cleaned.isEmpty || cleaned == weekId) return;

    weekId = cleaned;
    weekData = null;
    _draft.clear();
    _lastPopulatedWeekId = null;

    notifyListeners();
    start();
    await ensureWeek();
  }

  List<String> dayKeysForWeek() => MealPlanKeys.weekDayKeys(weekId);

  // -------------------------------------------------------
  // Helpers
  // -------------------------------------------------------

  int? recipeIdFromAny(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  // -------------------------------------------------------
  // Entry parsing
  // -------------------------------------------------------

  static Map<String, dynamic>? _parseEntry(dynamic raw) {
    if (raw is int) {
      return {'type': 'recipe', 'recipeId': raw, 'source': 'auto'};
    }
    if (raw is num) {
      return {'type': 'recipe', 'recipeId': raw.toInt(), 'source': 'auto'};
    }

    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final type = (m['type'] ?? '').toString();

      if (type == 'note') {
        final text = (m['text'] ?? '').toString().trim();
        if (text.isEmpty) return null;
        return {'type': 'note', 'text': text};
      }

      if (type == 'recipe') {
        final rid = m['recipeId'];
        final recipeId =
            (rid is int) ? rid : (rid is num ? rid.toInt() : null);
        if (recipeId == null) return null;
        return {
          'type': 'recipe',
          'recipeId': recipeId,
          'source': (m['source'] ?? 'auto').toString(),
        };
      }
    }

    return null;
  }

  Map<String, dynamic>? firestoreEntry(String dayKey, String slot) {
    final data = weekData;
    if (data == null) return null;
    final day = MealPlanRepository.dayMapFromWeek(data, dayKey);
    if (day == null) return null;
    return _parseEntry(day[slot]);
  }

  Map<String, dynamic>? draftEntry(String dayKey, String slot) {
    return _draft[dayKey]?[slot];
  }

  Map<String, dynamic>? effectiveEntry(String dayKey, String slot) {
    return draftEntry(dayKey, slot) ?? firestoreEntry(dayKey, slot);
  }

  bool entryIsRecipe(Map<String, dynamic>? e) => e?['type'] == 'recipe';
  bool entryIsNote(Map<String, dynamic>? e) => e?['type'] == 'note';

  int? entryRecipeId(Map<String, dynamic>? e) {
    if (e == null) return null;
    if (e['type'] != 'recipe') return null;
    final rid = e['recipeId'];
    if (rid is int) return rid;
    if (rid is num) return rid.toInt();
    return null;
  }

  String? entryNoteText(Map<String, dynamic>? e) {
    if (e == null) return null;
    if (e['type'] != 'note') return null;
    final t = (e['text'] ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  // -------------------------------------------------------
  // Draft editing
  // -------------------------------------------------------

  void setDraftRecipe(
    String dayKey,
    String slot,
    int recipeId, {
    String source = 'manual',
  }) {
    final dayDraft = _draft.putIfAbsent(dayKey, () => {});
    dayDraft[slot] = {'type': 'recipe', 'recipeId': recipeId, 'source': source};
    notifyListeners();
  }

  void setDraftNote(String dayKey, String slot, String text) {
    final dayDraft = _draft.putIfAbsent(dayKey, () => {});
    dayDraft[slot] = {'type': 'note', 'text': text.trim()};
    notifyListeners();
  }

  bool hasDraftChanges(String dayKey) {
    final d = _draft[dayKey];
    if (d == null || d.isEmpty) return false;
    final data = weekData;
    if (data == null) return true;

    for (final e in d.entries) {
      final current = firestoreEntry(dayKey, e.key);
      if (!_entryEquals(current, e.value)) return true;
    }
    return false;
  }

  bool _entryEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a['type'] != b['type']) return false;

    if (a['type'] == 'recipe') {
      return entryRecipeId(a) == entryRecipeId(b) &&
          (a['source'] ?? '') == (b['source'] ?? '');
    }
    if (a['type'] == 'note') {
      return entryNoteText(a) == entryNoteText(b);
    }
    return false;
  }

  Future<void> saveDay(String dayKey) async {
    final dayDraft = _draft[dayKey];
    if (dayDraft == null || dayDraft.isEmpty) return;

    final existing =
        MealPlanRepository.dayMapFromWeek(weekData ?? {}, dayKey) ?? {};

    await _repo.saveDay(
      uid: uid,
      weekId: weekId,
      dayKey: dayKey,
      daySlots: {...existing, ...dayDraft},
    );

    _draft.remove(dayKey);
    notifyListeners();
  }

  int? pickDifferentId({
    required List<int> availableIds,
    required int? currentId,
  }) {
    if (availableIds.isEmpty) return null;
    if (availableIds.length == 1) return availableIds.first;

    final idx = currentId == null ? -1 : availableIds.indexOf(currentId);
    final start = idx < 0 ? 0 : (idx + 1) % availableIds.length;

    for (int step = 0; step < availableIds.length; step++) {
      final c = availableIds[(start + step) % availableIds.length];
      if (c != currentId) return c;
    }
    return null;
  }

  // -------------------------------------------------------
  // Generator (hybrid: uses "course" when available)
  // -------------------------------------------------------

  Future<void> ensurePlanPopulated({
    required List<Map<String, dynamic>> recipes,
  }) async {
    if (_populateInFlight) return;
    if (_lastPopulatedWeekId == weekId) return;

    await ensureWeek();

    // Ensure we have latest week data so we don't overwrite changes
    Map<String, dynamic> data;
    if (weekData != null) {
      data = weekData!;
    } else {
      final loaded = await _repo.loadWeek(uid: uid, weekId: weekId);
      data = loaded ?? <String, dynamic>{};
      weekData = data;
      notifyListeners();
    }

    final existingDays =
        data['days'] is Map ? (data['days'] as Map) : const {};

    // SAFE pool (respect allergies) - safe only
    final allIds = <int>[];
    for (final r in recipes) {
      if (!recipeAllowed(r)) continue;
      final id = recipeIdFromAny(r['id']);
      if (id != null) allIds.add(id);
    }
    if (allIds.isEmpty) return;

    // Buckets must be built from SAFE recipes too
    final safeRecipes = recipes.where(recipeAllowed).toList();
    final buckets = _buildSlotBucketsFromCourse(safeRecipes);

    final rng = Random(weekId.hashCode);

    final used = <int>{};
    final toUpsert = <String, Map<String, dynamic>>{};

    final dayKeys = MealPlanKeys.weekDayKeys(weekId);

    _populateInFlight = true;
    try {
      for (final dayKey in dayKeys) {
        Map<String, dynamic> existingDay = {};
        final rawExisting = existingDays[dayKey];
        if (rawExisting is Map) {
          existingDay = Map<String, dynamic>.from(rawExisting);
        }

        final updatedDay = <String, dynamic>{...existingDay};
        bool changed = false;

        for (final slot in MealPlanSlots.order) {
          // Respect existing Firestore entry (recipe OR note)
          final existingEntry = _parseEntry(existingDay[slot]);
          if (existingEntry != null) {
            final rid = entryRecipeId(existingEntry);
            if (rid != null) used.add(rid);
            continue;
          }

          // Respect draft
          final d = _draft[dayKey]?[slot];
          if (d != null) {
            final rid = entryRecipeId(d);
            if (rid != null) used.add(rid);
            continue;
          }

          final candidates = buckets[slot];
          final picked = _pickId(
            rng: rng,
            preferred: candidates ?? const [],
            fallback: allIds,
            avoid: used,
          );

          if (picked != null) {
            updatedDay[slot] = {
              'type': 'recipe',
              'recipeId': picked,
              'source': 'auto',
            };
            used.add(picked);
            changed = true;
          }
        }

        if (changed) toUpsert[dayKey] = updatedDay;
      }

      if (toUpsert.isNotEmpty) {
        await _repo.upsertDays(uid: uid, weekId: weekId, days: toUpsert);
      }

      _lastPopulatedWeekId = weekId;
    } finally {
      _populateInFlight = false;
    }
  }

  Map<String, List<int>> _buildSlotBucketsFromCourse(
    List<Map<String, dynamic>> recipes,
  ) {
    const breakfastKeys = {'breakfast', 'brunch'};
    const snackKeys = {'snack', 'snacks'};
    const lunchKeys = {'lunch'};
    const dinnerKeys = {'dinner', 'main', 'mains', 'entree', 'entrée', 'supper'};

    final out = <String, List<int>>{
      'breakfast': <int>[],
      'snack1': <int>[],
      'lunch': <int>[],
      'snack2': <int>[],
      'dinner': <int>[],
    };

    for (final r in recipes) {
      final id = recipeIdFromAny(r['id']);
      if (id == null) continue;

      final course = _extractCourse(r);
      if (course == null) continue;

      final c = course.toLowerCase();
      bool matched = false;

      if (breakfastKeys.any((k) => c.contains(k))) {
        out['breakfast']!.add(id);
        matched = true;
      }
      if (snackKeys.any((k) => c.contains(k))) {
        out['snack1']!.add(id);
        out['snack2']!.add(id);
        matched = true;
      }
      if (lunchKeys.any((k) => c.contains(k))) {
        out['lunch']!.add(id);
        matched = true;
      }
      if (dinnerKeys.any((k) => c.contains(k))) {
        out['dinner']!.add(id);
        matched = true;
      }

      if (!matched) {
        // fallback only
      }
    }

    out.removeWhere((_, v) => v.isEmpty);
    return out;
  }

  String? _extractCourse(Map<String, dynamic> recipe) {
    dynamic v;

    final inner = recipe['recipe'];
    if (inner is Map<String, dynamic>) {
      v = inner['course'] ??
          inner['courses'] ??
          inner['meal'] ??
          inner['meal_type'];
    }
    v ??= recipe['course'] ?? recipe['courses'];

    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is List) {
      final parts = v
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isEmpty) return null;
      return parts.join(', ');
    }
    return null;
  }

  int? _pickId({
    required Random rng,
    required List<int> preferred,
    required List<int> fallback,
    required Set<int> avoid,
  }) {
    final pref = preferred.where((id) => !avoid.contains(id)).toList();
    if (pref.isNotEmpty) return pref[rng.nextInt(pref.length)];
    if (preferred.isNotEmpty) return preferred[rng.nextInt(preferred.length)];

    final fb = fallback.where((id) => !avoid.contains(id)).toList();
    if (fb.isNotEmpty) return fb[rng.nextInt(fb.length)];
    return fallback.isEmpty ? null : fallback[rng.nextInt(fallback.length)];
  }
}

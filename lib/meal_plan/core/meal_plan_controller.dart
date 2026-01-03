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

  final Map<String, Map<String, Map<String, dynamic>>> _draft = {};

  StreamSubscription<Map<String, dynamic>?>? _sub;

  bool _populateInFlight = false;
  String? _lastPopulatedWeekId;

  // -------------------------------------------------------
  // Allergies
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
    notifyListeners();
  }

  // -------------------------------------------------------
  // Ingredient text
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
  // Allergy engine
  // -------------------------------------------------------

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
      includeSwapRecipes: false,
    );

    return res.status == AllergyStatus.safe;
  }

  // -------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------

  String get uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError('User not logged in');
    return u.uid;
  }

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

  // -------------------------------------------------------
  // Parsing / Entries
  // -------------------------------------------------------

  int? recipeIdFromAny(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

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

  int? entryRecipeId(Map<String, dynamic>? e) {
    if (e == null || e['type'] != 'recipe') return null;
    return recipeIdFromAny(e['recipeId']);
  }

  String? entryNoteText(Map<String, dynamic>? e) {
    if (e == null || e['type'] != 'note') return null;
    return (e['text'] ?? '').toString().trim();
  }

  // -------------------------------------------------------
  // Draft Editing
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
      return entryRecipeId(a) == entryRecipeId(b);
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

  // -------------------------------------------------------
  // COURSE EXTRACTION
  // -------------------------------------------------------

  String? _extractCourse(Map<String, dynamic> recipe) {
    final r = recipe['recipe'] is Map ? (recipe['recipe'] as Map) : recipe;
    dynamic v;

    if (r['tags'] is Map) {
      final tags = r['tags'];
      v = tags['course'] ?? tags['courses'] ?? tags['meal'];
    }

    if (v == null) {
      v = r['course'] ?? r['courses'] ?? r['meal'] ?? r['meal_type'];
    }

    if (v == null && r['taxonomies'] is Map) {
      final tax = r['taxonomies'];
      v = tax['course'] ??
          tax['recipe_course'] ??
          tax['wprm_course'] ??
          tax['category'];
    }

    if (v == null) return null;

    if (v is String) return v.trim();
    if (v is List) {
      if (v.isEmpty) return null;
      final parts = <String>[];
      for (final item in v) {
        if (item is String) {
          parts.add(item);
        } else if (item is Map) {
          final name = item['name'] ?? item['slug'] ?? item['term'] ?? '';
          if (name is String && name.isNotEmpty) parts.add(name);
        }
      }
      if (parts.isEmpty) return null;
      return parts.join(', ');
    }
    return null;
  }

  List<String> _courseTokens(String? courseRaw) {
    if (courseRaw == null) return const [];
    final raw = courseRaw.toLowerCase().trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  bool _anyTokenContains(List<String> tokens, List<String> needles) {
    for (final t in tokens) {
      for (final n in needles) {
        if (t.contains(n)) return true;
      }
    }
    return false;
  }

  // Only these 4 exist in your dataset
  bool _isBreakfastCourseTokens(List<String> tokens) {
    return _anyTokenContains(tokens, const ['breakfast']);
  }

  bool _isMainsCourseTokens(List<String> tokens) {
    return _anyTokenContains(tokens, const ['mains']);
  }

  bool _isSnacksCourseTokens(List<String> tokens) {
    return _anyTokenContains(tokens, const ['snacks']);
  }

  bool _isSweetsCourseTokens(List<String> tokens) {
    return _anyTokenContains(tokens, const ['sweets']);
  }

  // -------------------------------------------------------
  // CANDIDATE FILTERING
  // -------------------------------------------------------

  List<int> getCandidatesForSlot(
    String slot,
    List<Map<String, dynamic>> recipes,
  ) {
    return recipes.where((r) {
      if (!recipeAllowed(r)) return false;

      final courseRaw = _extractCourse(r);
      final tokens = _courseTokens(courseRaw);
      if (tokens.isEmpty) return false;

      if (slot == 'breakfast') {
        // breakfast if breakfast appears anywhere in the course list
        return _isBreakfastCourseTokens(tokens);
      }

      if (slot == 'lunch' || slot == 'dinner') {
        // mains only
        return _isMainsCourseTokens(tokens);
      }

      if (slot == 'snack1' || slot == 'snack2') {
        // ✅ STRICT: snacks only if "snacks" appears anywhere
        // (Breakfast can be a snack ONLY if it ALSO has snacks)
        return _isSnacksCourseTokens(tokens);
      }

      return false;
    }).map((r) => recipeIdFromAny(r['id'])).whereType<int>().toList();
  }

  // -------------------------------------------------------
  // GENERATOR
  // -------------------------------------------------------

  Future<void> ensurePlanPopulated({
    required List<Map<String, dynamic>> recipes,
  }) async {
    if (_populateInFlight) return;
    if (_lastPopulatedWeekId == weekId) return;

    await ensureWeek();

    Map<String, dynamic> data;
    if (weekData != null) {
      data = weekData!;
    } else {
      final loaded = await _repo.loadWeek(uid: uid, weekId: weekId);
      data = loaded ?? <String, dynamic>{};
      weekData = data;
      notifyListeners();
    }

    final existingDays = data['days'] is Map ? (data['days'] as Map) : const {};

    final buckets = <String, List<int>>{
      'breakfast': getCandidatesForSlot('breakfast', recipes),
      'lunch': getCandidatesForSlot('lunch', recipes),
      'dinner': getCandidatesForSlot('dinner', recipes),
      'snack1': getCandidatesForSlot('snack1', recipes),
      'snack2': getCandidatesForSlot('snack2', recipes),
    };

    final usedInWeek = <int>{};
    final dayKeys = MealPlanKeys.weekDayKeys(weekId);

    for (final dayKey in dayKeys) {
      final rawExisting = existingDays[dayKey];
      final dayMap = (rawExisting is Map) ? rawExisting : {};
      for (final slot in MealPlanSlots.order) {
        final rid1 = entryRecipeId(_parseEntry(dayMap[slot]));
        if (rid1 != null) usedInWeek.add(rid1);
        final rid2 = entryRecipeId(_draft[dayKey]?[slot]);
        if (rid2 != null) usedInWeek.add(rid2);
      }
    }

    final rng = Random(weekId.hashCode);
    final toUpsert = <String, Map<String, dynamic>>{};
    _populateInFlight = true;

    try {
      for (final dayKey in dayKeys) {
        Map<String, dynamic> existingDay = {};
        if (existingDays[dayKey] is Map) {
          existingDay = Map<String, dynamic>.from(existingDays[dayKey]);
        }

        final updatedDay = <String, dynamic>{...existingDay};
        bool changed = false;

        for (final slot in MealPlanSlots.order) {
          if (_parseEntry(existingDay[slot]) != null) continue;
          if (_draft[dayKey]?[slot] != null) continue;

          var candidates = buckets[slot] ?? [];

          if (candidates.isEmpty && (slot == 'lunch' || slot == 'dinner')) {
            candidates = (slot == 'lunch')
                ? (buckets['dinner'] ?? [])
                : (buckets['lunch'] ?? []);
          }
          if (candidates.isEmpty && (slot == 'snack1' || slot == 'snack2')) {
            candidates = (slot == 'snack1')
                ? (buckets['snack2'] ?? [])
                : (buckets['snack1'] ?? []);
          }

          final picked = _pickId(rng, candidates, usedInWeek);

          if (picked != null) {
            updatedDay[slot] = {
              'type': 'recipe',
              'recipeId': picked,
              'source': 'auto',
            };
            usedInWeek.add(picked);
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

  int? _pickId(Random rng, List<int> candidates, Set<int> avoid) {
    if (candidates.isEmpty) return null;
    final fresh = candidates.where((id) => !avoid.contains(id)).toList();
    if (fresh.isNotEmpty) return fresh[rng.nextInt(fresh.length)];
    return candidates[rng.nextInt(candidates.length)];
  }
}

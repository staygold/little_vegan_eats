import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'allergy_keys.dart';
import 'meal_plan_keys.dart';
import 'meal_plan_repository.dart';
import 'meal_plan_slots.dart';

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
  /// EntryMap supports:
  /// - {"type":"recipe","recipeId":123,"source":"auto|manual"}
  /// - {"type":"note","text":"Out for dinner"}
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
    _excludedAllergens = excludedAllergens.where(AllergyKeys.isSupported).toSet();
    _childAllergens = childAllergens.where(AllergyKeys.isSupported).toSet();

    // Allow regeneration with new rules
    _lastPopulatedWeekId = null;
    notifyListeners();
  }

  Set<String> _recipeAllergens(Map<String, dynamic> recipe) {
    // Supports either recipe['allergens'] or recipe['recipe']['allergens']
    dynamic v = recipe['allergens'];
    final inner = recipe['recipe'];
    if (v == null && inner is Map<String, dynamic>) {
      v = inner['allergens'];
    }

    final out = <String>{};

    if (v is List) {
      for (final a in v) {
        final k = a?.toString().trim();
        if (k != null && k.isNotEmpty && AllergyKeys.isSupported(k)) out.add(k);
      }
    } else if (v is String) {
      // allow "peanut, gluten" or "peanut|gluten"
      for (final part in v.split(RegExp(r'[,|]'))) {
        final k = part.trim();
        if (k.isNotEmpty && AllergyKeys.isSupported(k)) out.add(k);
      }
    }

    return out;
  }

  bool recipeAllowed(Map<String, dynamic> recipe) {
    if (_excludedAllergens.isEmpty) return true;
    final a = _recipeAllergens(recipe);
    return a.intersection(_excludedAllergens).isEmpty;
  }

  bool recipeSafeForAllChildren(Map<String, dynamic> recipe) {
    if (_childAllergens.isEmpty) return true;
    final a = _recipeAllergens(recipe);
    return a.intersection(_childAllergens).isEmpty;
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
  // Helpers (ID parsing)
  // -------------------------------------------------------

  int? recipeIdFromAny(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  // -------------------------------------------------------
  // Entry parsing (supports legacy int + new map format)
  // -------------------------------------------------------

  static Map<String, dynamic>? _parseEntry(dynamic raw) {
    // Legacy: int/num recipeId
    if (raw is int) {
      return {'type': 'recipe', 'recipeId': raw, 'source': 'auto'};
    }
    if (raw is num) {
      return {'type': 'recipe', 'recipeId': raw.toInt(), 'source': 'auto'};
    }

    // New: map
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
        final recipeId = (rid is int) ? rid : (rid is num ? rid.toInt() : null);
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
    final t = text.trim();
    final dayDraft = _draft.putIfAbsent(dayKey, () => {});
    dayDraft[slot] = {'type': 'note', 'text': t};
    notifyListeners();
  }

  bool hasDraftChanges(String dayKey) {
    final d = _draft[dayKey];
    if (d == null || d.isEmpty) return false;

    final data = weekData;
    if (data == null) return true;

    for (final e in d.entries) {
      final slot = e.key;
      final draft = e.value;
      final current = firestoreEntry(dayKey, slot);

      if (!_entryEquals(current, draft)) return true;
    }
    return false;
  }

  bool _entryEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    final ta = a['type'];
    final tb = b['type'];
    if (ta != tb) return false;

    if (ta == 'recipe') {
      return entryRecipeId(a) == entryRecipeId(b) && (a['source'] ?? '') == (b['source'] ?? '');
    }
    if (ta == 'note') {
      return entryNoteText(a) == entryNoteText(b);
    }
    return false;
  }

  Future<void> saveDay(String dayKey) async {
    final data = weekData;
    final dayDraft = _draft[dayKey];
    if (dayDraft == null || dayDraft.isEmpty) return;

    final existing = (data == null)
        ? <String, dynamic>{}
        : (MealPlanRepository.dayMapFromWeek(data, dayKey) ?? <String, dynamic>{});

    final updated = <String, dynamic>{...existing};

    for (final e in dayDraft.entries) {
      updated[e.key] = e.value;
    }

    await _repo.saveDay(uid: uid, weekId: weekId, dayKey: dayKey, daySlots: updated);

    _draft.remove(dayKey);
    notifyListeners();
  }

  // -------------------------------------------------------
  // Inspire (recipe only)
  // -------------------------------------------------------

  int? pickDifferentId({
    required List<int> availableIds,
    required int? currentId,
  }) {
    if (availableIds.isEmpty) return null;
    if (availableIds.length == 1) return availableIds.first;

    final idx = currentId == null ? -1 : availableIds.indexOf(currentId);
    final start = idx < 0 ? 0 : (idx + 1) % availableIds.length;

    for (int step = 0; step < availableIds.length; step++) {
      final candidate = availableIds[(start + step) % availableIds.length];
      if (candidate != currentId) return candidate;
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

    final existingDays = data['days'] is Map ? (data['days'] as Map) : const {};

    // SAFE pool (respect allergies) + robust id parsing (int/num/string)
    final allIds = <int>[];
    for (final r in recipes) {
      if (!recipeAllowed(r)) continue;
      final id = recipeIdFromAny(r['id']);
      if (id != null) allIds.add(id);
    }
    if (allIds.isEmpty) return;

    // Buckets must be built from SAFE recipes too, and must also parse ids robustly
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
            updatedDay[slot] = {'type': 'recipe', 'recipeId': picked, 'source': 'auto'};
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

  Map<String, List<int>> _buildSlotBucketsFromCourse(List<Map<String, dynamic>> recipes) {
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
      v = inner['course'] ?? inner['courses'] ?? inner['meal'] ?? inner['meal_type'];
    }
    v ??= recipe['course'] ?? recipe['courses'];

    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is List) {
      final parts = v.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
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

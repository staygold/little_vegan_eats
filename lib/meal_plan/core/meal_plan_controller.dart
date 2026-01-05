import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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

  /// dayKey -> slot -> entryMap
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

  // ✅ ROBUST SLOT LOOKUP
  dynamic _lookupSlot(Map<String, dynamic>? container, String slot) {
    if (container == null) return null;
    if (container.containsKey(slot)) return container[slot];

    // Try underscore version
    if (slot == 'snack1' && container.containsKey('snack_1')) return container['snack_1'];
    if (slot == 'snack2' && container.containsKey('snack_2')) return container['snack_2'];

    // Try clean version
    if (slot == 'snack_1' && container.containsKey('snack1')) return container['snack1'];
    if (slot == 'snack_2' && container.containsKey('snack2')) return container['snack2'];

    return null;
  }

  String _normSlot(String slot) {
    final s = slot.trim().toLowerCase();
    if (s == 'snack1' || s == 'snacks1' || s == 'snack 1') return 'snack_1';
    if (s == 'snack2' || s == 'snacks2' || s == 'snack 2') return 'snack_2';
    return s;
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
        final recipeId = (rid is int) ? rid : (rid is num ? rid.toInt() : null);
        if (recipeId == null) return null;
        return {
          'type': 'recipe',
          'recipeId': recipeId,
          'source': (m['source'] ?? 'auto').toString(),
        };
      }

      if (type == 'reuse') {
        final fromDayKey = (m['fromDayKey'] ?? '').toString().trim();
        final fromSlot = (m['fromSlot'] ?? '').toString().trim();
        if (fromDayKey.isEmpty || fromSlot.isEmpty) return null;
        return {
          'type': 'reuse',
          'fromDayKey': fromDayKey,
          'fromSlot': fromSlot,
        };
      }

      // ✅ FIX: Handle persistent 'cleared' state
      if (type == 'cleared') {
        return {'type': 'clear'};
      }

      if (type == 'clear') {
        return {'type': 'clear'};
      }
    }
    return null;
  }

  Map<String, dynamic>? firestoreEntry(String dayKey, String slot) {
    final data = weekData;
    if (data == null) return null;
    final day = MealPlanRepository.dayMapFromWeek(data, dayKey);
    return _parseEntry(_lookupSlot(day, slot));
  }

  Map<String, dynamic>? draftEntry(String dayKey, String slot) {
    return _draft[dayKey]?[slot];
  }

  Map<String, dynamic>? effectiveEntry(String dayKey, String slot) {
    final d = _draft[dayKey];
    final draftItem = _lookupSlot(d, slot);
    if (draftItem != null) return draftItem;
    return firestoreEntry(dayKey, slot);
  }

  int? entryRecipeId(Map<String, dynamic>? e) {
    if (e == null || e['type'] != 'recipe') return null;
    return recipeIdFromAny(e['recipeId']);
  }

  String? entryNoteText(Map<String, dynamic>? e) {
    if (e == null || e['type'] != 'note') return null;
    final t = (e['text'] ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  Map<String, String>? entryReuseFrom(Map<String, dynamic>? e) {
    if (e == null || e['type'] != 'reuse') return null;
    final d = (e['fromDayKey'] ?? '').toString().trim();
    final s = (e['fromSlot'] ?? '').toString().trim();
    if (d.isEmpty || s.isEmpty) return null;
    return {'dayKey': d, 'slot': s};
  }

  // -------------------------------------------------------
  // Reuse resolution
  // -------------------------------------------------------

  Map<String, dynamic>? effectiveResolvedEntry(
    String dayKey,
    String slot, {
    Set<String>? visiting,
  }) {
    visiting ??= <String>{};
    final key = '$dayKey|$slot';
    if (visiting.contains(key)) return null;
    visiting.add(key);

    final e = effectiveEntry(dayKey, slot);
    if (e == null) return null;

    final type = (e['type'] ?? '').toString();
    if (type == 'recipe' || type == 'note') return e;
    
    // ✅ Handle clear/cleared as "return entry" so UI sees it's explicitly cleared
    if (type == 'clear' || type == 'cleared') return {'type': 'clear'};

    if (type == 'reuse') {
      final from = entryReuseFrom(e);
      if (from == null) return null;

      final fromDay = from['dayKey']!;
      final fromSlot = from['slot']!;

      final resolved = effectiveResolvedEntry(
        fromDay,
        fromSlot,
        visiting: visiting,
      );

      if (resolved == null) return null;

      return {
        ...resolved,
        '_reuseFrom': {'dayKey': fromDay, 'slot': fromSlot},
      };
    }

    return null;
  }

  Map<String, dynamic>? effectiveEntryForUI(String dayKey, String slot) {
    return effectiveResolvedEntry(dayKey, slot);
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
    final trimmed = text.trim();
    final dayDraft = _draft.putIfAbsent(dayKey, () => {});
    if (trimmed.isEmpty) {
      dayDraft[slot] = {'type': 'clear'};
    } else {
      dayDraft[slot] = {'type': 'note', 'text': trimmed};
    }
    notifyListeners();
  }

  void setDraftClear(String dayKey, String slot) {
    final dayDraft = _draft.putIfAbsent(dayKey, () => {});
    dayDraft[slot] = {'type': 'clear'};
    notifyListeners();
  }

  void setDraftReuseFrom({
    required String targetDayKey,
    required String targetSlot,
    required String fromDayKey,
    required String fromSlot,
  }) {
    final dayDraft = _draft.putIfAbsent(targetDayKey, () => {});
    dayDraft[targetSlot] = {
      'type': 'reuse',
      'fromDayKey': fromDayKey.trim(),
      'fromSlot': fromSlot.trim(),
    };
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
    if (a == null || b == null) {
      final bt = b?['type'];
      final at = a?['type'];
      // Treat clear, cleared, and null as equivalent for equality checks
      final aEmpty = (a == null || at == 'clear' || at == 'cleared');
      final bEmpty = (b == null || bt == 'clear' || bt == 'cleared');
      return aEmpty == bEmpty;
    }

    final ta = (a['type'] ?? '').toString();
    final tb = (b['type'] ?? '').toString();
    
    // Normalize 'cleared' -> 'clear'
    final taNorm = (ta == 'cleared') ? 'clear' : ta;
    final tbNorm = (tb == 'cleared') ? 'clear' : tb;
    
    if (taNorm != tbNorm) return false;

    if (taNorm == 'recipe') return entryRecipeId(a) == entryRecipeId(b);
    if (taNorm == 'note') return entryNoteText(a) == entryNoteText(b);
    if (taNorm == 'reuse') {
      final ra = entryReuseFrom(a);
      final rb = entryReuseFrom(b);
      if (ra == null && rb == null) return true;
      if (ra == null || rb == null) return false;
      return ra['dayKey'] == rb['dayKey'] && _normSlot(ra['slot']!) == _normSlot(rb['slot']!);
    }
    if (taNorm == 'clear') return true;

    return false;
  }

  Future<void> saveDay(String dayKey) async {
    final dayDraft = _draft[dayKey];
    if (dayDraft == null || dayDraft.isEmpty) return;

    final existing =
        MealPlanRepository.dayMapFromWeek(weekData ?? {}, dayKey) ?? {};

    final merged = <String, dynamic>{...existing};
    for (final e in dayDraft.entries) {
      final type = (e.value['type'] ?? '').toString();
      if (type == 'clear') {
        // ✅ FIX: Save explicit 'cleared' object to overwrite existing data in Firestore
        // This prevents the old recipe from reappearing after a merge.
        merged[e.key] = {'type': 'cleared'};
      } else {
        merged[e.key] = e.value;
      }
    }

    await _repo.saveDay(
      uid: uid,
      weekId: weekId,
      dayKey: dayKey,
      daySlots: merged,
    );

    _draft.remove(dayKey);
    notifyListeners();
  }

  // -------------------------------------------------------
  // Reuse dependents
  // -------------------------------------------------------

  List<Map<String, String>> reuseDependents({
    required String fromDayKey,
    required String fromSlot,
  }) {
    final fromSlotNorm = _normSlot(fromSlot);
    final out = <Map<String, String>>[];

    final dayKeys = MealPlanKeys.weekDayKeys(weekId);

    for (final dk in dayKeys) {
      for (final slot in MealPlanSlots.order) {
        final e = effectiveEntry(dk, slot);
        final from = entryReuseFrom(e);
        if (from == null) continue;

        if (from['dayKey'] == fromDayKey &&
            _normSlot(from['slot']!) == fromSlotNorm) {
          out.add({'dayKey': dk, 'slot': slot});
        }
      }
    }

    return out;
  }

  void clearSlotCascade({
    required String fromDayKey,
    required String fromSlot,
  }) {
    setDraftClear(fromDayKey, fromSlot);
    final deps = reuseDependents(fromDayKey: fromDayKey, fromSlot: fromSlot);
    for (final d in deps) {
      final dk = d['dayKey']!;
      final sl = d['slot']!;
      setDraftClear(dk, sl);
    }
    notifyListeners();
  }

  // -------------------------------------------------------
  // Generator Logic
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

  bool _isBreakfastCourseTokens(List<String> tokens) {
    return _anyTokenContains(tokens, const ['breakfast']);
  }

  bool _isMainsCourseTokens(List<String> tokens) {
    return _anyTokenContains(tokens, const ['mains']);
  }

  bool _isSnacksCourseTokens(List<String> tokens) {
    return _anyTokenContains(tokens, const ['snacks']);
  }

  List<int> getCandidatesForSlot(
    String slot,
    List<Map<String, dynamic>> recipes,
  ) {
    return recipes.where((r) {
      if (!recipeAllowed(r)) return false;

      final courseRaw = _extractCourse(r);
      final tokens = _courseTokens(courseRaw);
      if (tokens.isEmpty) return false;

      final norm = _normSlot(slot);

      if (norm.contains('breakfast')) return _isBreakfastCourseTokens(tokens);

      if (norm.contains('lunch') || norm.contains('dinner')) return _isMainsCourseTokens(tokens);

      if (norm.contains('snack')) {
        return _isSnacksCourseTokens(tokens);
      }

      return false;
    }).map((r) => recipeIdFromAny(r['id'])).whereType<int>().toList();
  }

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
      'snack_1': getCandidatesForSlot('snack_1', recipes),
      'snack_2': getCandidatesForSlot('snack_2', recipes),
    };

    final usedInWeek = <int>{};
    final dayKeys = MealPlanKeys.weekDayKeys(weekId);

    for (final dayKey in dayKeys) {
      final rawExisting = existingDays[dayKey];
      final dayMap = (rawExisting is Map) 
          ? Map<String, dynamic>.from(rawExisting) 
          : <String, dynamic>{};

      for (final slot in MealPlanSlots.order) {
        final rid1 = entryRecipeId(_parseEntry(_lookupSlot(dayMap, slot)));
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
          // ✅ FIX: _parseEntry returns {'type':'clear'} for cleared slots.
          // Since it is NOT null, the generator sees it as "occupied" and skips it.
          if (_parseEntry(_lookupSlot(existingDay, slot)) != null) continue;
          if (_lookupSlot(_draft[dayKey], slot) != null) continue;

          var candidates = buckets[slot] ?? [];

          if (candidates.isEmpty && (slot == 'lunch' || slot == 'dinner')) {
            candidates = (slot == 'lunch') ? (buckets['dinner'] ?? []) : (buckets['lunch'] ?? []);
          }

          if (candidates.isEmpty && (slot == 'snack_1' || slot == 'snack_2')) {
            candidates = (slot == 'snack_1') ? (buckets['snack_2'] ?? []) : (buckets['snack_1'] ?? []);
          }

          final picked = _pickId(rng, candidates, usedInWeek);

          if (picked != null) {
            updatedDay[slot] = {'type': 'recipe', 'recipeId': picked, 'source': 'auto'};
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
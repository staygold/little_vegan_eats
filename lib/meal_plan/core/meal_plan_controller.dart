// lib/meal_plan/core/meal_plan_controller.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  // -------------------------------------------------------
  // Week view state (kept for calendar navigation)
  // -------------------------------------------------------
  String weekId;

  /// Loading is now tied to day-cache + program pointer.
  bool isLoading = true;

  /// Effective day cache keyed by dayKey (YYYY-MM-DD).
  /// Value is the *day doc* shape (may include 'slots', 'type', etc).
  final Map<String, Map<String, dynamic>?> _dayDocCache = {};

  /// Per-day subs for the currently viewed week
  final Map<String, StreamSubscription<Map<String, dynamic>?>> _daySubs = {};

  /// Last known effective source for a day (optional, for debugging/UI)
  final Map<String, String> _daySources = {};

  // -------------------------------------------------------
  // Draft state (still used by MealPlanScreen)
  // -------------------------------------------------------
  /// dayKey -> slot -> entryMap
  final Map<String, Map<String, Map<String, dynamic>>> _draft = {};

  // -------------------------------------------------------
  // ✅ Program-based state (source of truth)
  // -------------------------------------------------------
  String? _activeProgramId;
  Map<String, dynamic>? _activeProgram;

  StreamSubscription<String?>? _programIdSub;
  StreamSubscription<Map<String, dynamic>?>? _programSub;

  String? get activeProgramId => _activeProgramId;
  Map<String, dynamic>? get activeProgram => _activeProgram;

  List<String> get scheduledDates {
    final p = _activeProgram;
    if (p == null) return const [];
    final v = p['scheduledDates'];
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  bool get hasActiveProgram {
    final p = _activeProgram;
    if (p == null) return false;
    return scheduledDates.isNotEmpty;
  }

  bool isDatePlanned(String dateKey) {
    if (dateKey.trim().isEmpty) return false;
    final p = _activeProgram;
    if (p == null) return false;
    final dates = p['scheduledDates'];
    if (dates is! List) return false;
    return dates.contains(dateKey);
  }

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
  // Lifecycle helpers
  // -------------------------------------------------------
  String get uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError('User not logged in');
    return u.uid;
  }

  /// “Has plan” now means: any meaningful content in the current viewed week
  /// OR (optionally) having an active program (even if the week view is empty).
  bool get hasActivePlan {
    // If you want this to reflect "program exists even if week is empty", keep this:
    if (hasActiveProgram) return true;

    final dayKeys = MealPlanKeys.weekDayKeys(weekId);
    for (final dk in dayKeys) {
      final doc = _dayDocCache[dk];
      final slots = slotsFromAnyDayDoc(doc);
      if (_dayHasMeaningfulSlots(slots)) return true;
    }
    return false;
  }

  // -------------------------------------------------------
  // Start/Stop (NEW)
  // -------------------------------------------------------
  void start() {
    // Program pointer watcher
    _programIdSub?.cancel();
    _programSub?.cancel();

    isLoading = true;

    _programIdSub = _repo.watchActiveProgramId(uid: uid).listen((pid) {
      final cleaned = (pid ?? '').trim();
      final next = cleaned.isEmpty ? null : cleaned;

      if (next == _activeProgramId) return;

      _activeProgramId = next;
      _activeProgram = null;

      // program doc watcher
      _programSub?.cancel();
      if (_activeProgramId != null) {
        _programSub = _repo
            .watchProgram(uid: uid, programId: _activeProgramId!)
            .listen((p) {
          _activeProgram = p;
          _rebuildWeekDayWatchers(); // program changes can affect effective days
          notifyListeners();
        });
      } else {
        _rebuildWeekDayWatchers();
        notifyListeners();
      }
    });

    // Kick watchers for the initial week
    _rebuildWeekDayWatchers();
  }

  Future<void> stop() async {
    await _programIdSub?.cancel();
    _programIdSub = null;

    await _programSub?.cancel();
    _programSub = null;

    for (final sub in _daySubs.values) {
      await sub.cancel();
    }
    _daySubs.clear();
    _dayDocCache.clear();
    _daySources.clear();

    isLoading = true;
  }

  /// No-op now (legacy week docs removed)
  Future<void> ensureWeek() async {
    // intentionally empty
  }

  Future<void> setWeek(String newWeekId) async {
    final cleaned = newWeekId.trim();
    if (cleaned.isEmpty || cleaned == weekId) return;

    weekId = cleaned;
    _draft.clear();

    _rebuildWeekDayWatchers();
    notifyListeners();
  }

  void _rebuildWeekDayWatchers() {
    final needed = MealPlanKeys.weekDayKeys(weekId).toSet();

    // Cancel subs we no longer need
    final toRemove = _daySubs.keys.where((k) => !needed.contains(k)).toList();
    for (final dk in toRemove) {
      _daySubs[dk]?.cancel();
      _daySubs.remove(dk);
      _dayDocCache.remove(dk);
      _daySources.remove(dk);
    }

    // Add missing subs
    for (final dk in needed) {
      if (_daySubs.containsKey(dk)) continue;

      final sub = _repo
          .watchEffectiveDay(
            uid: uid,
            dateKey: dk,
            programId: _activeProgramId,
          )
          .listen((doc) {
        _dayDocCache[dk] = doc;

        final src = (doc?['_effectiveSource'] ?? '').toString().trim();
        if (src.isNotEmpty) _daySources[dk] = src;

        // Once we have *some* values for the 7 days, consider ourselves "not loading".
        if (isLoading) {
          final all = MealPlanKeys.weekDayKeys(weekId);
          final haveAny = all.any((k) => _dayDocCache.containsKey(k));
          if (haveAny) isLoading = false;
        }

        notifyListeners();
      });

      _daySubs[dk] = sub;
    }

    // If no subs (shouldn't happen), stop loading anyway
    if (_daySubs.isEmpty) isLoading = false;
  }

  // -------------------------------------------------------
  // Program day helpers (still useful to call directly)
  // -------------------------------------------------------
  Stream<Map<String, dynamic>?> watchProgramDay(String dateKey) {
    final pid = _activeProgramId;
    if (pid == null) return const Stream.empty();

    final dk = dateKey.trim();
    if (dk.isEmpty) return const Stream.empty();

    return _repo.watchProgramDayInProgram(
      uid: uid,
      programId: pid,
      dateKey: dk,
    );
  }

  static Map<String, dynamic> slotsFromProgramDayDoc(Map<String, dynamic>? doc) {
    if (doc == null) return <String, dynamic>{};
    final v = doc['slots'];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  Future<void> saveProgramDay({
    required String dateKey,
    required Map<String, dynamic> daySlots,
  }) async {
    final pid = _activeProgramId;
    if (pid == null) throw StateError('No active program');

    final dk = dateKey.trim();
    if (dk.isEmpty) throw ArgumentError('dateKey is empty');

    await _repo.upsertProgramDay(
      uid: uid,
      programId: pid,
      dateKey: dk,
      daySlots: daySlots,
    );
  }

  Future<void> clearActiveProgram() async {
    await _repo.setActiveProgramId(uid: uid, programId: null);
  }

  // -------------------------------------------------------
  // ✅ GENERATE PLAN STRUCTURE (builder helper)
  // -------------------------------------------------------
  Map<String, dynamic> generatePlanData({
    required bool wantsBreakfast,
    required bool wantsLunch,
    required bool wantsDinner,
    required int snackCount, // 0, 1, or 2
    required String? planName,
    required bool isWeek,
  }) {
    final Map<String, dynamic> dayStructure = {};

    dayStructure['breakfast'] = wantsBreakfast ? null : {'type': 'clear'};
    dayStructure['lunch'] = wantsLunch ? null : {'type': 'clear'};
    dayStructure['dinner'] = wantsDinner ? null : {'type': 'clear'};

    if (snackCount == 0) {
      dayStructure['snack1'] = {'type': 'clear'};
      dayStructure['snack2'] = {'type': 'clear'};
    } else if (snackCount == 1) {
      dayStructure['snack1'] = null;
      dayStructure['snack2'] = {'type': 'clear'};
    } else {
      dayStructure['snack1'] = null;
      dayStructure['snack2'] = null;
    }

    final timestamp = FieldValue.serverTimestamp();

    if (!isWeek) {
      return {
        'title': (planName?.trim().isNotEmpty == true) ? planName : 'My Day Plan',
        'type': 'day',
        'savedAt': timestamp,
        'updatedAt': timestamp,
        'day': dayStructure,
      };
    } else {
      final Map<String, dynamic> weekDays = {};
      for (int i = 0; i < 7; i++) {
        weekDays[i.toString()] = dayStructure;
      }
      return {
        'title': (planName?.trim().isNotEmpty == true) ? planName : 'My Week Plan',
        'type': 'week',
        'savedAt': timestamp,
        'updatedAt': timestamp,
        'days': weekDays,
      };
    }
  }

  // -------------------------------------------------------
  // Day doc slot extraction (supports both shapes)
  // -------------------------------------------------------
  static Map<String, dynamic> slotsFromAnyDayDoc(Map<String, dynamic>? doc) {
    if (doc == null) return <String, dynamic>{};

    // Preferred shape: { slots: { breakfast: ..., ... } }
    final v = doc['slots'];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);

    // Fallback shape: doc itself contains slot keys
    final out = <String, dynamic>{};
    for (final slot in MealPlanSlots.order) {
      if (doc.containsKey(slot)) out[slot] = doc[slot];
      if (slot == 'snack1' && doc.containsKey('snack_1')) out['snack1'] = doc['snack_1'];
      if (slot == 'snack2' && doc.containsKey('snack_2')) out['snack2'] = doc['snack_2'];
    }
    return out;
  }

  // -------------------------------------------------------
  // Meaningful plan detection (reused)
  // -------------------------------------------------------
  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  bool _isValidRecipeId(dynamic v) {
    final n = (v is int) ? v : int.tryParse(v?.toString() ?? '');
    return (n ?? 0) > 0;
  }

  bool _isSlotEntryMap(Map m) {
    final keys = m.keys.map((e) => e.toString()).toSet();
    return keys.contains('type') ||
        keys.contains('kind') ||
        keys.contains('recipeId') ||
        keys.contains('id') ||
        keys.contains('text') ||
        keys.contains('note') ||
        keys.contains('fromDayKey') ||
        keys.contains('fromSlot');
  }

  bool _slotHasRealContent(Map m) {
    final type = (m['type'] ?? m['kind'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (type == 'clear' || type == 'cleared') return false;

    if (type == 'note') {
      final t = (m['text'] ?? '').toString().trim();
      return t.isNotEmpty;
    }

    if (type == 'recipe') {
      return _isValidRecipeId(m['recipeId']) || _isValidRecipeId(m['id']);
    }

    // treat reuse as non-meaningful for ghost detection
    if (type == 'reuse') return false;

    if (_isValidRecipeId(m['recipeId']) || _isValidRecipeId(m['id'])) return true;
    final t = (m['text'] ?? m['note'] ?? '').toString().trim();
    if (t.isNotEmpty) return true;

    return false;
  }

  bool _hasMeaningfulValue(dynamic v) {
    if (v == null) return false;

    if (v is String) return v.trim().isNotEmpty;
    if (v is num || v is bool) return true;

    if (v is List) {
      for (final item in v) {
        if (_hasMeaningfulValue(item)) return true;
      }
      return false;
    }

    if (v is Map) {
      if (v.isEmpty) return false;

      if (_isSlotEntryMap(v)) {
        return _slotHasRealContent(v);
      }

      for (final entry in v.entries) {
        final key = entry.key.toString();
        final val = entry.value;
        if (key == 'updatedAt' || key == 'createdAt') continue;
        if (_hasMeaningfulValue(val)) return true;
      }
      return false;
    }

    return true;
  }

  bool _dayHasMeaningfulSlots(Map<String, dynamic> day) {
    for (final slot in MealPlanSlots.order) {
      final v = day[slot];
      if (_hasMeaningfulValue(v)) return true;

      if (slot == 'snack1' && _hasMeaningfulValue(day['snack_1'])) return true;
      if (slot == 'snack2' && _hasMeaningfulValue(day['snack_2'])) return true;
    }
    return false;
  }

  // -------------------------------------------------------
  // Parsing / Entries (now sourced from effective day cache)
  // -------------------------------------------------------
  int? recipeIdFromAny(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  dynamic _lookupSlot(Map<String, dynamic>? container, String slot) {
    if (container == null) return null;
    if (container.containsKey(slot)) return container[slot];

    if (slot == 'snack1' && container.containsKey('snack_1')) return container['snack_1'];
    if (slot == 'snack2' && container.containsKey('snack_2')) return container['snack_2'];

    return null;
  }

  String _normSlot(String slot) {
    final s = slot.trim().toLowerCase();
    if (s == 'snack_1' || s == 'snacks_1' || s == 'snack 1') return 'snack1';
    if (s == 'snack1' || s == 'snacks1') return 'snack1';
    if (s == 'snack_2' || s == 'snacks_2' || s == 'snack 2') return 'snack2';
    if (s == 'snack2' || s == 'snacks2') return 'snack2';
    return s;
  }

  static Map<String, dynamic>? _parseEntry(dynamic raw) {
    if (raw is int) return {'type': 'recipe', 'recipeId': raw, 'source': 'auto'};
    if (raw is num) return {'type': 'recipe', 'recipeId': raw.toInt(), 'source': 'auto'};

    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final type = (m['type'] ?? '').toString();

      if (type == 'note') {
        final text = (m['text'] ?? '').toString().trim();
        if (text.isEmpty) return null;
        return {'type': 'note', 'text': text};
      }

      if (type == 'recipe') {
        final rid = m['recipeId'] ?? m['id'];
        final recipeId = (rid is int)
            ? rid
            : (rid is num ? rid.toInt() : int.tryParse('${rid ?? ''}'));
        if (recipeId == null || recipeId <= 0) return null;
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
        return {'type': 'reuse', 'fromDayKey': fromDayKey, 'fromSlot': fromSlot};
      }

      if (type == 'cleared' || type == 'clear') return {'type': 'clear'};
    }

    return null;
  }

  /// Returns parsed entry from the effective day cache (adhoc > program).
  Map<String, dynamic>? firestoreEntry(String dayKey, String slot) {
    final doc = _dayDocCache[dayKey];
    final slots = slotsFromAnyDayDoc(doc);
    return _parseEntry(_lookupSlot(slots, slot));
  }

  Map<String, dynamic>? draftEntry(String dayKey, String slot) => _draft[dayKey]?[slot];

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

  Set<String> dirtyDayKeys() {
    final out = <String>{};
    final dayKeys = MealPlanKeys.weekDayKeys(weekId);
    for (final dk in dayKeys) {
      if (hasDraftChanges(dk)) out.add(dk);
    }
    return out;
  }

  int dirtySlotCount() {
    int total = 0;
    final dayKeys = MealPlanKeys.weekDayKeys(weekId);
    for (final dk in dayKeys) {
      total += dirtySlotsForDay(dk).length;
    }
    return total;
  }

  Set<String> dirtySlotsForDay(String dayKey) {
    final out = <String>{};
    final d = _draft[dayKey];
    if (d == null || d.isEmpty) return out;

    for (final e in d.entries) {
      final current = firestoreEntry(dayKey, e.key);
      if (!_entryEquals(current, e.value)) out.add(e.key);
    }
    return out;
  }

  Future<void> saveAllDirtyDays() async {
    final days = dirtyDayKeys().toList()..sort();
    for (final dk in days) {
      await saveDay(dk);
    }
  }

  bool hasDraftChanges(String dayKey) {
    final d = _draft[dayKey];
    if (d == null || d.isEmpty) return false;

    for (final e in d.entries) {
      final current = firestoreEntry(dayKey, e.key);
      if (!_entryEquals(current, e.value)) return true;
    }
    return false;
  }

  bool _entryEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;

    if (a == null || b == null) {
      final at = (a?['type'] ?? '').toString();
      final bt = (b?['type'] ?? '').toString();
      final aEmpty = (a == null || at == 'clear' || at == 'cleared');
      final bEmpty = (b == null || bt == 'clear' || bt == 'cleared');
      return aEmpty == bEmpty;
    }

    final ta = (a['type'] ?? '').toString();
    final tb = (b['type'] ?? '').toString();

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

    final existingDoc = _dayDocCache[dayKey];
    final existingSlots = slotsFromAnyDayDoc(existingDoc);

    final merged = <String, dynamic>{...existingSlots};

    for (final e in dayDraft.entries) {
      final type = (e.value['type'] ?? '').toString();
      if (type == 'clear') {
        // Store as clear in the new model
        merged[e.key] = {'type': 'clear'};
      } else {
        merged[e.key] = e.value;
      }
    }

    // Save destination:
    // - if date is part of active program => write program day
    // - else => write adhoc day
    if (_activeProgramId != null && isDatePlanned(dayKey)) {
      await _repo.upsertProgramDay(
        uid: uid,
        programId: _activeProgramId!,
        dateKey: dayKey,
        daySlots: merged,
      );
    } else {
      await _repo.upsertAdhocDay(
        uid: uid,
        dateKey: dayKey,
        daySlots: merged,
      );
    }

    _draft.remove(dayKey);
    notifyListeners();
  }

  // -------------------------------------------------------
  // Reuse cascading helpers
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
  // Legacy “saved plan activation” (rewired to adhoc writes)
  // -------------------------------------------------------
  /// Applies a legacy-style savedPlan map onto the current viewed week
  /// by writing ad-hoc days for those dates.
  Future<void> activateSavedPlan({
    required Map<String, dynamic> savedPlan,
  }) async {
    final targetDates = MealPlanKeys.weekDayKeys(weekId);

    final rawConfig = savedPlan['config'];
    final config = (rawConfig is Map)
        ? Map<String, dynamic>.from(rawConfig)
        : <String, dynamic>{};

    final v = config['daysToPlan'];
    final daysToPlan = (v is int) ? v : int.tryParse(v?.toString() ?? '');
    final isDayPlan = (daysToPlan ?? 0) == 1;

    final sourceDays = savedPlan['days'] as Map<String, dynamic>? ?? {};
    final Map<String, Map<String, dynamic>> newDaysByDate = {};

    if (isDayPlan) {
      final tk = (config['targetDayKey'] ?? '').toString().trim();
      final targetDayKey = tk.isNotEmpty ? tk : targetDates.first;

      final finalDayKey =
          targetDates.contains(targetDayKey) ? targetDayKey : targetDates.first;

      Map<String, dynamic>? dayData;
      if (sourceDays['0'] is Map) {
        dayData = Map<String, dynamic>.from(sourceDays['0'] as Map);
      } else {
        for (final vv in sourceDays.values) {
          if (vv is Map) {
            dayData = Map<String, dynamic>.from(vv);
            break;
          }
        }
      }

      if (dayData != null) newDaysByDate[finalDayKey] = dayData;
    } else {
      // Week plan mapping numeric keys to week dates
      int index = 0;

      final sortedKeys = sourceDays.keys.map((k) => k.toString()).toList();
      sortedKeys.sort((a, b) {
        final ai = int.tryParse(a);
        final bi = int.tryParse(b);
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.compareTo(b);
      });

      for (final dateKey in targetDates) {
        if (index >= sortedKeys.length) break;

        final sourceKey = sortedKeys[index];
        final sourceDayData = sourceDays[sourceKey];

        if (sourceDayData is Map) {
          newDaysByDate[dateKey] = Map<String, dynamic>.from(sourceDayData);
        }
        index++;
      }
    }

    if (newDaysByDate.isEmpty) return;

    // Apply as adhoc overrides (safe, reversible, doesn’t mutate program template)
    for (final entry in newDaysByDate.entries) {
      final dateKey = entry.key;
      final slots = Map<String, dynamic>.from(entry.value);
      await _repo.upsertAdhocDay(uid: uid, dateKey: dateKey, daySlots: slots);
    }

    notifyListeners();
  }

  /// Clears ad-hoc overrides for the current viewed week and drafts.
  /// (Does NOT delete the program.)
  Future<void> clearPlan() async {
    final dayKeys = MealPlanKeys.weekDayKeys(weekId);
    for (final dk in dayKeys) {
      try {
        await _repo.deleteAdhocDay(uid: uid, dateKey: dk);
      } catch (_) {
        // ignore if not present
      }
    }

    _draft.clear();
    notifyListeners();
  }

  // -------------------------------------------------------
  // Candidate selection (courses)
  // -------------------------------------------------------
  List<int> getCandidatesForSlot(
    String slot,
    List<Map<String, dynamic>> recipes,
  ) {
    return recipes
        .where((r) {
          if (!recipeAllowed(r)) return false;

          final courseRaw = _extractCourse(r);
          final tokens = _courseTokens(courseRaw);
          if (tokens.isEmpty) return false;

          final norm = _normSlot(slot);

          if (norm.contains('breakfast')) return _isBreakfastCourseTokens(tokens);

          if (norm.contains('lunch') || norm.contains('dinner')) {
            return _isMainsCourseTokens(tokens);
          }

          if (norm.contains('snack')) return _isSnacksCourseTokens(tokens);

          return false;
        })
        .map((r) => recipeIdFromAny(r['id']))
        .whereType<int>()
        .toList();
  }

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
    return _anyTokenContains(tokens, const ['mains', 'lunch', 'dinner', 'main']);
  }

  bool _isSnacksCourseTokens(List<String> tokens) {
    return _anyTokenContains(tokens, const ['snacks', 'snack']);
  }
}

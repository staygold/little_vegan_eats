// lib/meal_plan/core/meal_plan_controller.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'meal_plan_age_engine.dart';
import 'meal_plan_keys.dart';
import 'meal_plan_log.dart' as mplog;
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
  // ✅ Children (for age gating)
  // -------------------------------------------------------
  List<dynamic>? get childrenFromProgramOrNull {
    final p = _activeProgram;
    if (p == null) return null;
    final c = p['children'];
    return (c is List) ? c : null;
  }

  // -------------------------------------------------------
  // ✅ User doc cache (fallback children source)
  // -------------------------------------------------------
  Map<String, dynamic>? _userDocCache;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  List<dynamic>? get childrenFallbackFromUserDocOrNull {
    final c = _userDocCache?['children'];
    return (c is List) ? c : null;
  }

  /// ✅ Prefer program children, otherwise fallback to user doc children.
  List<dynamic>? get childrenEffectiveOrNull {
    final a = childrenFromProgramOrNull;
    if (a != null && a.isNotEmpty) return a;
    final b = childrenFallbackFromUserDocOrNull;
    if (b != null && b.isNotEmpty) return b;
    return a; // could be null
  }

  bool get hasChildren => (childrenEffectiveOrNull?.isNotEmpty ?? false);

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
  // Ingredient text (legacy fallback)
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
  // Allergy engine (tags + swaps first, legacy scan fallback)
  // -------------------------------------------------------
  List<String> _allUserAllergies() {
    if (_excludedAllergens.isEmpty && _childAllergens.isEmpty) return const [];
    return <String>{
      ..._excludedAllergens,
      ..._childAllergens,
    }.toList();
  }

  List<String> _extractAllergyTags(Map<String, dynamic> recipe) {
    final r = (recipe['recipe'] is Map)
        ? Map<String, dynamic>.from(recipe['recipe'] as Map)
        : recipe;

    final out = <String>[];

    void addFrom(dynamic v) {
      if (v == null) return;

      if (v is List) {
        for (final item in v) {
          if (item is String) {
            final s = item.trim();
            if (s.isNotEmpty) out.add(s);
          } else if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final name = (m['slug'] ?? m['name'] ?? m['term'] ?? '')
                .toString()
                .trim();
            if (name.isNotEmpty) out.add(name);
          }
        }
        return;
      }

      if (v is String) {
        final s = v.trim();
        if (s.isNotEmpty) {
          out.addAll(
            s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
          );
        }
      }
    }

    final tags = r['tags'];
    if (tags is Map) addFrom(tags['allergies']);

    addFrom(r['wprm_allergies']);
    addFrom(r['allergies']);
    addFrom(r['allergy_tags']);

    final norm = out
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return norm;
  }

  String _extractSwapText(Map<String, dynamic> recipe) {
    final r = (recipe['recipe'] is Map)
        ? Map<String, dynamic>.from(recipe['recipe'] as Map)
        : recipe;

    final cf = r['custom_fields'];
    if (cf is Map) {
      final v = (cf['ingredient_swaps'] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }

    final v2 =
        (r['ingredient_swaps'] ?? r['swap_text'] ?? '').toString().trim();
    return v2;
  }

  dynamic _evaluateWithTags(Map<String, dynamic> recipe) {
    final allergies = _allUserAllergies();
    if (allergies.isEmpty) return null;

    final tags = _extractAllergyTags(recipe);
    if (tags.isEmpty) return null;

    final swaps = _extractSwapText(recipe);

    return AllergyEngine.evaluate(
      recipeAllergyTags: tags,
      swapFieldText: swaps,
      userAllergies: allergies,
    );
  }

  dynamic _evaluateLegacyScan(
    Map<String, dynamic> recipe, {
    required bool includeSwapRecipes,
  }) {
    final allergies = _allUserAllergies();
    if (allergies.isEmpty) return null;

    final ingredientsText = _ingredientsTextOf(recipe);
    if (ingredientsText.isEmpty) return null;

    return AllergyEngine.evaluateRecipe(
      ingredientsText: ingredientsText,
      childAllergies: allergies,
      includeSwapRecipes: includeSwapRecipes,
    );
  }

  dynamic evaluateRecipe(
    Map<String, dynamic> recipe, {
    required bool includeSwapRecipes,
  }) {
    final allergies = _allUserAllergies();
    if (allergies.isEmpty) return null;

    final tagsRes = _evaluateWithTags(recipe);
    if (tagsRes != null) return tagsRes;

    return _evaluateLegacyScan(
      recipe,
      includeSwapRecipes: includeSwapRecipes,
    );
  }

  /// Gate used by plan generation + candidate selection.
  bool recipeAllowed(Map<String, dynamic> recipe) {
    final allergies = _allUserAllergies();
    if (allergies.isEmpty) return true;

    final res = _evaluateWithTags(recipe) ??
        _evaluateLegacyScan(recipe, includeSwapRecipes: false);

    if (res == null) return true;

    return res.status == AllergyStatus.safe;
  }

  // -------------------------------------------------------
  // ✅ Storage days taxonomy
  // -------------------------------------------------------
  int? extractStorageDays(Map<String, dynamic> recipe) {
    final r = (recipe['recipe'] is Map)
        ? Map<String, dynamic>.from(recipe['recipe'] as Map)
        : recipe;

    dynamic v;

    final tags = r['tags'];
    if (tags is Map) v = tags['storage_days'];

    v ??= (r['taxonomies'] is Map)
        ? (r['taxonomies'] as Map)['storage_days']
        : null;

    v ??= r['storage_days'];

    if (v is int) return v.clamp(1, 30);
    final parsed = int.tryParse(v?.toString().trim() ?? '');
    if (parsed == null) return null;
    return parsed.clamp(1, 30);
  }

  // -------------------------------------------------------
  // Lifecycle helpers
  // -------------------------------------------------------
  String get uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError('User not logged in');
    return u.uid;
  }

  bool get hasActivePlan {
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
  // Start/Stop
  // -------------------------------------------------------
  void start() {
    _programIdSub?.cancel();
    _programSub?.cancel();
    _userDocSub?.cancel();

    isLoading = true;

    // ✅ Cache /users/{uid} so we can fallback to children when program hasn't loaded.
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      _userDocCache = snap.data();
      // Only notify if program children are missing (prevents UI spam)
      if (!(childrenFromProgramOrNull?.isNotEmpty ?? false)) {
        notifyListeners();
      }
    });

    _programIdSub = _repo.watchActiveProgramId(uid: uid).listen((pid) {
      final cleaned = (pid ?? '').trim();
      final next = cleaned.isEmpty ? null : cleaned;

      if (next == _activeProgramId) return;

      _activeProgramId = next;
      _activeProgram = null;

      _programSub?.cancel();
      if (_activeProgramId != null) {
        _programSub = _repo
            .watchProgram(uid: uid, programId: _activeProgramId!)
            .listen((p) {
          _activeProgram = p;
          _rebuildWeekDayWatchers();
          notifyListeners();
        });
      } else {
        _rebuildWeekDayWatchers();
        notifyListeners();
      }
    });

    _rebuildWeekDayWatchers();
  }

  Future<void> stop() async {
    await _programIdSub?.cancel();
    _programIdSub = null;

    await _programSub?.cancel();
    _programSub = null;

    await _userDocSub?.cancel();
    _userDocSub = null;
    _userDocCache = null;

    for (final sub in _daySubs.values) {
      await sub.cancel();
    }
    _daySubs.clear();
    _dayDocCache.clear();
    _daySources.clear();
    _draft.clear();

    isLoading = true;
  }

  Future<void> ensureWeek() async {}

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

    final toRemove = _daySubs.keys.where((k) => !needed.contains(k)).toList();
    for (final dk in toRemove) {
      _daySubs[dk]?.cancel();
      _daySubs.remove(dk);
      _dayDocCache.remove(dk);
      _daySources.remove(dk);
    }

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

        if (isLoading) {
          final all = MealPlanKeys.weekDayKeys(weekId);
          final haveAny = all.any((k) => _dayDocCache.containsKey(k));
          if (haveAny) isLoading = false;
        }

        notifyListeners();
      });

      _daySubs[dk] = sub;
    }

    if (_daySubs.isEmpty) isLoading = false;
  }

  // -------------------------------------------------------
  // Program day helpers
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
    required int snackCount,
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

    final v = doc['slots'];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);

    final out = <String, dynamic>{};
    for (final slot in MealPlanSlots.order) {
      if (doc.containsKey(slot)) out[slot] = doc[slot];
      if (slot == 'snack1' && doc.containsKey('snack_1')) {
        out['snack1'] = doc['snack_1'];
      }
      if (slot == 'snack2' && doc.containsKey('snack_2')) {
        out['snack2'] = doc['snack_2'];
      }
    }
    return out;
  }

  // -------------------------------------------------------
  // Meaningful plan detection
  // -------------------------------------------------------
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
  // Parsing / Entries (KEEP for review service)
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

    if (slot == 'snack1' && container.containsKey('snack_1')) {
      return container['snack_1'];
    }
    if (slot == 'snack2' && container.containsKey('snack_2')) {
      return container['snack_2'];
    }

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

  /// ✅ used by meal_plan_review_service.dart
  Map<String, dynamic>? firestoreEntry(String dayKey, String slot) {
    final doc = _dayDocCache[dayKey];
    final slots = slotsFromAnyDayDoc(doc);
    return _parseEntry(_lookupSlot(slots, slot));
  }

  Map<String, dynamic>? draftEntry(String dayKey, String slot) =>
      _draft[dayKey]?[slot];

  Map<String, dynamic>? effectiveEntry(String dayKey, String slot) {
    final d = _draft[dayKey];
    final draftItem = _lookupSlot(d, slot);
    if (draftItem != null) return draftItem;
    return firestoreEntry(dayKey, slot);
  }

  /// ✅ used by meal_plan_review_service.dart
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
  // ✅ First foods detection (STRICT)
  // -------------------------------------------------------
  String _normFirstFoodsToken(String s) {
    final t = s.toLowerCase().trim();
    // normalize separators/spaces to underscore
    final norm = t
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return norm;
  }

  bool _isExactlyFirstFoodsToken(String s) {
    final n = _normFirstFoodsToken(s);
    return n == 'first_foods' || n == 'first_food';
  }

  bool _containsExactFirstFoods(dynamic v) {
    if (v == null) return false;

    // direct string
    if (v is String) return _isExactlyFirstFoodsToken(v);

    // list of strings or list of maps
    if (v is List) {
      for (final item in v) {
        if (_containsExactFirstFoods(item)) return true;
      }
      return false;
    }

    // map shapes:
    // - {slug: "..."} / {name: "..."} etc
    // - {terms: [...]}
    // - {"first_foods": true}  <-- we do NOT treat key-names as truth anymore
    if (v is Map) {
      // common single-term map
      final slug = (v['slug'] ?? v['term'] ?? v['id'] ?? '').toString().trim();
      final name = (v['name'] ?? v['label'] ?? '').toString().trim();
      if (slug.isNotEmpty && _isExactlyFirstFoodsToken(slug)) return true;
      if (name.isNotEmpty && _isExactlyFirstFoodsToken(name)) return true;

      // common nested list
      final terms = v['terms'] ?? v['items'] ?? v['values'];
      if (_containsExactFirstFoods(terms)) return true;

      // also scan values only (NOT keys)
      for (final entry in v.entries) {
        if (_containsExactFirstFoods(entry.value)) return true;
      }
      return false;
    }

    return false;
  }

  bool _isFirstFoodsRecipe(Map<String, dynamic> recipe) {
    final r = (recipe['recipe'] is Map)
        ? Map<String, dynamic>.from(recipe['recipe'] as Map)
        : recipe;

    // Prefer explicit taxonomies collections first
    final tax = r['taxonomies'];
    if (tax is Map) {
      // WPRM collections / custom collections
      if (_containsExactFirstFoods(tax['wprm_collections'])) return true;
      if (_containsExactFirstFoods(tax['collections'])) return true;

      // categories (only if explicitly tagged as first_foods)
      if (_containsExactFirstFoods(tax['categories'])) return true;
      if (_containsExactFirstFoods(tax['category'])) return true;

      // explicit custom key
      if (_containsExactFirstFoods(tax['first_foods'])) return true;
    }

    final tags = r['tags'];
    if (tags is Map) {
      if (_containsExactFirstFoods(tags['collections'])) return true;
      if (_containsExactFirstFoods(tags['categories'])) return true;
      if (_containsExactFirstFoods(tags['category'])) return true;
      if (_containsExactFirstFoods(tags['first_foods'])) return true;
    }

    // top-level fallbacks (string/list/map)
    if (_containsExactFirstFoods(r['wprm_collections'])) return true;
    if (_containsExactFirstFoods(r['collections'])) return true;
    if (_containsExactFirstFoods(r['categories'])) return true;
    if (_containsExactFirstFoods(r['category'])) return true;
    if (_containsExactFirstFoods(r['first_foods'])) return true;

    return false;
  }

  // -------------------------------------------------------
  // Candidate selection (courses + allergies + age + storage reuse)
  // -------------------------------------------------------
  List<int> getCandidatesForSlot(
    String slot,
    List<Map<String, dynamic>> recipes, {
    String audience = 'family', // 'family' | 'kids'
    DateTime? servingDate,
    Map<int, DateTime>? firstUsedDates,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
    List<dynamic>? children, // ✅ override (builder passes resolved children)
  }) {
    final normSlot = _normSlot(slot);
    final dt = servingDate ?? DateTime.now();

    // ✅ Choose children source deterministically:
    // 1) explicit override (builder)
    // 2) program children (if loaded)
    // 3) user doc fallback (cached)
    final effectiveChildren =
        (children != null && children.isNotEmpty) ? children : childrenEffectiveOrNull;
    final hasEffectiveChildren = (effectiveChildren?.isNotEmpty ?? false);

    final youngest = MealPlanAgeEngine.youngestAgeMonths(
      children: effectiveChildren,
      onDate: dt,
    );
    final isBaby = (youngest != null && youngest < babyThresholdMonths);

    // ✅ Snack slots should become kids-audience if we have children at all,
    // even if builder accidentally passes audience="family".
    final effectiveAudience =
        (normSlot.startsWith('snack') && hasEffectiveChildren)
            ? 'kids'
            : audience.toLowerCase().trim();

    // ✅ Focused + rate-limited per slot/day.
    final dayKey = dt.toIso8601String().substring(0, 10);
    mplog.MealPlanLog.i(
      'CANDIDATES_START slot=$normSlot audience=$audience effectiveAudience=$effectiveAudience '
      'day=$dayKey recipesIn=${recipes.length} youngest=$youngest isBaby=$isBaby '
      'threshold=$babyThresholdMonths hasChildren=$hasEffectiveChildren',
      key: 'candidates:$normSlot:$dayKey',
    );

    int dropAllergy = 0;
    int dropAgeGate = 0;
    int dropFirstFoods = 0;
    int dropCourse = 0;
    int dropStorage = 0;
    int dropNoId = 0;

    final out = <int>[];

    for (final r in recipes) {
      // 1) allergies
      if (!recipeAllowed(r)) {
        dropAllergy++;
        continue;
      }

      // 2) audience + age gate
      if (effectiveAudience == 'kids') {
        // ✅ Only force first_foods snacks when there is a baby
        if (isBaby && normSlot.startsWith('snack') && !_isFirstFoodsRecipe(r)) {
          dropFirstFoods++;
          continue;
        }

        final ok = MealPlanAgeEngine.allowRecipeForSlotUsingFirstFoodsGate(
          recipe: r,
          slotKey: normSlot,
          children: effectiveChildren,
          babyThresholdMonths: babyThresholdMonths,
          servingDate: dt,
        );
        if (!ok) {
          dropAgeGate++;
          continue;
        }
      }

      // 3) course matching
      final courseRaw = _extractCourse(r);
      final tokens = _courseTokens(courseRaw);
      if (tokens.isEmpty) {
        dropCourse++;
        continue;
      }

      if (normSlot.contains('breakfast') && !_isBreakfastCourseTokens(tokens)) {
        dropCourse++;
        continue;
      }

      if ((normSlot.contains('lunch') || normSlot.contains('dinner')) &&
          !_isMainsCourseTokens(tokens)) {
        dropCourse++;
        continue;
      }

      if (normSlot.contains('snack') && !_isSnacksCourseTokens(tokens)) {
        dropCourse++;
        continue;
      }

      // 4) id
      final id = recipeIdFromAny(r['id']);
      if (id == null || id <= 0) {
        dropNoId++;
        continue;
      }

      // 5) storage days reuse rule (batch cooking)
      if (firstUsedDates != null && firstUsedDates.containsKey(id)) {
        final storageDays = extractStorageDays(r);
        if (storageDays != null) {
          final first = firstUsedDates[id]!;
          final expires = first.add(Duration(days: storageDays));
          if (dt.isAfter(expires)) {
            dropStorage++;
            continue;
          }
        }
      }

      out.add(id);
    }

    mplog.MealPlanLog.i(
      'CANDIDATES_END slot=$normSlot kept=${out.length} dropAllergy=$dropAllergy '
      'dropFirstFoods=$dropFirstFoods dropAgeGate=$dropAgeGate dropCourse=$dropCourse '
      'dropStorage=$dropStorage dropNoId=$dropNoId',
      key: 'candidates:$normSlot:$dayKey',
    );

    return out;
  }

  // -------------------------------------------------------
  // Course extraction
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
    return _anyTokenContains(tokens, const ['mains', 'lunch', 'dinner', 'main']);
  }

  bool _isSnacksCourseTokens(List<String> tokens) {
    return _anyTokenContains(tokens, const ['snacks', 'snack']);
  }
}

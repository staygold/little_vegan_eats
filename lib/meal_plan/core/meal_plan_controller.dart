// lib/meal_plan/core/meal_plan_controller.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'meal_plan_age_engine.dart';
import 'meal_plan_keys.dart';
import 'meal_plan_log.dart' as mplog;
import 'meal_plan_repository.dart';
import 'meal_plan_slots.dart';

import '../../recipes/family_profile_repository.dart';
import '../../recipes/family_profile.dart';
import '../../recipes/profile_person.dart';

import '../../recipes/recipe_index.dart';
import '../../recipes/food_policy_core.dart';
import '../../recipes/allergy_engine.dart';

class MealPlanController extends ChangeNotifier {
  MealPlanController({
    required FirebaseAuth auth,
    required MealPlanRepository repo,
    required FamilyProfileRepository profileRepo,
    required Map<int, RecipeIndex> recipeIndexById,
    String? initialWeekId,
  })  : _auth = auth,
        _repo = repo,
        _profileRepo = profileRepo,
        _recipeIndexById = recipeIndexById,
        weekId = (initialWeekId != null && initialWeekId.trim().isNotEmpty)
            ? initialWeekId.trim()
            : MealPlanKeys.currentWeekId();

  final FirebaseAuth _auth;
  final MealPlanRepository _repo;
  final FamilyProfileRepository _profileRepo;
  final Map<int, RecipeIndex> _recipeIndexById;

  // -------------------------------------------------------
  // ✅ Debug switches
  // -------------------------------------------------------
  bool debugSuitability = true; // flip off when done
  int debugExampleIds = 6;

  void _dbgI(String msg, {String? key}) {
    if (!debugSuitability) return;
    mplog.MealPlanLog.i(msg, key: key);
  }

  void _dbgD(String msg, {String? key}) {
    if (!debugSuitability) return;
    mplog.MealPlanLog.d(msg, key: key);
  }

  // -------------------------------------------------------
  // Week view state
  // -------------------------------------------------------
  String weekId;
  bool isLoading = true;

  final Map<String, Map<String, dynamic>?> _dayDocCache = {};
  final Map<String, StreamSubscription<Map<String, dynamic>?>> _daySubs = {};
  final Map<String, String> _daySources = {};

  // Draft state (kept for UI edits)
  final Map<String, Map<String, Map<String, dynamic>>> _draft = {};

  // -------------------------------------------------------
  // Program state
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
  // ✅ Profile state (SSOT)
  // -------------------------------------------------------
  FamilyProfile? _family;
  StreamSubscription<FamilyProfile>? _familySub;

  int _adultCount = 2;

  int get adultCount => _adultCount;
  int get kidCount => _family?.children.length ?? 0;

  FamilyProfile? get family => _family;
  bool get hasChildren => (_family?.children.isNotEmpty ?? false);

  // -------------------------------------------------------
  // ✅ Profile readiness latch
  // -------------------------------------------------------
  Completer<void>? _profileReady;

  Future<void> get profileReady async {
    final c = _profileReady;
    if (c == null) return;
    if (c.isCompleted) return;
    await c.future;
  }

  bool get isProfileReady => _profileReady?.isCompleted ?? false;

  // -------------------------------------------------------
  // ✅ Children bridge (ProfilePerson -> Map<String,dynamic>)
  // -------------------------------------------------------
  Map<String, dynamic> _childToMap(ProfilePerson k) {
    final key = (k.key.isNotEmpty ? k.key : k.id).toString().trim();

    return <String, dynamic>{
      'dobMonth': k.dobMonth,
      'dobYear': k.dobYear,
      'dob': k.dob,
      'name': k.name,
      'childName': k.name,
      if (key.isNotEmpty) 'childKey': key,
      if (key.isNotEmpty) 'id': key,
      if (key.isNotEmpty) 'key': key,
      if (key.isNotEmpty) 'uid': key,
    };
  }

  /// ✅ Used by builder service.
  List<Map<String, dynamic>> get childrenEffectiveOrNull {
    final kids = _family?.children ?? const <ProfilePerson>[];
    if (kids.isEmpty) return const <Map<String, dynamic>>[];
    return kids.map(_childToMap).toList();
  }

  List<Map<String, dynamic>> _normalizeChildrenOverride(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const <Map<String, dynamic>>[];

    if (raw.first is Map) {
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    if (raw.first is ProfilePerson) {
      return raw.cast<ProfilePerson>().map(_childToMap).toList();
    }

    return const <Map<String, dynamic>>[];
  }

  // -------------------------------------------------------
  // ✅ Household allergy policy settings
  // -------------------------------------------------------
  bool _allergyPolicyEnabled = true;
  bool _includeSwaps = true;

  bool get allergyPolicyEnabled => _allergyPolicyEnabled;
  bool get includeSwaps => _includeSwaps;

  void setAllergyPolicy({
    bool? enabled,
    bool? includeSwaps,
  }) {
    if (enabled != null) _allergyPolicyEnabled = enabled;
    if (includeSwaps != null) _includeSwaps = includeSwaps;
    notifyListeners();
  }

  // -------------------------------------------------------
  // Lifecycle helpers
  // -------------------------------------------------------
  String get uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError('User not logged in');
    return u.uid;
  }

  RecipeIndex? indexForId(int id) => _recipeIndexById[id];

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
    _familySub?.cancel();

    _profileReady = Completer<void>();
    isLoading = true;

    _familySub = _profileRepo.watchFamilyProfile().listen((fam) {
      _family = fam;
      _adultCount = fam.adults.isEmpty ? 1 : fam.adults.length;

      final c = _profileReady;
      if (c != null && !c.isCompleted) c.complete();

      final youngest = MealPlanAgeEngine.youngestAgeMonths(
        children: childrenEffectiveOrNull,
        onDate: DateTime.now(),
      );

      mplog.MealPlanLog.i(
        'PROFILE_WIRED adults=$_adultCount kids=$kidCount youngest=$youngest',
        key: 'profile:wired',
      );

      notifyListeners();
    }, onError: (e) {
      final c = _profileReady;
      if (c != null && !c.isCompleted) c.complete();
      mplog.MealPlanLog.e('PROFILE_WATCH_ERROR $e');
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

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  Future<void> stop() async {
    await _programIdSub?.cancel();
    _programIdSub = null;

    await _programSub?.cancel();
    _programSub = null;

    await _familySub?.cancel();
    _familySub = null;

    _family = null;
    _adultCount = 2;

    _profileReady = null;

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
  // Program helpers
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
  // ✅ Day doc slot extraction (NEW SHAPE ONLY)
  // { slots: { breakfast: ..., lunch: ..., ... } }
  // -------------------------------------------------------
  static Map<String, dynamic> slotsFromAnyDayDoc(Map<String, dynamic>? doc) {
    if (doc == null) return <String, dynamic>{};

    final v = doc['slots'];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);

    return <String, dynamic>{};
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
        keys.contains('fromSlot') ||
        keys.contains('warning') ||
        keys.contains('warnings');
  }

  bool _slotHasRealContent(Map m) {
    final type = (m['type'] ?? m['kind'] ?? '').toString().trim().toLowerCase();

    if (type == 'clear' || type == 'cleared') return false;

    if (type == 'note') {
      final t = (m['text'] ?? '').toString().trim();
      return t.isNotEmpty;
    }

    if (type == 'recipe' || type == 'reuse') {
      return _isValidRecipeId(m['recipeId']) || _isValidRecipeId(m['id']);
    }

    if (_isValidRecipeId(m['recipeId']) || _isValidRecipeId(m['id'])) {
      return true;
    }

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
    }
    return false;
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

  String _normSlot(String slot) => slot.trim().toLowerCase();

  Map<String, dynamic>? firestoreEntry(String dayKey, String slot) {
    final dk = dayKey.trim();
    if (dk.isEmpty) return null;

    final s = _normSlot(slot);

    final doc = _dayDocCache[dk];
    final slots = slotsFromAnyDayDoc(doc);
    final raw = slots[s];

    if (raw == null) return null;

    if (raw is Map) return Map<String, dynamic>.from(raw);

    final rid = recipeIdFromAny(raw);
    if (rid != null && rid > 0) {
      return <String, dynamic>{
        'type': 'recipe',
        'recipeId': rid,
      };
    }

    return null;
  }

  int? entryRecipeId(Map<String, dynamic>? entry) {
    if (entry == null) return null;

    final rid =
        recipeIdFromAny(entry['recipeId']) ?? recipeIdFromAny(entry['id']);
    if (rid != null && rid > 0) return rid;

    final alt = recipeIdFromAny(entry['recipe_id']) ??
        recipeIdFromAny(entry['recipe']);
    if (alt != null && alt > 0) return alt;

    return null;
  }

  // -------------------------------------------------------
  // ✅ Allergy gating (WHOLE FAMILY default)
  // -------------------------------------------------------
  bool recipeAllowedForGeneration(Map<String, dynamic> recipe) {
    if (!_allergyPolicyEnabled) return true;

    final fam = _family;
    if (fam == null) return true;

    final id = recipeIdFromAny(recipe['id']);
    if (id == null || id <= 0) return false;

    final ix = _recipeIndexById[id];
    if (ix == null) return false;

    final profiles = <ProfilePerson>[
      ...fam.adults,
      ...fam.children,
    ];

    final anyAllergies =
        profiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);
    if (!anyAllergies) return true;

    final sel = AllergiesSelection(
      enabled: true,
      mode: SuitabilityMode.wholeFamily,
      includeSwaps: _includeSwaps,
      personIds: const <String>{},
    );

    return FoodPolicyCore.isAllowedForProfiles(
      ix: ix,
      profiles: profiles,
      selection: sel,
    );
  }

  bool recipeAllowed(Map<String, dynamic> recipe) =>
      recipeAllowedForGeneration(recipe);

  // -------------------------------------------------------
  // ✅ Allergy label (UI helper for meal plan cards)
  // Mirrors recipe list label logic via FoodPolicyCore.
  // -------------------------------------------------------
  String? allergySubtitleForRecipeId(int recipeId) {
    if (!_allergyPolicyEnabled) return null;

    final fam = _family;
    if (fam == null) return null;

    final ix = _recipeIndexById[recipeId];
    if (ix == null) return null;

    final activeProfiles = <ProfilePerson>[
      ...fam.adults,
      ...fam.children,
    ];

    final anyAllergies = activeProfiles.any(
      (p) => p.hasAllergies && p.allergies.isNotEmpty,
    );
    if (!anyAllergies) return null;

    final selection = AllergiesSelection(
      enabled: true,
      mode: SuitabilityMode.wholeFamily,
      includeSwaps: _includeSwaps,
      personIds: const <String>{},
    );

    final res = FoodPolicyCore.allergyTagForRecipe(
      ix: ix,
      activeProfiles: activeProfiles,
      selection: selection,
    );

    final tag = res.tag?.trim();
    if (tag == null || tag.isEmpty) return null;
    return tag;
  }

  // -------------------------------------------------------
  // ✅ ONE ENGINE: Candidate selection (SSOT)
  // - Kids audience => filter by TARGET CHILD (eldest if 2+)
  // - Family audience => NO age gating
  // - Snacks follow the same rules as meals
  // -------------------------------------------------------
  List<int> getCandidatesForSlotUnified(
    String slot,
    List<Map<String, dynamic>> recipes, {
    String audience = 'family',
    DateTime? servingDate,
    Map<int, DateTime>? firstUsedDates,
    int babyThresholdMonths = MealPlanAgeEngine.defaultBabyThresholdMonths,
    List<dynamic>? childrenOverride,
  }) {
    final normSlot = _normSlot(slot);
    final dt = servingDate ?? DateTime.now();

    final overrideKids = _normalizeChildrenOverride(childrenOverride);
    final effectiveChildren =
        overrideKids.isNotEmpty ? overrideKids : childrenEffectiveOrNull;

    final baseAudience = audience.toLowerCase().trim();
    final effectiveAudience = (baseAudience == 'kids') ? 'kids' : 'family';

    final dayKey = dt.toIso8601String().substring(0, 10);

    _dbgI(
      'SUITABILITY_START slot=$normSlot audience=$audience effectiveAudience=$effectiveAudience '
      'day=$dayKey recipesIn=${recipes.length} adults=$adultCount kids=${effectiveChildren.length} '
      'allergyEnabled=$_allergyPolicyEnabled includeSwaps=$_includeSwaps '
      'overrideKids=${overrideKids.isNotEmpty}',
      key: 'suitability:$normSlot:$dayKey',
    );

    int dropAllergy = 0;
    int dropAgeGate = 0;
    int dropCourse = 0;
    int dropStorage = 0;
    int dropNoId = 0;
    int dropNoIndex = 0;

    final exAllergy = <int>[];
    final exAge = <int>[];
    final exCourse = <int>[];
    final exStorage = <int>[];

    void addExample(List<int> list, int id) {
      if (!debugSuitability) return;
      if (list.length >= debugExampleIds) return;
      list.add(id);
    }

    // Helpful context for kids audience
    if (debugSuitability && effectiveAudience == 'kids') {
      final target =
          MealPlanAgeEngine.targetChildForKidsAudience(effectiveChildren, dt);
      final youngest = MealPlanAgeEngine.youngestChild(effectiveChildren, dt);
      _dbgI(
        'KIDS_CTX slot=$normSlot day=$dayKey '
        'kidsAges=${effectiveChildren.map((c) => "${c['name']}:${MealPlanAgeEngine.childAgeMonths(c, dt)}").toList()} '
        'target=${target?['name']} youngest=${youngest?['name']}',
        key: 'kidsCtx:$normSlot:$dayKey',
      );
    }

    final out = <int>[];

    for (final r in recipes) {
      final id = recipeIdFromAny(r['id']);
      if (id == null || id <= 0) {
        dropNoId++;
        continue;
      }

      final ix = _recipeIndexById[id];
      if (ix == null) {
        dropNoIndex++;
        continue;
      }

      // 1) Allergy gate
      if (!recipeAllowedForGeneration(r)) {
        dropAllergy++;
        addExample(exAllergy, id);
        continue;
      }

      // 2) Age gate ONLY in kids audience (SSOT: target child)
      // ✅ Also enforces baby-only strict rule: (6m + first_foods only)
      if (effectiveAudience == 'kids') {
        final ok = MealPlanAgeEngine.allowForKidsAudience(
          slotKey: normSlot,
          children: effectiveChildren,
          servingDate: dt,
          ix: ix,
          recipe: r,
          babyThresholdMonths: babyThresholdMonths,
        );

        if (!ok) {
          dropAgeGate++;
          addExample(exAge, id);
          continue;
        }
      }

      // 3) Course gate
      final courseRaw = _extractCourse(r);
      final tokens = _courseTokens(courseRaw);
      if (tokens.isEmpty) {
        dropCourse++;
        addExample(exCourse, id);
        continue;
      }

      if (normSlot.contains('breakfast') && !_isBreakfastCourseTokens(tokens)) {
        dropCourse++;
        addExample(exCourse, id);
        continue;
      }

      if ((normSlot.contains('lunch') || normSlot.contains('dinner')) &&
          !_isMainsCourseTokens(tokens)) {
        dropCourse++;
        addExample(exCourse, id);
        continue;
      }

      if (normSlot.contains('snack') && !_isSnacksCourseTokens(tokens)) {
        dropCourse++;
        addExample(exCourse, id);
        continue;
      }

      // 4) Storage window (reuse only if still within storageDays)
      if (firstUsedDates != null && firstUsedDates.containsKey(id)) {
        final storageDays = extractStorageDays(r);
        if (storageDays != null) {
          final first = firstUsedDates[id]!;
          final expires = first.add(Duration(days: storageDays));
          if (dt.isAfter(expires)) {
            dropStorage++;
            addExample(exStorage, id);
            continue;
          }
        }
      }

      out.add(id);
    }

    _dbgI(
      'SUITABILITY_END slot=$normSlot kept=${out.length} dropNoId=$dropNoId dropNoIndex=$dropNoIndex '
      'dropAllergy=$dropAllergy dropAgeGate=$dropAgeGate dropCourse=$dropCourse dropStorage=$dropStorage '
      'exAllergy=$exAllergy exAge=$exAge exCourse=$exCourse exStorage=$exStorage',
      key: 'suitabilityEnd:$normSlot:$dayKey',
    );

    return out;
  }

  // -------------------------------------------------------
  // Storage days taxonomy
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
  // Course parsing
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

  bool _isBreakfastCourseTokens(List<String> tokens) =>
      _anyTokenContains(tokens, const ['breakfast']);

  bool _isMainsCourseTokens(List<String> tokens) =>
      _anyTokenContains(tokens, const ['mains', 'lunch', 'dinner', 'main']);

  bool _isSnacksCourseTokens(List<String> tokens) =>
      _anyTokenContains(tokens, const ['snacks', 'snack']);
}

// lib/meal_plan/meal_plan_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/allergy_engine.dart';
import '../recipes/recipe_repository.dart';
// ✅ NEW IMPORTS FOR SEARCH ENGINE
import '../recipes/recipe_index.dart';
import '../recipes/recipe_index_builder.dart';
import '../utils/text.dart'; // Assuming you have this for stripHtml

import 'core/allergy_profile.dart';
import 'core/meal_plan_keys.dart';
import 'widgets/meal_plan_entry_parser.dart';
import 'widgets/meal_plan_shopping_sheet.dart';
import 'widgets/today_meal_plan_section.dart';

import 'choose_recipe_page.dart';
import 'reuse_recipe_page.dart';
import 'builder/meal_plan_builder_screen.dart';

import 'saved_meal_plans_screen.dart';

import '../recipes/family_profile_repository.dart';
import '../recipes/family_profile.dart';

class MealPlanScreen extends StatefulWidget {
  final String? weekId;
  final String? focusDayKey;

  const MealPlanScreen({
    super.key,
    this.weekId,
    this.focusDayKey,
  });

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen>
    with SingleTickerProviderStateMixin {
  bool _reviewMode = false;

  // Recipes & Index
  List<Map<String, dynamic>> _recipes = [];
  Map<int, RecipeIndex> _indexById = {}; // ✅ Stores the search index
  bool _recipesLoading = true;

  late TabController _tabController;

  // user data + favs
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};

  // Family Profile
  final FamilyProfileRepository _familyRepo = FamilyProfileRepository();
  StreamSubscription<FamilyProfile>? _familySub;
  List<String> _childNames = [];
  FamilyProfile _family = const FamilyProfile(adults: [], children: []); // ✅ Store full profile

  // Programs pointer
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;
  String? _activeProgramId;

  // active programme weekdays
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _programSub;
  Set<int> _programWeekdays = <int>{};

  // Effective day subscriptions
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _programDaySubs = {};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _adhocDaySubs = {};

  final Map<String, Map<String, dynamic>> _programDayCache = {};
  final Map<String, Map<String, dynamic>> _adhocDayCache = {};

  late DateTime _weekStart;

  final Map<String, List<int>> _recentBySlot = <String, List<int>>{};
  static const int _recentWindow = 12;

  final Set<String> _snack2HiddenDays = <String>{};

  Color get _brandDark => const Color(0xFF044246);
  Color get _brandPrimary => const Color(0xFF32998D);
  Color get _bg => const Color(0xFFECF3F4);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --------------------------
  // DATE HELPERS
  // --------------------------
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isPastDayKey(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return true;
    return _dateOnly(dt).isBefore(_dateOnly(DateTime.now()));
  }

  int? _weekdayFromDayKey(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    return dt?.weekday;
  }

  bool _isDayInProgramme(String dayKey) {
    if ((_activeProgramId ?? '').trim().isEmpty) return false;
    if (_programWeekdays.isEmpty) return false;
    final wd = _weekdayFromDayKey(dayKey);
    if (wd == null) return false;
    return _programWeekdays.contains(wd);
  }

  // --------------------------
  // WEEK LABEL
  // --------------------------
  String _monthShort(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final idx = (m - 1).clamp(0, 11);
    return months[idx];
  }

  String _weekRangeLabelFromStart(DateTime start) {
    final end = start.add(const Duration(days: 6));
    if (start.month == end.month) {
      return '${start.day}–${end.day} ${_monthShort(start.month)}';
    }
    return '${start.day} ${_monthShort(start.month)}–${end.day} ${_monthShort(end.month)}';
  }

  // --------------------------
  // FIRESTORE REFS
  // --------------------------
  DocumentReference<Map<String, dynamic>>? _settingsDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPlan')
        .doc('settings');
  }

  DocumentReference<Map<String, dynamic>> _programDoc(String programId) {
    final user = FirebaseAuth.instance.currentUser!;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPrograms')
        .doc(programId);
  }

  DocumentReference<Map<String, dynamic>> _programDayDoc({
    required String programId,
    required String dayKey,
  }) {
    final user = FirebaseAuth.instance.currentUser!;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPrograms')
        .doc(programId)
        .collection('mealProgramDays')
        .doc(dayKey);
  }

  DocumentReference<Map<String, dynamic>> _adhocDayDoc({
    required String dayKey,
  }) {
    final user = FirebaseAuth.instance.currentUser!;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealAdhocDays')
        .doc(dayKey);
  }

  // --------------------------
  // SUBSCRIPTIONS
  // --------------------------
  void _clearDaySubscriptions() {
    for (final sub in _programDaySubs.values) {
      sub.cancel();
    }
    for (final sub in _adhocDaySubs.values) {
      sub.cancel();
    }
    _programDaySubs.clear();
    _adhocDaySubs.clear();
    _programDayCache.clear();
    _adhocDayCache.clear();
  }

  void _listenVisibleWeekDays() {
    final pid = (_activeProgramId ?? '').trim();

    final dayKeys = _visibleWeekDayKeys();
    final wanted = dayKeys.toSet();

    final existingP = _programDaySubs.keys.toList();
    for (final k in existingP) {
      if (!wanted.contains(k)) {
        _programDaySubs[k]?.cancel();
        _programDaySubs.remove(k);
        _programDayCache.remove(k);
      }
    }

    final existingA = _adhocDaySubs.keys.toList();
    for (final k in existingA) {
      if (!wanted.contains(k)) {
        _adhocDaySubs[k]?.cancel();
        _adhocDaySubs.remove(k);
        _adhocDayCache.remove(k);
      }
    }

    for (final dk in dayKeys) {
      if (_adhocDaySubs.containsKey(dk)) continue;

      final ref = _adhocDayDoc(dayKey: dk);
      _adhocDaySubs[dk] = ref.snapshots().listen((snap) {
        final data = snap.data();
        final rawSlots = data?['slots'];

        final Map<String, dynamic> slots = (rawSlots is Map)
            ? Map<String, dynamic>.from(rawSlots)
            : <String, dynamic>{};

        if (!mounted) return;
        setState(() {
          if (!snap.exists) {
            _adhocDayCache.remove(dk);
          } else {
            _adhocDayCache[dk] = slots;
          }
        });
      });
    }

    if (pid.isNotEmpty) {
      for (final dk in dayKeys) {
        if (_programDaySubs.containsKey(dk)) continue;

        final ref = _programDayDoc(programId: pid, dayKey: dk);
        _programDaySubs[dk] = ref.snapshots().listen((snap) {
          final data = snap.data();
          final rawSlots = data?['slots'];

          final Map<String, dynamic> slots = (rawSlots is Map)
              ? Map<String, dynamic>.from(rawSlots)
              : <String, dynamic>{};

          if (!mounted) return;
          setState(() {
            if (!snap.exists) {
              _programDayCache.remove(dk);
            } else {
              _programDayCache[dk] = slots;
            }
          });
        });
      }
    } else {
      for (final dk in dayKeys) {
        _programDayCache.remove(dk);
      }
    }
  }

  List<String> _visibleWeekDayKeys() {
    final out = <String>[];
    for (int i = 0; i < 7; i++) {
      final dt = _weekStart.add(Duration(days: i));
      out.add(MealPlanKeys.dayKey(dt));
    }
    return out;
  }

  Future<void> _shiftWeekBy(int deltaWeeks) async {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks));
    });

    _listenVisibleWeekDays();

    if (mounted) {
      _tabController.animateTo(0);
    }
  }

  // --------------------------
  // INIT / DISPOSE
  // --------------------------
  @override
  void initState() {
    super.initState();

    final focusKey = (widget.focusDayKey != null &&
            widget.focusDayKey!.trim().isNotEmpty)
        ? widget.focusDayKey!.trim()
        : MealPlanKeys.todayKey();

    final focusDate = MealPlanKeys.parseDayKey(focusKey) ?? DateTime.now();
    _weekStart = MealPlanKeys.startOfWeek(_dateOnly(focusDate));

    _tabController = TabController(length: 7, vsync: this);

    final weekKeys = _visibleWeekDayKeys();
    final initialIndex = weekKeys.indexOf(focusKey);
    if (initialIndex != -1) {
      _tabController.index = initialIndex;
    }

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {});
      }
    });

    () async {
      await _loadRecipes();
      _startUserDocAllergyListener();
      _startFavoritesListener();
      _startSettingsListener();
      _startFamilyListener();
    }();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    _reviewMode = (args is Map && args['review'] == true);
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _favSub?.cancel();
    _settingsSub?.cancel();
    _programSub?.cancel();
    _familySub?.cancel(); 
    _clearDaySubscriptions();
    _tabController.dispose();
    super.dispose();
  }

  // --------------------------
  // DATA LOADERS
  // --------------------------
  void _startSettingsListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = _settingsDoc();
    if (doc == null) return;

    _settingsSub?.cancel();
    _settingsSub = doc.snapshots().listen((snap) {
      final data = snap.data() ?? <String, dynamic>{};
      final next = (data['activeProgramId'] ?? '').toString().trim();

      if (!mounted) return;

      final changed = next != (_activeProgramId ?? '');
      if (!changed) return;

      setState(() {
        _activeProgramId = next.isEmpty ? null : next;

        _programSub?.cancel();
        _programWeekdays = <int>{};

        if ((_activeProgramId ?? '').trim().isNotEmpty) {
          final pid = _activeProgramId!.trim();
          _programSub = _programDoc(pid).snapshots().listen((psnap) {
            final pdata = psnap.data() ?? <String, dynamic>{};
            final raw = pdata['weekdays'];

            final nextDays = <int>{};
            if (raw is List) {
              for (final v in raw) {
                final n = (v is int) ? v : int.tryParse(v.toString());
                if (n != null && n >= 1 && n <= 7) nextDays.add(n);
              }
            }

            if (!mounted) return;
            setState(() {
              _programWeekdays = nextDays;
            });
          });
        }

        _clearDaySubscriptions();
        _listenVisibleWeekDays();
      });
    });
  }

  void _startUserDocAllergyListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userDocSub?.cancel();
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) {
      final sets = AllergyProfile.buildFromUserDoc(snap.data());
      _excludedAllergens
        ..clear()
        ..addAll(sets.excludedAllergens);
      _childAllergens
        ..clear()
        ..addAll(sets.childAllergens);

      if (mounted) setState(() {});
    });
  }

  void _startFavoritesListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _favSub?.cancel();
    _favSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .snapshots()
        .listen((snap) {
      final next = <int>{};
      for (final d in snap.docs) {
        final raw = d.data()['recipeId'];
        final id = (raw is int) ? raw : int.tryParse(raw?.toString() ?? '');
        if (id != null && id > 0) next.add(id);
      }
      if (!mounted) return;
      setState(() {
        _favoriteIds
          ..clear()
          ..addAll(next);
      });
    });
  }

  // ✅ Updated listener to capture full FamilyProfile
  void _startFamilyListener() {
    _familySub?.cancel();
    _familySub = _familyRepo.watchFamilyProfile().listen((fam) {
      if (!mounted) return;
      setState(() {
        _family = fam; // Store full object
        _childNames = fam.children.map((c) => c.name).toList();
      });
    });
  }

  // ✅ UPDATED: Load recipes AND build index
  Future<void> _loadRecipes() async {
    try {
      final loaded = await RecipeRepository.ensureRecipesLoaded();
      
      // Build index on the fly so Search/Filters work
      final normalised = loaded.map((r) => _normaliseForIndex(r)).where((m) => m.isNotEmpty).toList();
      final newIndex = RecipeIndexBuilder.buildById(normalised);

      if (mounted) {
        setState(() {
          _recipes = loaded;
          _indexById = newIndex;
          _recipesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _recipes = [];
          _indexById = {};
          _recipesLoading = false;
        });
      }
    } 
  }

  // ✅ Helper to normalize data for RecipeIndexBuilder (Simplified for MealPlan)
  Map<String, dynamic> _normaliseForIndex(Map<String, dynamic> r) {
    final id = r['id'];
    if (id is! int) return const {};

    // Helper to extract text tags from WPRM taxonomies if "names" map isn't available
    List<String> extractTags(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
    }

    // Try to get nice names from the 'tags' object first
    List<String> getTags(String key) {
       try {
         final recipe = r['recipe'];
         if (recipe is Map && recipe['tags'] is Map) {
           final t = recipe['tags'][key];
           if (t is List) {
             return t.map((x) => (x is Map ? x['name'] : x).toString()).toList();
           }
         }
       } catch (_) {}
       // Fallback to raw IDs if needed, though less ideal for UI filtering
       return extractTags(r['wprm_$key']); 
    }

    String swapText = '';
    if (r['ingredient_swaps'] != null) swapText = r['ingredient_swaps'].toString();
    else if (r['meta'] is Map && r['meta']['ingredient_swaps'] != null) {
      swapText = r['meta']['ingredient_swaps'].toString();
    }

    return <String, dynamic>{
      'id': id,
      'title': _titleOf(r),
      'ingredients': _ingredientsTextOf(r),
      'wprm_course': getTags('course'), // try 'course' first
      'wprm_collections': getTags('collection'), 
      'wprm_cuisine': getTags('cuisine'),
      'wprm_suitable_for': getTags('suitable_for'), // or 'age'?
      'wprm_nutrition_tag': getTags('nutrition'),
      'recipe': r['recipe'],
      'meta': r['meta'],
      'ingredient_swaps': swapText,
      'wprm_allergies': getTags('allergies'), 
    };
  }
  
  String _ingredientsTextOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is! Map) return '';
    final flat = recipe['ingredients_flat'];
    if (flat is! List) return '';
    final buf = StringBuffer();
    for (final row in flat) {
      if (row is! Map) continue;
      final name = (row['name'] ?? '').toString();
      if (name.isNotEmpty) buf.write('$name ');
    }
    return buf.toString().trim();
  }


  // --------------------------
  // ALLERGY + RECIPE HELPERS
  // --------------------------
  final Set<String> _excludedAllergens = <String>{};
  final Set<String> _childAllergens = <String>{};

  int? _recipeIdFrom(Map<String, dynamic> r) =>
      MealPlanEntryParser.recipeIdFromAny(r['id']);

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && (t['rendered'] is String)) {
      final s = (t['rendered'] as String).trim();
      if (s.isNotEmpty) return s;
    }
    return 'Untitled';
  }

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.trim().isNotEmpty) return url.trim();
    }
    return null;
  }

  String _weekdayLetter(DateTime dt) => MealPlanKeys.weekdayLetter(dt);

  // --------------------------
  // EFFECTIVE DAY
  // --------------------------
  bool _isAdhocActive(String dayKey) => _adhocDayCache.containsKey(dayKey);

  Map<String, dynamic> _baseSlotsForDay(String dayKey) {
    final adhoc = _adhocDayCache[dayKey];
    if (adhoc != null) return adhoc;

    final prog = _programDayCache[dayKey];
    if (prog != null) return prog;

    return <String, dynamic>{};
  }

  Map<String, dynamic> _dayRawForUI(String dayKey) {
    final raw = _baseSlotsForDay(dayKey);
    if (raw.isEmpty) return <String, dynamic>{};

    final out = <String, dynamic>{};
    for (final entry in raw.entries) {
      final k = entry.key.toString();
      if (k == 'snack2' && _snack2HiddenDays.contains(dayKey)) continue;
      out[k] = entry.value;
    }
    return out;
  }

  // --------------------------
  // WRITE HELPERS (Methods omitted for brevity, they remain unchanged)
  // --------------------------
  // ... _ensureProgramDayDocExists, _ensureAdhocDayDocExists, _setSlotEntry, etc. 
  // (Pasting strictly the changed logic below and keeping structure)
  
  Future<void> _ensureProgramDayDocExists(String dayKey) async {
    final user = FirebaseAuth.instance.currentUser;
    final pid = (_activeProgramId ?? '').trim();
    if (user == null || pid.isEmpty) return;

    final ref = _programDayDoc(programId: pid, dayKey: dayKey);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set({
      'dayKey': dayKey,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'slots': <String, dynamic>{},
    }, SetOptions(merge: true));
  }

  Future<void> _ensureAdhocDayDocExists(String dayKey) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = _adhocDayDoc(dayKey: dayKey);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set({
      'type': 'adhoc',
      'dayKey': dayKey,
      'dateKey': dayKey,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'slots': <String, dynamic>{},
    }, SetOptions(merge: true));
  }

  Future<void> _setSlotEntryProgram({
    required String dayKey,
    required String slot,
    required Map<String, dynamic> entry,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final pid = (_activeProgramId ?? '').trim();
    if (user == null || pid.isEmpty) return;

    await _ensureProgramDayDocExists(dayKey);

    final ref = _programDayDoc(programId: pid, dayKey: dayKey);
    await ref.set({
      'updatedAt': FieldValue.serverTimestamp(),
      'slots': {slot: entry},
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      final current = Map<String, dynamic>.from(
          _programDayCache[dayKey] ?? const <String, dynamic>{});
      current[slot] = entry;
      _programDayCache[dayKey] = current;
    });
  }

  Future<void> _clearSlotEntryProgram({
    required String dayKey,
    required String slot,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final pid = (_activeProgramId ?? '').trim();
    if (user == null || pid.isEmpty) return;

    await _ensureProgramDayDocExists(dayKey);

    final ref = _programDayDoc(programId: pid, dayKey: dayKey);
    await ref.update({
      'updatedAt': FieldValue.serverTimestamp(),
      'slots.$slot': FieldValue.delete(),
    });

    if (!mounted) return;
    setState(() {
      final current = Map<String, dynamic>.from(
          _programDayCache[dayKey] ?? const <String, dynamic>{});
      current.remove(slot);
      _programDayCache[dayKey] = current;
    });
  }

  Future<void> _setSlotEntryAdhoc({
    required String dayKey,
    required String slot,
    required Map<String, dynamic> entry,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _ensureAdhocDayDocExists(dayKey);

    final ref = _adhocDayDoc(dayKey: dayKey);
    await ref.set({
      'updatedAt': FieldValue.serverTimestamp(),
      'slots': {slot: entry},
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      final current = Map<String, dynamic>.from(
          _adhocDayCache[dayKey] ?? const <String, dynamic>{});
      current[slot] = entry;
      _adhocDayCache[dayKey] = current;
    });
  }

  Future<void> _clearSlotEntryAdhoc({
    required String dayKey,
    required String slot,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_adhocDayCache.containsKey(dayKey)) return;

    final ref = _adhocDayDoc(dayKey: dayKey);
    await ref.set({'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
    await ref.update({'slots.$slot': FieldValue.delete()});

    if (!mounted) return;
    setState(() {
      final current = Map<String, dynamic>.from(
          _adhocDayCache[dayKey] ?? const <String, dynamic>{});
      current.remove(slot);
      if (current.isEmpty) {
        _adhocDayCache.remove(dayKey);
      } else {
        _adhocDayCache[dayKey] = current;
      }
    });
  }

  Future<void> _setSlotEntry({
    required String dayKey,
    required String slot,
    required Map<String, dynamic> entry,
  }) async {
    if (_isAdhocActive(dayKey)) {
      await _setSlotEntryAdhoc(dayKey: dayKey, slot: slot, entry: entry);
    } else {
      await _setSlotEntryProgram(dayKey: dayKey, slot: slot, entry: entry);
    }
  }

  Future<void> _clearSlotEntry({
    required String dayKey,
    required String slot,
  }) async {
    if (_isAdhocActive(dayKey)) {
      await _clearSlotEntryAdhoc(dayKey: dayKey, slot: slot);
    } else {
      await _clearSlotEntryProgram(dayKey: dayKey, slot: slot);
    }
  }

  // --------------------------
  // HEADER ACTION
  // --------------------------
  void _openPlanSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedMealPlansScreen()),
    );
  }

  // --------------------------
  // AD-HOC ACTIONS
  // --------------------------
  Future<void> _saveDayAsAdhoc(String dayKey) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final currentSlots = _dayRawForUI(dayKey);
    if (currentSlots.isEmpty) {
      _snack('Nothing to save yet');
      return;
    }

    await _adhocDayDoc(dayKey: dayKey).set({
      'type': 'adhoc',
      'dayKey': dayKey,
      'dateKey': dayKey,
      'slots': currentSlots,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      _adhocDayCache[dayKey] = Map<String, dynamic>.from(currentSlots);
    });

    _snack('Saved as a one-off day');
  }

  Future<void> _revertAdhocToProgram(String dayKey) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_adhocDayCache.containsKey(dayKey)) {
      _snack('No one-off day to revert');
      return;
    }

    await _adhocDayDoc(dayKey: dayKey).delete();

    if (!mounted) return;
    setState(() {
      _adhocDayCache.remove(dayKey);
    });

    _snack('Reverted to programme');
  }

  // --------------------------
  // SNAPSHOTS
  // --------------------------
  List<String> _slotsForSnapshot(String dayKey) {
    final out = <String>['breakfast', 'lunch', 'dinner', 'snack1'];
    if (_snack2HiddenDays.contains(dayKey)) return out;

    final day = _dayRawForUI(dayKey);
    if (day.containsKey('snack2')) out.add('snack2');
    return out;
  }

  Map<String, dynamic>? _snapshotSlotEntry(String dayKey, String slot) {
    if (slot == 'snack2' && _snack2HiddenDays.contains(dayKey)) return null;

    final raw = _dayRawForUI(dayKey)[slot];
    final e = MealPlanEntryParser.parse(raw);
    if (e == null) return null;

    final rid = MealPlanEntryParser.entryRecipeId(e);
    if (rid != null) {
      String src = '';
      if (raw != null && raw is Map) {
        final m = <String, dynamic>{};
        for (final entry in raw.entries) {
          m[entry.key.toString()] = entry.value;
        }
        src = (m['source'] ?? m['src'] ?? '').toString();
      }

      return {
        'kind': 'recipe',
        'id': rid,
        if (src.trim().isNotEmpty) 'source': src.trim(),
        if (MealPlanEntryParser.entryReuseFrom(e) != null)
          'reuseFrom': MealPlanEntryParser.entryReuseFrom(e),
      };
    }

    final note = (MealPlanEntryParser.entryNoteText(e) ?? '').trim();
    if (note.isEmpty) return null;
    return {
      'kind': 'note',
      'text': note,
      if (MealPlanEntryParser.entryReuseFrom(e) != null)
        'reuseFrom': MealPlanEntryParser.entryReuseFrom(e),
    };
  }

  Map<String, dynamic> _snapshotDay(String dayKey) {
    final out = <String, dynamic>{};
    for (final slot in _slotsForSnapshot(dayKey)) {
      final snap = _snapshotSlotEntry(dayKey, slot);
      if (snap != null) out[slot] = snap;
    }
    return out;
  }

  void _openShoppingSheet() {
    final dayKeys = _visibleWeekDayKeys();
    final days = <String, dynamic>{};
    for (final dk in dayKeys) {
      days[dk] = _snapshotDay(dk);
    }
    final planData = {'type': 'week', 'days': days};

    final knownTitles = <int, String>{};
    for (final r in _recipes) {
      final id = _recipeIdFrom(r);
      final title = _titleOf(r);
      if (id != null) knownTitles[id] = title;
    }

    MealPlanShoppingSheet.show(context, planData, knownTitles);
  }

  // --------------------------
  // REUSE + CHOOSE + NOTE + CLEAR
  // --------------------------
  String _prettySlotLabel(String slot) {
    switch (slot.toLowerCase().trim()) {
      case 'breakfast':
        return 'BREAKFAST';
      case 'lunch':
        return 'LUNCH';
      case 'dinner':
        return 'DINNER';
      case 'snack1':
        return 'SNACK 1';
      case 'snack2':
        return 'SNACK 2';
      default:
        return slot.toUpperCase();
    }
  }

  Future<void> _reuseFromAnotherDay({
    required String dayKey,
    required String slot,
  }) async {
    final headerLabel =
        '${_prettySlotLabel(slot)} • ${MealPlanKeys.formatPretty(dayKey)}';

    final weekDayKeys = _visibleWeekDayKeys();
    final currentIndex = weekDayKeys.indexOf(dayKey);

    final candidates = <ReuseCandidate>[];

    for (var i = 0; i < weekDayKeys.length; i++) {
      final dk = weekDayKeys[i];
      if (currentIndex >= 0 && i >= currentIndex) break;

      final resolved = _dayRawForUI(dk)[slot];
      final parsed = MealPlanEntryParser.parse(resolved);
      final rid = MealPlanEntryParser.entryRecipeId(parsed);
      if (rid == null) continue;

      String title = 'Recipe';
      for (final r in _recipes) {
        final id = _recipeIdFrom(r);
        if (id == rid) {
          title = _titleOf(r);
          break;
        }
      }

      candidates.add(
        ReuseCandidate(
          sourceDayKey: dk,
          sourceSlot: slot,
          recipeId: rid,
          recipeTitle: title,
        ),
      );
    }

    if (candidates.isEmpty) {
      if (!mounted) return;
      _snack('No earlier meals to reuse yet');
      return;
    }

    final picked = await Navigator.of(context).push<ReusePick>(
      MaterialPageRoute(
        builder: (_) => ReuseRecipePage(
          headerLabel: headerLabel,
          candidates: candidates,
          formatDayPretty: MealPlanKeys.formatPretty,
        ),
      ),
    );

    if (picked == null) return;

    await _setSlotEntry(
      dayKey: dayKey,
      slot: slot,
      entry: {
        'type': 'reuse',
        'dayKey': picked.fromDayKey,
        'slot': picked.fromSlot,
        'source': 'reuse',
      },
    );
  }

  // ✅ UPDATED: Call the new ChooseRecipePage
  Future<void> _chooseRecipe({
    required String dayKey,
    required String slot,
  }) async {
    final currentParsed = MealPlanEntryParser.parse(_dayRawForUI(dayKey)[slot]);
    final currentId = MealPlanEntryParser.entryRecipeId(currentParsed);

    final headerLabel = '${_prettySlotLabel(slot)} • ${MealPlanKeys.formatPretty(dayKey)}';

    // Map slot to initial course if possible
    String courseFilter = 'All';
    if (slot.toLowerCase() == 'breakfast') courseFilter = 'Breakfast';
    else if (slot.toLowerCase().contains('snack')) courseFilter = 'Snacks';
    else courseFilter = 'Main Course'; // Lunch/Dinner

    // Call the new page
    final pickedId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ChooseRecipePage(
          recipes: _recipes,
          indexById: _indexById,
          familyProfile: _family,
          headerLabel: headerLabel,
          currentId: currentId,
          initialCourse: courseFilter,
        ),
      ),
    );

    if (pickedId != null) {
      if (slot == 'snack2') _snack2HiddenDays.remove(dayKey);
      await _setSlotEntry(
        dayKey: dayKey,
        slot: slot,
        entry: {'type': 'recipe', 'recipeId': pickedId, 'source': 'manual'},
      );
    }
  }

  Future<void> _addOrEditNote({
    required String dayKey,
    required String slot,
    String? initial,
  }) async {
    final textCtrl = TextEditingController(text: initial ?? '');
    final result = await showDialog<_NoteResult>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: "e.g. Out for dinner"),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _NoteResult.cancel()),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(_NoteResult.save(textCtrl.text)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (result == null || result.kind == _NoteResultKind.cancel) return;
    final text = (result.text ?? '').trim();
    if (text.isEmpty) return;

    await _setSlotEntry(
      dayKey: dayKey,
      slot: slot,
      entry: {'type': 'note', 'text': text, 'source': 'note'},
    );
  }

  Future<void> _clearSlot({
    required String dayKey,
    required String slot,
  }) async {
    if (slot == 'snack2') {
      setState(() => _snack2HiddenDays.add(dayKey));
      await _clearSlotEntry(dayKey: dayKey, slot: 'snack2');
      return;
    }
    await _clearSlotEntry(dayKey: dayKey, slot: slot);
  }

  // --------------------------
  // BACK HANDLING + EMPTY STATES (UNCHANGED)
  // --------------------------
  Future<bool> _handleBack() async {
    if (_reviewMode) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return false;
    }
    return true;
  }

  Widget _addThisDayToProgrammeButton(String dayKey) {
    final hasActiveProgram = (_activeProgramId ?? '').trim().isNotEmpty;

    if (_reviewMode) return const SizedBox.shrink();
    if (!hasActiveProgram) return const SizedBox.shrink();
    if (_isPastDayKey(dayKey)) return const SizedBox.shrink();
    if (_isDayInProgramme(dayKey)) return const SizedBox.shrink();

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _openPlanSettings,
        style: OutlinedButton.styleFrom(
          foregroundColor: _brandPrimary,
          side: BorderSide(color: _brandPrimary, width: 2),
          shape: const StadiumBorder(),
        ),
        child: const Text(
          'ADD THIS DAY TO MY PROGRAMME',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _emptyDayCta(String dayKey) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 10),
                blurRadius: 24,
                color: Color.fromRGBO(0, 0, 0, 0.08),
              )
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No meal plan for this day yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a plan for this day to add meals and snacks.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: Colors.black.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_isPastDayKey(dayKey)) return;

                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MealPlanBuilderScreen(
                          weekId: MealPlanKeys.weekIdForDate(
                            MealPlanKeys.parseDayKey(dayKey) ?? DateTime.now(),
                          ),
                          entry: MealPlanBuilderEntry.adhocDay,
                          initialSelectedDayKey: dayKey,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandPrimary,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    'CREATE A ONE-OFF DAY',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _addThisDayToProgrammeButton(dayKey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pastEmptyDayCard(String dayKey) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withOpacity(0.08), width: 1),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Past day (no plan)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You can’t add a new plan to past days.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: Colors.black.withOpacity(0.45),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getCurrentHeaderTitle() {
    final dayKeys = _visibleWeekDayKeys();
    if (dayKeys.isEmpty) return '';

    final idx = _tabController.index.clamp(0, dayKeys.length - 1);
    final dk = dayKeys[idx];
    return 'Day ${idx + 1} • ${MealPlanKeys.formatPretty(dk)}';
  }

  Widget _oneOffActionRow(String dayKey) {
    if (_reviewMode) return const SizedBox.shrink();

    final adhocActive = _isAdhocActive(dayKey);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          if (adhocActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _brandPrimary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'ONE-OFF DAY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                  color: _brandPrimary,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'PROGRAMME DAY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
            ),
          const Spacer(),
          if (adhocActive)
            TextButton(
              onPressed: () => _revertAdhocToProgram(dayKey),
              child: const Text('Revert'),
            )
          else
            TextButton(
              onPressed: () => _saveDayAsAdhoc(dayKey),
              child: const Text('Save as one-off'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Log in to view your meal plan')),
      );
    }
    if (_recipesLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasActiveProgram = (_activeProgramId ?? '').trim().isNotEmpty;

    if (_adhocDaySubs.isEmpty || (hasActiveProgram && _programDaySubs.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listenVisibleWeekDays();
      });
    }

    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(
              _reviewMode ? Icons.close : Icons.arrow_back,
              color: _brandDark,
            ),
            onPressed: () async {
              final ok = await _handleBack();
              if (ok && mounted) Navigator.of(context).maybePop();
            },
          ),
          title: const Text(''),
          elevation: 0,
          actions: _reviewMode
              ? []
              : [
                  IconButton(
                    tooltip: 'Edit plan',
                    icon: Icon(Icons.tune_rounded, color: _brandDark),
                    onPressed: _openPlanSettings,
                  ),
                  IconButton(
                    tooltip: 'Shopping List',
                    icon: Icon(Icons.shopping_cart_outlined, color: _brandDark),
                    onPressed: _openShoppingSheet,
                  ),
                ],
        ),
        body: !hasActiveProgram
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No active meal plan yet',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _brandDark,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Create a plan to start adding meals.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withOpacity(0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MealPlanBuilderScreen(
                                  weekId: MealPlanKeys.currentWeekId(),
                                  entry: MealPlanBuilderEntry.choose,
                                  initialSelectedDayKey: MealPlanKeys.todayKey(),
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandPrimary,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'BUILD A MEAL PLAN',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : () {
                Widget buildDay(String dayKey) {
                  final dayRaw = _dayRawForUI(dayKey);

                  if (dayRaw.isEmpty && _isPastDayKey(dayKey)) {
                    return _pastEmptyDayCard(dayKey);
                  }
                  if (dayRaw.isEmpty) {
                    return _emptyDayCta(dayKey);
                  }

                  final allowReuse = _visibleWeekDayKeys().first != dayKey;

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 0),
                    children: [
                      _oneOffActionRow(dayKey),
                      TodayMealPlanSection(
                        todayRaw: dayRaw,
                        recipes: _recipes,
                        favoriteIds: _favoriteIds,
                        heroTopText: '',
                        heroBottomText: '',
                        planTitle: '',
                        programmeActive: hasActiveProgram,
                        dayInProgramme: _isDayInProgramme(dayKey),
                        childNames: _childNames,
                        onAddAdhocDay: () async {
                          if (_isPastDayKey(dayKey)) return;
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MealPlanBuilderScreen(
                                weekId: MealPlanKeys.weekIdForDate(
                                  MealPlanKeys.parseDayKey(dayKey) ?? DateTime.now(),
                                ),
                                entry: MealPlanBuilderEntry.adhocDay,
                                initialSelectedDayKey: dayKey,
                              ),
                            ),
                          );
                        },
                        onBuildMealPlan: () {
                          if (_isPastDayKey(dayKey)) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MealPlanBuilderScreen(
                                weekId: MealPlanKeys.weekIdForDate(
                                  MealPlanKeys.parseDayKey(dayKey) ?? DateTime.now(),
                                ),
                                entry: MealPlanBuilderEntry.adhocDay,
                                initialSelectedDayKey: dayKey,
                              ),
                            ),
                          );
                        },
                        homeAccordion: true,
                        homeAlwaysExpanded: true,
                        onChooseSlot: (slot) => _chooseRecipe(dayKey: dayKey, slot: slot),
                        onReuseSlot: allowReuse
                            ? (slot) => _reuseFromAnotherDay(dayKey: dayKey, slot: slot)
                            : null,
                        onNoteSlot: (slot) async {
                          final initial = MealPlanEntryParser.entryNoteText(
                            MealPlanEntryParser.parse(_dayRawForUI(dayKey)[slot]),
                          );
                          await _addOrEditNote(dayKey: dayKey, slot: slot, initial: initial);
                        },
                        onClearSlot: (slot) => _clearSlot(dayKey: dayKey, slot: slot),
                        onAddAnotherSnack: () => _chooseRecipe(dayKey: dayKey, slot: 'snack2'),
                        canSave: false,
                        onSaveChanges: null,
                      ),
                    ],
                  );
                }

                final dayKeys = _visibleWeekDayKeys();
                final weekLabel = _weekRangeLabelFromStart(_weekStart);

                return Column(
                  children: [
                    if (!_reviewMode)
                      _WeekHeaderRow(
                        weekLabel: weekLabel,
                        brandDark: _brandDark,
                        onPrev: () => _shiftWeekBy(-1),
                        onNext: () => _shiftWeekBy(1),
                      ),
                    _WeekPillStripWithController(
                      controller: _tabController,
                      dayKeys: dayKeys,
                      weekdayLetter: _weekdayLetter,
                      brandDark: _brandDark,
                      brandPrimary: _brandPrimary,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _getCurrentHeaderTitle(),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _brandDark,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          for (final dayKey in dayKeys) buildDay(dayKey),
                        ],
                      ),
                    ),
                  ],
                );
              }(),
      ),
    );
  }
}

// -------------------------------------------------------
// UI helpers used by this file
// -------------------------------------------------------
class _WeekHeaderRow extends StatelessWidget {
  final String weekLabel;
  final Color brandDark;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _WeekHeaderRow({
    required this.weekLabel,
    required this.brandDark,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous week',
            icon: Icon(Icons.chevron_left, color: brandDark),
            onPressed: onPrev,
          ),
          Expanded(
            child: Text(
              weekLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: brandDark,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: 'Next week',
            icon: Icon(Icons.chevron_right, color: brandDark),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _WeekPillStripWithController extends StatelessWidget {
  final TabController controller;
  final List<String> dayKeys;
  final String Function(DateTime) weekdayLetter;

  final Color brandDark;
  final Color brandPrimary;

  const _WeekPillStripWithController({
    required this.controller,
    required this.dayKeys,
    required this.weekdayLetter,
    required this.brandDark,
    required this.brandPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final todayKey = MealPlanKeys.todayKey();

    return ClipRect(
      child: SizedBox(
        height: 86,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: controller,
          builder: (ctx, _) {
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              scrollDirection: Axis.horizontal,
              itemCount: dayKeys.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final dk = dayKeys[i];
                final date = MealPlanKeys.parseDayKey(dk) ?? DateTime.now();
                final isToday = dk == todayKey;
                final selected = controller.index == i;

                return _PillDayTab(
                  weekday: weekdayLetter(date),
                  dayNumber: date.day.toString(),
                  selected: selected,
                  isToday: isToday,
                  brandDark: brandDark,
                  brandPrimary: brandPrimary,
                  onTap: () => controller.animateTo(i),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PillDayTab extends StatelessWidget {
  final String weekday;
  final String dayNumber;
  final bool selected;
  final bool isToday;
  final Color brandDark;
  final Color brandPrimary;
  final VoidCallback onTap;

  const _PillDayTab({
    required this.weekday,
    required this.dayNumber,
    required this.selected,
    required this.isToday,
    required this.brandDark,
    required this.brandPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? brandDark : Colors.white;
    final fg = selected ? Colors.white : brandDark;

    final borderColor = selected
        ? Colors.transparent
        : (isToday ? brandPrimary : brandDark.withOpacity(0.12));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 64,
        height: 58,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
            width: isToday && !selected ? 2.0 : 1.2,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    weekday.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                      color: fg.withOpacity(selected ? 0.92 : 0.65),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dayNumber,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
            if (isToday)
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withOpacity(0.14)
                          : brandPrimary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'TODAY',
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: selected ? Colors.white : brandPrimary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _NoteResultKind { cancel, save }

class _NoteResult {
  final _NoteResultKind kind;
  final String? text;
  const _NoteResult._(this.kind, this.text);
  const _NoteResult.cancel() : this._(_NoteResultKind.cancel, null);
  _NoteResult.save(String text) : this._(_NoteResultKind.save, text);
}
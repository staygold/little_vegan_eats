// lib/meal_plan/meal_plan_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/allergy_engine.dart';
import '../recipes/recipe_repository.dart';

import 'core/allergy_profile.dart';
import 'core/meal_plan_controller.dart';
import 'core/meal_plan_keys.dart';
import 'core/meal_plan_repository.dart';

import 'widgets/meal_plan_entry_parser.dart';
import 'widgets/meal_plan_shopping_sheet.dart';
import 'widgets/today_meal_plan_section.dart';

import 'choose_recipe_page.dart';
import 'reuse_recipe_page.dart';
import 'builder/meal_plan_builder_screen.dart';

enum MealPlanViewMode { today, week }

class MealPlanScreen extends StatefulWidget {
  final String? weekId;
  final String? focusDayKey;
  final MealPlanViewMode? initialViewMode;

  const MealPlanScreen({
    super.key,
    this.weekId,
    this.focusDayKey,
    this.initialViewMode,
  });

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> with SingleTickerProviderStateMixin {
  late MealPlanViewMode _mode;
  bool _reviewMode = false;
  String? _focusDayOverride;

  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = true;

  late final MealPlanController _ctrl;
  
  // ✅ ADDED: Controller to track swiping
  late TabController _tabController;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};

  final Map<String, List<int>> _recentBySlot = <String, List<int>>{};
  static const int _recentWindow = 12;

  final Set<String> _snack2HiddenDays = <String>{};

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sourcePlanSub;
  String? _sourcePlanIdListening;
  String? _sourcePlanTitle;

  Color get _brandDark => const Color(0xFF044246);
  Color get _brandPrimary => const Color(0xFF32998D);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _isFirstDayOfWeekView(String dayKey) {
    final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
    if (dayKeys.isEmpty) return false;
    return dayKeys.first == dayKey;
  }

  String _monthShort(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final idx = (m - 1).clamp(0, 11);
    return months[idx];
  }

  String _weekRangeLabel(String weekId) {
    final dayKeys = MealPlanKeys.weekDayKeys(weekId);
    if (dayKeys.isEmpty) return 'Meal plan';

    final start = MealPlanKeys.parseDayKey(dayKeys.first);
    final end = MealPlanKeys.parseDayKey(dayKeys.last);
    if (start == null || end == null) return 'Meal plan';

    if (start.month == end.month) {
      return '${start.day}–${end.day} ${_monthShort(start.month)}';
    }
    return '${start.day} ${_monthShort(start.month)}–${end.day} ${_monthShort(end.month)}';
  }

  Future<void> _shiftWeekBy(int deltaWeeks) async {
    final base = MealPlanKeys.parseDayKey(_ctrl.weekId) ?? DateTime.now();
    final next = base.add(Duration(days: 7 * deltaWeeks));
    final nextWeekId = MealPlanKeys.dayKey(next);

    setState(() {
      _focusDayOverride = null;
      _mode = MealPlanViewMode.week;
    });

    await _ctrl.setWeek(nextWeekId);
    _sourcePlanSub?.cancel();
    _sourcePlanSub = null;
    _sourcePlanIdListening = null;
    _sourcePlanTitle = null;

    // Reset tab controller to start of week (or today if applicable)
    _tabController.animateTo(0);

    if (!mounted) return;
    setState(() {});
  }

  // -------------------------------------------------------
  // SAVE AND ACTIVATE AS WEEK PLAN
  // -------------------------------------------------------
  Future<void> _saveAsWeekPlanSnapshot() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Name this Plan"),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "e.g. Family Favourites",
            labelText: "Plan Name",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandPrimary,
            ),
            child: const Text("Save & Activate"),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
    final Map<String, dynamic> days = {};
    for (var i = 0; i < dayKeys.length; i++) {
      final dk = dayKeys[i];
      final snap = _snapshotDay(dk);
      days['$i'] = snap.isEmpty ? null : snap;
    }

    final snacksPerDay = _snacksPerDayFromWeek();
    final title = name;

    final payload = <String, dynamic>{
      'title': title,
      'type': 'week',
      'savedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'days': days,
      'config': <String, dynamic>{
        'daysToPlan': 7,
        'snacksPerDay': snacksPerDay,
        'createdFrom': 'dayPlans',
        'createdFromWeekId': _ctrl.weekId,
      },
    };

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('savedMealPlans')
          .add(payload);

      final weekRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mealPlansWeeks')
          .doc(_ctrl.weekId);

      final updates = <String, dynamic>{
         'config.title': title,
         'config.sourceWeekPlanId': docRef.id,
         'config.horizon': 'week', 
         'config.mode': 'week',
         'config.daysToPlan': 7,
         'config.daySources': FieldValue.delete(), 
         'config.dayPlanTitles': FieldValue.delete(),
         'config.dayPlanSourceIds': FieldValue.delete(),
         'updatedAt': FieldValue.serverTimestamp(),
      };

      await weekRef.update(updates);

      if (!mounted) return;
      _snack('Saved "$title" and set as active');
      setState(() {});

    } catch (e) {
      if (!mounted) return;
      _snack('Error saving plan: $e');
    }
  }

  String? _getWeekSourcePlanId() {
    final cfg = _ctrl.weekData?['config'];
    if (cfg is! Map) return null;
    var v = (cfg['sourceWeekPlanId'] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
    v = (cfg['sourcePlanId'] ?? '').toString().trim();
    return v.isNotEmpty ? v : null;
  }

  String? _dayPlanTitleForDay(String dayKey) {
    if (_getWeekSourcePlanId() != null) return null;

    final rawDays = _ctrl.weekData?['days'];
    if (rawDays is Map) {
      final dayMap = rawDays[dayKey];
      if (dayMap is Map) {
        final t = (dayMap['title'] ?? '').toString().trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }

  String? _sourcePlanIdForDay(String dayKey) {
    final cfg = _ctrl.weekData?['config'];
    if (cfg is Map) {
      final ids = cfg['dayPlanSourceIds'];
      if (ids is Map) {
        final v = (ids[dayKey] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      final v2 = _getWeekSourcePlanId();
      if (v2 != null) return v2;
    }
    return null;
  }

  void _ensureSourcePlanTitleListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final planId = _getWeekSourcePlanId();
    if (planId == null || planId.trim().isEmpty) {
      _sourcePlanSub?.cancel();
      _sourcePlanSub = null;
      _sourcePlanIdListening = null;
      _sourcePlanTitle = null;
      return;
    }

    if (_sourcePlanIdListening == planId) return;

    _sourcePlanSub?.cancel();
    _sourcePlanIdListening = planId;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedMealPlans')
        .doc(planId);

    _sourcePlanSub = ref.snapshots().listen((snap) {
      final data = snap.data();
      final t = (data?['title'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _sourcePlanTitle = t.isNotEmpty ? t : null;
      });
    });
  }

  String _activePlanTitleForCards() {
    final data = _ctrl.weekData;
    if (data == null) return 'Meal plan';

    final cfg = data['config'];
    if (cfg is Map) {
      final v = (cfg['title'] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }

    final fromSaved = (_sourcePlanTitle ?? '').trim();
    if (fromSaved.isNotEmpty) return fromSaved;

    final t = (data['title'] ?? '').toString().trim();
    if (t.isNotEmpty) return t;

    return 'Meal plan';
  }

  int _snacksPerDayFromWeek() {
    final cfg = _ctrl.weekData?['config'];
    if (cfg is! Map) return 1;
    final v = cfg['snacksPerDay'];
    final n = (v is int) ? v : int.tryParse(v?.toString() ?? '');
    return (n ?? 1).clamp(0, 2);
  }

  bool _isSnack2HiddenForDay(String dayKey) => _snack2HiddenDays.contains(dayKey);

  List<String> _slotsForDaySnapshot(String dayKey) {
    final snacksPerDay = _snacksPerDayFromWeek();
    final out = <String>['breakfast', 'lunch', 'dinner', 'snack1'];

    if (_isSnack2HiddenForDay(dayKey)) return out;

    final snack2Exists = _ctrl.effectiveEntryForUI(dayKey, 'snack2') != null;
    if (snacksPerDay >= 2 || snack2Exists) out.add('snack2');

    return out;
  }

  Map<String, dynamic>? _snapshotSlotEntry(String dayKey, String slot) {
    if (slot == 'snack2' && _isSnack2HiddenForDay(dayKey)) return null;

    final raw = _ctrl.effectiveEntryForUI(dayKey, slot);
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
    for (final slot in _slotsForDaySnapshot(dayKey)) {
      final snap = _snapshotSlotEntry(dayKey, slot);
      if (snap != null) out[slot] = snap;
    }
    return out;
  }

  Future<void> _syncDaySnapshotToSavedPlan({
    required String sourcePlanId,
    required String dayKey,
    required Map<String, dynamic> daySnapshot,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final savedRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('savedMealPlans')
          .doc(sourcePlanId);

      final docSnap = await savedRef.get();
      if (!docSnap.exists) return;

      final data = docSnap.data()!;

      bool isDayPlan = false;
      if (data['day'] is Map) {
        isDayPlan = true;
      } else if (data['days'] is Map) {
        final map = data['days'] as Map;
        if (map.length == 1) isDayPlan = true;
      }

      if (isDayPlan) {
        await savedRef.set({
          'day': daySnapshot,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await savedRef.set({
          'days': {dayKey: daySnapshot},
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  void _openShoppingSheet() {
    final bool forcedToday = widget.initialViewMode == MealPlanViewMode.today;
    final MealPlanViewMode effectiveMode = forcedToday ? MealPlanViewMode.today : _mode;

    Map<String, dynamic> planData;

    if (effectiveMode == MealPlanViewMode.today) {
      final dayKey = MealPlanKeys.todayKey();
      planData = {'type': 'day', 'day': _snapshotDay(dayKey)};
    } else {
      final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
      final days = <String, dynamic>{};
      for (final dk in dayKeys) {
        days[dk] = _snapshotDay(dk);
      }
      planData = {'type': 'week', 'days': days};
    }

    final knownTitles = <int, String>{};
    for (final r in _recipes) {
      final id = _recipeIdFrom(r);
      final title = _titleOf(r);
      if (id != null) knownTitles[id] = title;
    }

    MealPlanShoppingSheet.show(context, planData, knownTitles);
  }

  @override
  void initState() {
    super.initState();

    final hasFocus = (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty);
    _mode = widget.initialViewMode ?? (hasFocus ? MealPlanViewMode.today : MealPlanViewMode.week);

    final resolvedWeekId = (widget.weekId != null && widget.weekId!.trim().isNotEmpty)
        ? widget.weekId!.trim()
        : MealPlanKeys.currentWeekId();

    _ctrl = MealPlanController(
      auth: FirebaseAuth.instance,
      repo: MealPlanRepository(FirebaseFirestore.instance),
      initialWeekId: resolvedWeekId,
    );

    _ctrl.start();
    _ctrl.ensureWeek();

    // ✅ INIT TAB CONTROLLER
    // We init with 7 days for the week view
    _tabController = TabController(length: 7, vsync: this);
    
    // Set initial index based on focus day
    final weekKeys = MealPlanKeys.weekDayKeys(resolvedWeekId);
    final focusKey = widget.focusDayKey ?? MealPlanKeys.todayKey();
    final initialIndex = weekKeys.indexOf(focusKey);
    if (initialIndex != -1) {
      _tabController.index = initialIndex;
    }

    // Listener to update title on swipe
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // Force rebuild to update the header title
        setState(() {});
      }
    });

    () async {
      await _loadAllergies();
      await _loadRecipes();
      _startUserDocAllergyListener();
      _startFavoritesListener();
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
    _sourcePlanSub?.cancel();
    _ctrl.stop();
    _ctrl.dispose();
    _tabController.dispose();
    super.dispose();
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
      _ctrl.setAllergySets(
        excludedAllergens: sets.excludedAllergens,
        childAllergens: sets.childAllergens,
      );
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

  Future<void> _loadAllergies() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final sets = AllergyProfile.buildFromUserDoc(snap.data());
      _ctrl.setAllergySets(
        excludedAllergens: sets.excludedAllergens,
        childAllergens: sets.childAllergens,
      );
    } catch (_) {
      _ctrl.setAllergySets(excludedAllergens: {}, childAllergens: {});
    }
  }

  Future<void> _loadRecipes() async {
    try {
      _recipes = await RecipeRepository.ensureRecipesLoaded();
    } catch (_) {
      _recipes = [];
    } finally {
      if (mounted) setState(() => _recipesLoading = false);
    }
  }

  String _swapTextOf(Map<String, dynamic> r) {
    if (r['ingredient_swaps'] != null) return r['ingredient_swaps'].toString();
    if (r['meta'] is Map && r['meta']['ingredient_swaps'] != null) {
      return r['meta']['ingredient_swaps'].toString();
    }
    return '';
  }

  String _statusTextOf(Map<String, dynamic> recipe) {
    if (_ctrl.excludedAllergens.isEmpty && _ctrl.childAllergens.isEmpty) return 'safe';

    final allAllergies = <String>{
      ..._ctrl.excludedAllergens,
      ..._ctrl.childAllergens,
    }.toList();

    final res = AllergyEngine.evaluate(
      recipeAllergyTags: const [],
      swapFieldText: _swapTextOf(recipe),
      userAllergies: allAllergies,
    );

    if (res.status == AllergyStatus.safe) return 'safe';
    if (res.status == AllergyStatus.swapRequired) return 'swap';
    return 'blocked';
  }

  int? _recipeIdFrom(Map<String, dynamic> r) => MealPlanEntryParser.recipeIdFromAny(r['id']);

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

  // --------------------------
  // DATE + CALENDAR HELPERS
  // --------------------------

  String formatDayKeyPretty(String dayKey) => MealPlanKeys.formatPretty(dayKey);
  String _weekdayLetter(DateTime dt) => MealPlanKeys.weekdayLetter(dt);

  Map<String, dynamic> _dayRawForUI(String dayKey) {
    const slots = <String>['breakfast', 'lunch', 'dinner', 'snack1', 'snack2'];
    final out = <String, dynamic>{};

    for (final slot in slots) {
      if (slot == 'snack2' && _isSnack2HiddenForDay(dayKey)) continue;
      final resolved = _ctrl.effectiveEntryForUI(dayKey, slot);
      if (resolved != null) out[slot] = resolved;
    }
    return out;
  }

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

  // --------------------------
  // GLOBAL SAVE BAR (PERSISTENT)
  // --------------------------

  int _uniqueDirtyRecipeCount() {
    final recipeIds = <int>{};
    final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);

    for (final dk in dayKeys) {
      final slots = _ctrl.dirtySlotsForDay(dk);
      for (final slot in slots) {
        final raw = _ctrl.effectiveEntryForUI(dk, slot);
        final parsed = MealPlanEntryParser.parse(raw);
        final rid = MealPlanEntryParser.entryRecipeId(parsed);
        if (rid != null) recipeIds.add(rid);
      }
    }
    return recipeIds.length;
  }

  String _saveBarLabel() {
    final recipeCount = _uniqueDirtyRecipeCount();
    final slotCount = _ctrl.dirtySlotCount();

    if (recipeCount > 0) {
      if (recipeCount == 1) return 'SAVE CHANGES TO 1 RECIPE';
      return 'SAVE CHANGES TO $recipeCount RECIPES';
    }

    if (slotCount <= 1) return 'SAVE CHANGES';
    return 'SAVE $slotCount CHANGES';
  }

  Future<void> _saveAllChanges() async {
    final dirtyDays = _ctrl.dirtyDayKeys().toList();
    if (dirtyDays.isEmpty) return;

    // Snapshot before save clears drafts.
    final snapshots = <String, Map<String, dynamic>>{};
    for (final dk in dirtyDays) {
      snapshots[dk] = _snapshotDay(dk);
    }

    for (final dk in dirtyDays) {
      await _ctrl.saveDay(dk);

      final snap = snapshots[dk];
      if (snap == null) continue;

      final sourceId = _sourcePlanIdForDay(dk);
      if (sourceId == null || sourceId.trim().isEmpty) continue;

      await _syncDaySnapshotToSavedPlan(
        sourcePlanId: sourceId.trim(),
        dayKey: dk,
        daySnapshot: snap,
      );
    }

    if (!mounted) return;
    if (dirtyDays.length == 1) {
      _snack('Saved ${formatDayKeyPretty(dirtyDays.first)}');
    } else {
      _snack('Saved ${dirtyDays.length} days');
    }
  }

  Widget _persistentSaveBar() {
    final dirtySlots = _ctrl.dirtySlotCount();
    if (dirtySlots <= 0) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: _brandDark,
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, -6),
                blurRadius: 18,
                color: Color.fromRGBO(0, 0, 0, 0.10),
              )
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveAllChanges,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                shape: const StadiumBorder(),
              ),
              child: Text(_saveBarLabel()),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------
  // NAV: View Today should go to today
  // --------------------------
  void _goToTodayView() {
    setState(() {
      _focusDayOverride = MealPlanKeys.todayKey();
      _mode = MealPlanViewMode.today;
    });
  }

  // --------------------------
  // USER ACTIONS
  // --------------------------

  Future<void> _reuseFromAnotherDay({
    required String dayKey,
    required String slot,
  }) async {
    final headerLabel = '${_prettySlotLabel(slot)} • ${formatDayKeyPretty(dayKey)}';

    final weekDayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
    final currentIndex = weekDayKeys.indexOf(dayKey);

    final candidates = <ReuseCandidate>[];

    for (var i = 0; i < weekDayKeys.length; i++) {
      final dk = weekDayKeys[i];
      if (currentIndex >= 0 && i >= currentIndex) break;

      final resolved = _ctrl.effectiveEntryForUI(dk, slot);
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
          formatDayPretty: formatDayKeyPretty,
        ),
      ),
    );

    if (picked == null) return;

    _ctrl.setDraftReuseFrom(
      targetDayKey: dayKey,
      targetSlot: slot,
      fromDayKey: picked.fromDayKey,
      fromSlot: picked.fromSlot,
    );
  }

  Future<void> _chooseRecipe({
    required String dayKey,
    required String slot,
  }) async {
    final currentParsed = MealPlanEntryParser.parse(_ctrl.effectiveEntryForUI(dayKey, slot));
    final currentId = MealPlanEntryParser.entryRecipeId(currentParsed);

    final candidates = _ctrl.getCandidatesForSlot(slot, _recipes);

    final recentKey = '$dayKey|$slot';
    final initialRecent = List<int>.from(_recentBySlot[recentKey] ?? const <int>[]);

    final headerLabel = '${_prettySlotLabel(slot)} • ${formatDayKeyPretty(dayKey)}';

    final res = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ChooseRecipePage(
          recipes: _recipes,
          titleOf: _titleOf,
          thumbOf: _thumbOf,
          idOf: _recipeIdFrom,
          statusTextOf: _statusTextOf,
          headerLabel: headerLabel,
          currentId: currentId,
          availableIds: candidates,
          recentKey: recentKey,
          initialRecent: initialRecent,
          recentWindow: _recentWindow,
        ),
      ),
    );

    if (res == null) return;

    final key = (res['recentKey'] ?? recentKey).toString();
    final recent = (res['recent'] is List)
        ? (res['recent'] as List)
            .map((e) => int.tryParse(e.toString()) ?? -1)
            .where((v) => v > 0)
            .toList()
        : initialRecent;
    _recentBySlot[key] = recent;

    final picked = res['pickedId'];
    final pickedId = (picked is int) ? picked : int.tryParse(picked?.toString() ?? '');

    if (pickedId != null) {
      if (slot == 'snack2') _snack2HiddenDays.remove(dayKey);
      _ctrl.setDraftRecipe(dayKey, slot, pickedId, source: 'manual');
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
            onPressed: () => Navigator.of(context).pop(const _NoteResult.cancel()),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_NoteResult.save(textCtrl.text)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (result == null || result.kind == _NoteResultKind.cancel) return;
    final text = (result.text ?? '').trim();
    if (text.isEmpty) return;
    _ctrl.setDraftNote(dayKey, slot, text);
  }

  Future<void> _clearSlot({
    required String dayKey,
    required String slot,
  }) async {
    if (slot == 'snack2') {
      _snack2HiddenDays.add(dayKey);
      _ctrl.setDraftClear(dayKey, 'snack2');
      return;
    }

    final current = _ctrl.effectiveEntryForUI(dayKey, slot);
    final parsedCurrent = MealPlanEntryParser.parse(current);
    final reuseMeta = MealPlanEntryParser.entryReuseFrom(parsedCurrent);
    if (reuseMeta != null) {
      final fromDay = (reuseMeta['dayKey'] ?? '').toString();
      final fromSlot = (reuseMeta['slot'] ?? '').toString();

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Remove reused item?'),
          content: Text(
            'This meal is reused from ${formatDayKeyPretty(fromDay)} (${_prettySlotLabel(fromSlot)}).\n\nRemove it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      _ctrl.setDraftClear(dayKey, slot);
      return;
    }

    final deps = _ctrl.reuseDependents(fromDayKey: dayKey, fromSlot: slot);
    if (deps.isNotEmpty) {
      final preview = deps.take(4).map((d) {
        final dk = d['dayKey'] ?? '';
        final sl = d['slot'] ?? '';
        return '${formatDayKeyPretty(dk)} • ${_prettySlotLabel(sl)}';
      }).join('\n');
      final more = deps.length > 4 ? '\n…and ${deps.length - 4} more.' : '';

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('This meal is reused'),
          content: Text('Removing this will also remove the reused copies:\n\n$preview$more'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove all'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      _ctrl.clearSlotCascade(fromDayKey: dayKey, fromSlot: slot);
      return;
    }

    _ctrl.setDraftClear(dayKey, slot);
  }

  Future<bool> _handleBack() async {
    if (_reviewMode) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return false;
    }
    return true;
  }

  bool _isDayPlanFromWeekData() {
    final cfg = _ctrl.weekData?['config'];
    if (cfg is! Map) return false;
    final v = cfg['daysToPlan'];
    final n = (v is int) ? v : int.tryParse(v?.toString() ?? '');
    return (n ?? 0) == 1;
  }

  void _maybePreferWeekIfDayPlanLoaded() {
    if (!mounted) return;
    if (widget.initialViewMode != null) return;
    if (_mode != MealPlanViewMode.today) return;
    if (!_isDayPlanFromWeekData()) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialViewMode != null) return;
      if (_mode == MealPlanViewMode.today && _isDayPlanFromWeekData()) {
        setState(() => _mode = MealPlanViewMode.week);
      }
    });
  }

  // ✅ UPDATED: Removes all header text, just shows the CTA card
  Widget _emptyDayCta(String dayKey, {String? planTitle}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        // ✅ NEW: IF a planTitle IS passed (only when it's NOT week mode), show it
        // BUT: if we are in day mode, we should NOT show title if it's empty
        // The header logic will handle the title.
        
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
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MealPlanBuilderScreen(
                          startAsDayPlan: true,
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
                    'BUILD A DAY PLAN',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ✅ DYNAMIC HEADER TITLE LOGIC
  String _getCurrentHeaderTitle() {
    if (_ctrl.weekData == null) return '';

    bool isGlobal = _getWeekSourcePlanId() != null;
    if (isGlobal) {
       // If Week Plan -> Always show the global name
       return _activePlanTitleForCards(); 
    }

    // If Day Plan -> Show the specific day name if it exists, otherwise empty
    int index = _tabController.index;
    final days = MealPlanKeys.weekDayKeys(_ctrl.weekId);
    if (index >= 0 && index < days.length) {
      String dayKey = days[index];
      return _dayPlanTitleForDay(dayKey) ?? '';
    }
    
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Log in to view your meal plan')));
    }
    if (_recipesLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final todayKey = MealPlanKeys.todayKey();

    final focusDayKey = (_focusDayOverride?.trim().isNotEmpty == true)
        ? _focusDayOverride!.trim()
        : (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty)
            ? widget.focusDayKey!.trim()
            : todayKey;

    final bool forcedToday = widget.initialViewMode == MealPlanViewMode.today;
    final bool forcedWeek = widget.initialViewMode == MealPlanViewMode.week;

    final MealPlanViewMode effectiveMode = forcedToday ? MealPlanViewMode.today : _mode;

    return WillPopScope(
      onWillPop: _handleBack,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final data = _ctrl.weekData;

          _maybePreferWeekIfDayPlanLoaded();
          if (data != null) _ensureSourcePlanTitleListener();

          final hasGlobalDirty = _ctrl.dirtySlotCount() > 0;

          final bool isThisWeek = _ctrl.weekId == MealPlanKeys.currentWeekId();
          
          final bool isAlreadyWeekPlan = _getWeekSourcePlanId() != null;

          final bool showSaveAsWeekInAppBar =
              !_reviewMode && 
              isThisWeek && 
              (effectiveMode == MealPlanViewMode.week) &&
              !isAlreadyWeekPlan;

          // Helper for rendering each day's content
          Widget buildColourfulDay(
            String dayKey, {
            required String heroTop,
            required String heroBottom,
            required bool isWeekMode,
          }) {
            final dayRaw = _dayRawForUI(dayKey);
            final allowReuse = isWeekMode && !_isFirstDayOfWeekView(dayKey);

            final isEmpty = dayRaw.isEmpty;
            if (isWeekMode && isEmpty) {
              // ✅ PASS NULL for title so it doesn't double up inside the scroll view
              return _emptyDayCta(dayKey, planTitle: null);
            }

            return ListView(
              padding: EdgeInsets.only(bottom: hasGlobalDirty ? 86 : 0),
              children: [
                TodayMealPlanSection(
                  todayRaw: dayRaw,
                  recipes: _recipes,
                  favoriteIds: _favoriteIds,
                  
                  // ✅ Cleared headers for week view, as day/date is in calendar
                  heroTopText: isWeekMode ? '' : heroTop,
                  heroBottomText: isWeekMode ? '' : heroBottom,
                  
                  // ✅ Pass empty string so title is NOT shown inside the scroll view
                  // (It is now handled by the persistent header above)
                  planTitle: isWeekMode ? '' : '', 

                  onBuildMealPlan: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MealPlanBuilderScreen(
                          startAsDayPlan: true,
                          initialSelectedDayKey: dayKey,
                        ),
                      ),
                    );
                  },
                  homeAccordion: true,
                  homeAlwaysExpanded: true,
                  onChooseSlot: (slot) => _chooseRecipe(dayKey: dayKey, slot: slot),
                  onReuseSlot: allowReuse ? (slot) => _reuseFromAnotherDay(dayKey: dayKey, slot: slot) : null,
                  onNoteSlot: (slot) async {
                    final initial = MealPlanEntryParser.entryNoteText(
                      MealPlanEntryParser.parse(_ctrl.effectiveEntryForUI(dayKey, slot)),
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

          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: Icon(_reviewMode ? Icons.close : Icons.arrow_back),
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
        if (showSaveAsWeekInAppBar)
          TextButton(
            onPressed: _saveAsWeekPlanSnapshot,
            style: TextButton.styleFrom(
              foregroundColor: _brandDark,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
            child: const Text('SAVE AS WEEK'),
          ),

        IconButton(
          tooltip: 'Shopping List',
          icon: const Icon(Icons.shopping_cart_outlined),
          onPressed: _openShoppingSheet,
        ),
      ],
            ),
            body: (data == null)
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      () {
                        if (effectiveMode == MealPlanViewMode.today) {
                          return buildColourfulDay(
                            todayKey,
                            heroTop: "TODAY’S",
                            heroBottom: "MEAL PLAN",
                            isWeekMode: false,
                          );
                        }

                        final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);

                        final focusIndex = dayKeys.indexOf(focusDayKey);
                        final initialIndex =
                            (focusIndex >= 0 ? focusIndex : 0).clamp(0, dayKeys.length - 1);

                        final weekLabel = _weekRangeLabel(_ctrl.weekId);

                        // ✅ FIX: WRAP THE COLUMN (INCLUDING PILL STRIP) IN DEFAULTTABCONTROLLER
                        // But we use OUR _tabController here.
                        return Column(
                            children: [
                              if (!_reviewMode)
                                _WeekHeaderRow(
                                  weekLabel: weekLabel,
                                  brandDark: _brandDark,
                                  onPrev: () => _shiftWeekBy(-1),
                                  onNext: () => _shiftWeekBy(1),
                                ),

                              // We use our explicit controller here for the strip
                              _WeekPillStripWithController(
                                controller: _tabController,
                                dayKeys: dayKeys,
                                weekdayLetter: _weekdayLetter,
                                brandDark: _brandDark,
                                brandPrimary: _brandPrimary,
                              ),
                              
                              // ✅ PERSISTENT TITLE AREA
                              // Calculated dynamically based on the tab index
                              if (effectiveMode == MealPlanViewMode.week)
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
                                  // Disable swipe if using individual day plans (per request)
                                  physics: !isAlreadyWeekPlan
                                      ? const NeverScrollableScrollPhysics()
                                      : null,
                                  children: [
                                    for (final dayKey in dayKeys)
                                      buildColourfulDay(
                                        dayKey,
                                        heroTop: '',
                                        heroBottom: '',
                                        isWeekMode: true,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                      }(),
                      _persistentSaveBar(),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------
// ✅ Week header row (range + chevrons only)
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
            icon: const Icon(Icons.chevron_left),
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
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------
// ✅ Pill calendar strip using explicit TabController
// -------------------------------------------------------

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
              physics: const BouncingScrollPhysics(),
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
          }
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

    final borderColor =
        selected ? Colors.transparent : (isToday ? brandPrimary : brandDark.withOpacity(0.12));

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
                    maxLines: 1,
                    overflow: TextOverflow.clip,
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
                      color: selected ? Colors.white.withOpacity(0.14) : brandPrimary.withOpacity(0.14),
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
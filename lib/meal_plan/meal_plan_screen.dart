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

  /// ✅ explicit initial view mode (Home can force today/week).
  /// If null, screen will infer mode from focusDayKey (existing behaviour).
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

class _MealPlanScreenState extends State<MealPlanScreen> {
  late MealPlanViewMode _mode;
  bool _reviewMode = false;

  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = true;

  late final MealPlanController _ctrl;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};

  final Map<String, List<int>> _recentBySlot = <String, List<int>>{};
  static const int _recentWindow = 12;

  // UI-only override
  final Set<String> _snack2HiddenDays = <String>{};

  // Saved plan title (users/{uid}/savedMealPlans/{sourcePlanId}.title)
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sourcePlanSub;
  String? _sourcePlanIdListening;
  String? _sourcePlanTitle;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _isFirstDayOfWeekView(String dayKey) {
    final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
    if (dayKeys.isEmpty) return false;
    return dayKeys.first == dayKey;
  }

  String? _getSourcePlanId() {
    final cfg = _ctrl.weekData?['config'];
    if (cfg is! Map) return null;
    return cfg['sourcePlanId']?.toString();
  }

  void _ensureSourcePlanTitleListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final planId = _getSourcePlanId();
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

  String _activePlanTitle() {
    final fromSaved = (_sourcePlanTitle ?? '').trim();
    if (fromSaved.isNotEmpty) return fromSaved;

    final data = _ctrl.weekData;
    if (data == null) return 'Meal plan';

    final cfg = data['config'];
    if (cfg is Map) {
      final v = (cfg['title'] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }

    final t = (data['title'] ?? '').toString().trim();
    if (t.isNotEmpty) return t;

    return 'Meal plan';
  }

  int _snacksPerDayFromWeek() {
    final v = _ctrl.weekData?['config']?['snacksPerDay'];
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
      if (raw is Map) {
        final m = raw as Map;
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

  Future<void> _syncChangeToSavedPlan(String dayKey) async {
    final sourceId = _getSourcePlanId();
    if (sourceId == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final savedRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('savedMealPlans')
          .doc(sourceId);

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

      final daySnapshot = _snapshotDay(dayKey);

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
    final MealPlanViewMode effectiveMode =
        forcedToday ? MealPlanViewMode.today : _mode;

    Map<String, dynamic> planData;

    if (effectiveMode == MealPlanViewMode.today) {
      final dayKey = (widget.focusDayKey?.isNotEmpty == true)
          ? widget.focusDayKey!
          : MealPlanKeys.todayKey();

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

  // ✅ FULL DELETE:
  // - If this week is sourced from a saved plan -> delete savedMealPlans/{sourcePlanId}
  // - Clear week schedule (days) + config/title
  // - Clear user activeSavedMealPlanId
  // - Pop to root (Home)
  Future<void> _deleteThisMealPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final sourcePlanId = _getSourcePlanId();
    final hasSource = (sourcePlanId ?? '').trim().isNotEmpty;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this meal plan?'),
        content: Text(
          hasSource
              ? 'This will delete the saved plan and remove it from your current schedule.'
              : 'This will clear your current meal plan from your schedule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final uid = user.uid;
    final fs = FirebaseFirestore.instance;

    try {
      final batch = fs.batch();

      final weekRef = fs
          .collection('users')
          .doc(uid)
          .collection('mealPlansWeeks')
          .doc(_ctrl.weekId);

      final userRef = fs.collection('users').doc(uid);

      // 1) Delete saved plan doc if this week is sourced from one
      if (hasSource) {
        final savedRef = fs
            .collection('users')
            .doc(uid)
            .collection('savedMealPlans')
            .doc(sourcePlanId!.trim());
        batch.delete(savedRef);
      }

      // 2) Clear schedule + detach config
      batch.set(
        weekRef,
        {
          'days': <String, dynamic>{},
          'title': FieldValue.delete(),
          'config': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 3) Clear user active pointer (safe even if field doesn't exist)
      batch.set(
        userRef,
        {'activeSavedMealPlanId': FieldValue.delete()},
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;

      // Reset local title listener so UI doesn't show old title briefly
      _sourcePlanSub?.cancel();
      _sourcePlanSub = null;
      _sourcePlanIdListening = null;
      _sourcePlanTitle = null;

      // ✅ Go back to Home (root)
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      _snack('Delete failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    final hasFocus =
        (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty);

    _mode = widget.initialViewMode ??
        (hasFocus ? MealPlanViewMode.today : MealPlanViewMode.week);

    final resolvedWeekId =
        (widget.weekId != null && widget.weekId!.trim().isNotEmpty)
            ? widget.weekId!.trim()
            : MealPlanKeys.currentWeekId();

    _ctrl = MealPlanController(
      auth: FirebaseAuth.instance,
      repo: MealPlanRepository(FirebaseFirestore.instance),
      initialWeekId: resolvedWeekId,
    );

    _ctrl.start();
    _ctrl.ensureWeek();

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
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
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
    if (_ctrl.excludedAllergens.isEmpty && _ctrl.childAllergens.isEmpty) {
      return 'safe';
    }
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
    final currentParsed =
        MealPlanEntryParser.parse(_ctrl.effectiveEntryForUI(dayKey, slot));
    final currentId = MealPlanEntryParser.entryRecipeId(currentParsed);

    final candidates = _ctrl.getCandidatesForSlot(slot, _recipes);

    final recentKey = '$dayKey|$slot';
    final initialRecent =
        List<int>.from(_recentBySlot[recentKey] ?? const <int>[]);

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
    final pickedId =
        (picked is int) ? picked : int.tryParse(picked?.toString() ?? '');

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
          content: Text(
            'Removing this will also remove the reused copies:\n\n$preview$more',
          ),
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

  void _maybeForceTodayIfDayPlanLoaded() {
    if (widget.initialViewMode != null) return;
    if (!mounted) return;
    if (_mode != MealPlanViewMode.week) return;
    if (!_isDayPlanFromWeekData()) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialViewMode != null) return;
      if (_mode == MealPlanViewMode.week && _isDayPlanFromWeekData()) {
        setState(() => _mode = MealPlanViewMode.today);
      }
    });
  }

  Widget _appBarTitle({
    required String planTitle,
    required String contextLine,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(planTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          contextLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.85),
          ),
        ),
      ],
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

    final focusDayKey =
        (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty)
            ? widget.focusDayKey!.trim()
            : MealPlanKeys.todayKey();

    final now = DateTime.now();

    final bool forcedToday = widget.initialViewMode == MealPlanViewMode.today;
    final bool forcedWeek = widget.initialViewMode == MealPlanViewMode.week;

    final MealPlanViewMode effectiveMode =
        forcedToday ? MealPlanViewMode.today : _mode;

    return WillPopScope(
      onWillPop: _handleBack,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final data = _ctrl.weekData;

          _maybeForceTodayIfDayPlanLoaded();

          if (data != null) {
            _ensureSourcePlanTitleListener();
          }

          final planTitle = _activePlanTitle();

          final appBarContextLine = _reviewMode
              ? 'Review'
              : (effectiveMode == MealPlanViewMode.today ? 'Today' : 'Next 7 days');

          Widget buildColourfulDay(
            String dayKey, {
            required String heroTop,
            required String heroBottom,
            required bool isWeekMode,
          }) {
            final dayRaw = _dayRawForUI(dayKey);
            final canSave = _ctrl.hasDraftChanges(dayKey);
            final allowReuse = isWeekMode && !_isFirstDayOfWeekView(dayKey);

            return Stack(
              children: [
                ListView(
                  padding: EdgeInsets.only(bottom: canSave ? 86 : 0),
                  children: [
                    TodayMealPlanSection(
                      todayRaw: dayRaw,
                      recipes: _recipes,
                      favoriteIds: _favoriteIds,
                      heroTopText: heroTop,
                      heroBottomText: heroBottom,
                      planTitle: planTitle,
                      onBuildMealPlan: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MealPlanBuilderScreen(),
                          ),
                        );
                      },
                      homeAccordion: true,
                      homeAlwaysExpanded: true,
                      onChooseSlot: (slot) =>
                          _chooseRecipe(dayKey: dayKey, slot: slot),
                      onReuseSlot: allowReuse
                          ? (slot) => _reuseFromAnotherDay(
                                dayKey: dayKey,
                                slot: slot,
                              )
                          : null,
                      onNoteSlot: (slot) async {
                        final initial = MealPlanEntryParser.entryNoteText(
                          MealPlanEntryParser.parse(
                            _ctrl.effectiveEntryForUI(dayKey, slot),
                          ),
                        );
                        await _addOrEditNote(
                          dayKey: dayKey,
                          slot: slot,
                          initial: initial,
                        );
                      },
                      onClearSlot: (slot) =>
                          _clearSlot(dayKey: dayKey, slot: slot),
                      onAddAnotherSnack: () =>
                          _chooseRecipe(dayKey: dayKey, slot: 'snack2'),
                      canSave: false,
                      onSaveChanges: null,
                    ),
                  ],
                ),
                if (canSave)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF044246),
                          boxShadow: [
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
                            onPressed: () async {
                              await _ctrl.saveDay(dayKey);
                              await _syncChangeToSavedPlan(dayKey);

                              if (!mounted) return;
                              _snack('Saved ${formatDayKeyPretty(dayKey)}');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF32998D),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text('SAVE CHANGES'),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }

          return Scaffold(
            appBar: AppBar(
              leading: _reviewMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _handleBack(),
                    )
                  : null,
              title: _appBarTitle(
                planTitle: planTitle,
                contextLine: appBarContextLine,
              ),
              actions: _reviewMode
                  ? []
                  : [
                      if (_ctrl.hasActivePlan) ...[
                        if (!forcedToday && !forcedWeek) ...[
                          if (effectiveMode == MealPlanViewMode.today)
                            IconButton(
                              tooltip: 'View week',
                              icon: const Icon(Icons.calendar_month),
                              onPressed: () =>
                                  setState(() => _mode = MealPlanViewMode.week),
                            )
                          else
                            IconButton(
                              tooltip: 'View today',
                              icon: const Icon(Icons.today),
                              onPressed: () =>
                                  setState(() => _mode = MealPlanViewMode.today),
                            ),
                        ],
                        IconButton(
                          tooltip: 'Shopping List',
                          icon: const Icon(Icons.shopping_cart_outlined),
                          onPressed: _openShoppingSheet,
                        ),
                        IconButton(
                          tooltip: 'Delete meal plan',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _deleteThisMealPlan,
                        ),
                      ],
                    ],
            ),
            body: (data == null)
                ? const Center(child: CircularProgressIndicator())
                : () {
                    if (effectiveMode == MealPlanViewMode.today) {
                      return buildColourfulDay(
                        focusDayKey,
                        heroTop: "TODAY’S",
                        heroBottom: "MEAL PLAN",
                        isWeekMode: false,
                      );
                    }

                    final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
                    final focusIndex = dayKeys.indexOf(focusDayKey);
                    final initialIndex = focusIndex >= 0 ? focusIndex : 0;

                    return DefaultTabController(
                      length: dayKeys.length,
                      initialIndex: initialIndex.clamp(0, dayKeys.length - 1),
                      child: Column(
                        children: [
                          Material(
                            color: Theme.of(context).colorScheme.surface,
                            child: TabBar(
                              isScrollable: false,
                              tabs: [
                                for (final k in dayKeys)
                                  Tab(
                                    text: _weekdayLetter(
                                      MealPlanKeys.parseDayKey(k) ?? now,
                                    ),
                                  )
                              ],
                            ),
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                for (final dayKey in dayKeys)
                                  buildColourfulDay(
                                    dayKey,
                                    heroTop:
                                        formatDayKeyPretty(dayKey).toUpperCase(),
                                    heroBottom: '',
                                    isWeekMode: true,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
          );
        },
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

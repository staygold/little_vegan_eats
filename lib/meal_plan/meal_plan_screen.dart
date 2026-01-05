// lib/meal_plan/meal_plan_screen.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_repository.dart';
import '../recipes/allergy_engine.dart';

import 'core/allergy_profile.dart';
import 'core/meal_plan_controller.dart';
import 'core/meal_plan_keys.dart';
import 'core/meal_plan_repository.dart';
import 'core/meal_plan_slots.dart';

import 'widgets/meal_plan_entry_parser.dart';
import 'widgets/today_meal_plan_section.dart';
import 'widgets/meal_plan_shopping_sheet.dart';

import 'choose_recipe_page.dart';
import 'reuse_recipe_page.dart';

enum MealPlanViewMode { today, week }

// ✅ Result for saving a favourite (prevents "Added" after limit error)
enum SavePlanResult { saved, limitReached, notLoggedIn, failed }

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

class _MealPlanScreenState extends State<MealPlanScreen> {
  late MealPlanViewMode _mode;
  bool _reviewMode = false;

  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = true;

  late final MealPlanController _ctrl;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};

  final Random _rng = Random();
  final Map<String, List<int>> _recentBySlot = <String, List<int>>{};
  static const int _recentWindow = 12;

  // ✅ CAP
  static const int _maxSavedMealPlans = 20;

  bool _isFirstDayOfWeekView(String dayKey) {
    final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
    if (dayKeys.isEmpty) return false;
    return dayKeys.first == dayKey;
  }

  // ✅ Same normalization logic as Controller
  String _normSlot(String slot) {
    final s = slot.trim().toLowerCase();
    if (s == 'snack_1' ||
        s == 'snacks_1' ||
        s == 'snack 1' ||
        s == 'snacks 1') return 'snack_1';
    if (s == 'snack_2' ||
        s == 'snacks_2' ||
        s == 'snack 2' ||
        s == 'snacks 2') return 'snack_2';
    return s;
  }

  // Kept for any other legacy usage
  int? _pickRandomDifferentId({
    required List<int> availableIds,
    required int? currentId,
    required String dayKey,
    required String slot,
  }) {
    if (availableIds.isEmpty) return null;

    final key = '$dayKey|$slot';
    final recent = _recentBySlot.putIfAbsent(key, () => <int>[]);

    final fresh =
        availableIds.where((id) => id != currentId && !recent.contains(id));
    final pool = (fresh.isNotEmpty)
        ? fresh.toList()
        : availableIds.where((id) => id != currentId).toList();

    if (pool.isEmpty) return null;

    final next = pool[_rng.nextInt(pool.length)];
    recent.add(next);
    if (recent.length > _recentWindow) recent.removeAt(0);
    return next;
  }

  DocumentReference<Map<String, dynamic>>? _userRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString().trim()) ?? 0;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showInfoModal({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLimitModal() async {
    return _showInfoModal(
      title: 'Limit reached',
      message:
          'You’ve reached your limit of $_maxSavedMealPlans saved meal plans.\n\n'
          'Delete one to save a new plan.',
    );
  }

  /// ✅ Cap-enforced create.
  /// - returns SavedPlanResult.limitReached (NO throw)
  /// - caller decides whether to show "Added" snackbar
  Future<SavePlanResult> _createSavedMealPlanWithCap({
    required Map<String, dynamic> docData,
  }) async {
    final userRef = _userRef();
    if (userRef == null) return SavePlanResult.notLoggedIn;

    final db = FirebaseFirestore.instance;
    final savedCol = userRef.collection('savedMealPlans');
    final newDoc = savedCol.doc();

    try {
      final res = await db.runTransaction((tx) async {
        final userSnap = await tx.get(userRef);
        final userData = userSnap.data() ?? <String, dynamic>{};
        final current = _asInt(userData['savedMealPlanCount']);

        if (current >= _maxSavedMealPlans) {
          return SavePlanResult.limitReached;
        }

        tx.set(newDoc, docData, SetOptions(merge: true));
        tx.set(
          userRef,
          {
            'savedMealPlanCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return SavePlanResult.saved;
      });

      return res;
    } catch (_) {
      return SavePlanResult.failed;
    }
  }

  Future<String?> _promptPlanName(BuildContext context,
      {required String title}) async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name your meal plan'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final name = (res ?? '').trim();
    if (name.isEmpty) return null;
    return name;
  }

  Map<String, dynamic>? _snapshotSlotEntry(String dayKey, String slot) {
    final raw = _ctrl.effectiveEntryForUI(dayKey, slot);
    final e = MealPlanEntryParser.parse(raw);
    if (e == null) return null;

    final rid = MealPlanEntryParser.entryRecipeId(e);
    if (rid != null) {
      String src = '';
      if (raw is Map) {
        final m = Map<String, dynamic>.from(raw as Map);
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
    for (final slot in MealPlanSlots.order) {
      final snap = _snapshotSlotEntry(dayKey, slot);
      if (snap != null) out[slot] = snap;
    }
    return out;
  }

  Future<void> _addDayPlanToFavourites(String dayKey) async {
    final name =
        await _promptPlanName(context, title: 'Add day plan to favourites');
    if (name == null) return;

    final payload = _snapshotDay(dayKey);

    final result = await _createSavedMealPlanWithCap(
      docData: {
        'title': name,
        'type': 'day',
        'savedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'day': payload,
        'meta': {'fromDayKey': dayKey, 'fromWeekId': _ctrl.weekId},
      },
    );

    if (!mounted) return;

    if (result == SavePlanResult.saved) {
      _snack('Added "$name" to favourites');
      return;
    }

    if (result == SavePlanResult.limitReached) {
      await _showLimitModal();
      return;
    }

    if (result == SavePlanResult.notLoggedIn) {
      await _showInfoModal(
        title: 'Not signed in',
        message: 'Please log in to save meal plans.',
      );
      return;
    }

    await _showInfoModal(
      title: 'Could not save',
      message: 'Something went wrong saving this plan. Try again.',
    );
  }

  Future<void> _addWeekPlanToFavourites() async {
    final name =
        await _promptPlanName(context, title: 'Add week plan to favourites');
    if (name == null) return;

    final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
    final days = <String, dynamic>{};
    for (final dk in dayKeys) {
      days[dk] = _snapshotDay(dk);
    }

    final result = await _createSavedMealPlanWithCap(
      docData: {
        'title': name,
        'type': 'week',
        'weekId': _ctrl.weekId,
        'savedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'days': days,
      },
    );

    if (!mounted) return;

    if (result == SavePlanResult.saved) {
      _snack('Added "$name" to favourites');
      return;
    }

    if (result == SavePlanResult.limitReached) {
      await _showLimitModal();
      return;
    }

    if (result == SavePlanResult.notLoggedIn) {
      await _showInfoModal(
        title: 'Not signed in',
        message: 'Please log in to save meal plans.',
      );
      return;
    }

    await _showInfoModal(
      title: 'Could not save',
      message: 'Something went wrong saving this plan. Try again.',
    );
  }

  // ------------------------------------------------------------
  // SHOPPING LOGIC
  // ------------------------------------------------------------
  void _openShoppingSheet() {
    Map<String, dynamic> planData;

    if (_mode == MealPlanViewMode.today) {
      final dayKey = (widget.focusDayKey?.isNotEmpty == true)
          ? widget.focusDayKey!
          : MealPlanKeys.todayKey();

      planData = {
        'type': 'day',
        'day': _snapshotDay(dayKey),
      };
    } else {
      final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
      final days = <String, dynamic>{};
      for (final dk in dayKeys) {
        days[dk] = _snapshotDay(dk);
      }
      planData = {
        'type': 'week',
        'days': days,
      };
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
    _mode = (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty)
        ? MealPlanViewMode.today
        : MealPlanViewMode.week;

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
    if (_recipes.isNotEmpty && FirebaseAuth.instance.currentUser != null) {
      await _ctrl.ensurePlanPopulated(recipes: _recipes);
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
      recipeAllergyTags: [],
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

  String formatDayKeyPretty(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return dayKey;
    const w = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${w[dt.weekday - 1]}, ${dt.day} ${m[dt.month - 1]}';
  }

  String _weekdayLetter(DateTime dt) {
    const l = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return l[dt.weekday - 1];
  }

  Map<String, dynamic> _dayRawForUI(String dayKey) {
    final out = <String, dynamic>{};
    for (final slot in MealPlanSlots.order) {
      final resolved = _ctrl.effectiveEntryForUI(dayKey, slot);
      if (resolved != null) out[slot] = resolved;
    }
    return out;
  }

  String _prettySlotLabel(String slot) {
    switch (slot.toLowerCase()) {
      case 'breakfast':
        return 'BREAKFAST';
      case 'lunch':
        return 'LUNCH';
      case 'dinner':
        return 'DINNER';
      case 'snack_1':
        return 'SNACK 1';
      case 'snack_2':
        return 'SNACK 2';
      default:
        return slot.toUpperCase();
    }
  }

  // ------------------------------------------------------------
  // ✅ REUSE FLOW (FIXED)
  // ------------------------------------------------------------
  Future<void> _reuseFromAnotherDay({
    required String dayKey,
    required String slot,
  }) async {
    final headerLabel =
        '${_prettySlotLabel(slot)} • ${formatDayKeyPretty(dayKey)}';

    final weekDayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
    final currentIndex = weekDayKeys.indexOf(dayKey);

    final candidates = <ReuseCandidate>[];

    // earlier days only, same slot
    for (var i = 0; i < weekDayKeys.length; i++) {
      final dk = weekDayKeys[i];
      if (currentIndex >= 0 && i >= currentIndex) break;

      final resolved = _ctrl.effectiveEntryForUI(dk, slot);
      final parsed = MealPlanEntryParser.parse(resolved);
      final rid = MealPlanEntryParser.entryRecipeId(parsed);

      // ✅ Only reuse recipes, skip empty slots or existing reuse links
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

    // ✅ Typed result - no more crash on "ReusePick" cast
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

    final headerLabel =
        '${_prettySlotLabel(slot)} • ${formatDayKeyPretty(dayKey)}';

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
    _ctrl.setDraftNote(dayKey, slot, text);
  }

  // ✅ Warning + cascade clear
  Future<void> _clearSlot({
    required String dayKey,
    required String slot,
  }) async {
    final normalizedSlot = _normSlot(slot);

    // 1) If this slot is itself a reuse target, confirm removing reuse
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

    // 2) If other slots depend on this slot via reuse, warn and offer cascade
    final deps = _ctrl.reuseDependents(
      fromDayKey: dayKey,
      fromSlot: normalizedSlot,
    );
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

    // 3) Normal clear
    _ctrl.setDraftClear(dayKey, slot);
  }

  Future<bool> _handleBack() async {
    if (_reviewMode) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return false;
    }
    return true;
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

    final focusDayKey = (widget.focusDayKey != null &&
            widget.focusDayKey!.trim().isNotEmpty)
        ? widget.focusDayKey!.trim()
        : MealPlanKeys.todayKey();

    final now = DateTime.now();

    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        appBar: AppBar(
          leading: _reviewMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _handleBack(),
                )
              : null,
          title: Text(
            _reviewMode
                ? 'Review meal plan'
                : (_mode == MealPlanViewMode.today
                    ? "Today's meal plan"
                    : "Next 7 days"),
          ),
          actions: _reviewMode
              ? []
              : [
                  IconButton(
                    tooltip: 'Add plan to favourites',
                    icon: const Icon(Icons.star_border_rounded),
                    onPressed: () async {
                      if (_mode == MealPlanViewMode.today) {
                        await _addDayPlanToFavourites(focusDayKey);
                      } else {
                        await _addWeekPlanToFavourites();
                      }
                    },
                  ),
                  if (_mode == MealPlanViewMode.today)
                    IconButton(
                      tooltip: 'View week',
                      icon: const Icon(Icons.calendar_month),
                      onPressed: () =>
                          setState(() => _mode = MealPlanViewMode.week),
                    )
                  else ...[
                    IconButton(
                      tooltip: 'Shopping List',
                      icon: const Icon(Icons.shopping_cart_outlined),
                      onPressed: _openShoppingSheet,
                    ),
                    IconButton(
                      tooltip: 'View today',
                      icon: const Icon(Icons.today),
                      onPressed: () =>
                          setState(() => _mode = MealPlanViewMode.today),
                    ),
                  ],
                  if (_mode == MealPlanViewMode.today)
                    IconButton(
                      tooltip: 'Shopping List',
                      icon: const Icon(Icons.shopping_cart_outlined),
                      onPressed: _openShoppingSheet,
                    ),
                ],
        ),
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final data = _ctrl.weekData;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }

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

                        // Keep styling but ALWAYS OPEN
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

                        // saving handled by bottom bar in this screen
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

            if (_mode == MealPlanViewMode.today) {
              return buildColourfulDay(
                focusDayKey,
                heroTop: "TODAY’S",
                heroBottom: "MEAL PLAN",
                isWeekMode: false,
              );
            }

            final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
            final initialIndex = dayKeys.indexOf(focusDayKey) >= 0
                ? dayKeys.indexOf(focusDayKey)
                : 0;

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
                            heroTop: formatDayKeyPretty(dayKey).toUpperCase(),
                            heroBottom: '',
                            isWeekMode: true,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
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

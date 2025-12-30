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

// ✅ Canonical entry parser
import 'widgets/meal_plan_entry_parser.dart';

// ✅ Colourful shared UI (Home version) used everywhere
import 'widgets/today_meal_plan_section.dart';

enum MealPlanViewMode { today, week }

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

  // ------------------------------------------------------------
  // ⭐ Favorites (read-only indicator)
  // ------------------------------------------------------------
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};

  // ------------------------------------------------------------
  // ✅ Random inspire (avoid “same order” + avoid recent repeats)
  // ------------------------------------------------------------
  final Random _rng = Random();
  final Map<String, List<int>> _recentBySlot = <String, List<int>>{};
  static const int _recentWindow = 12;

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

  // ------------------------------------------------------------
  // ✅ Saved meal plans helpers (day + week snapshots)
  // ------------------------------------------------------------

  CollectionReference<Map<String, dynamic>>? _savedPlansCol() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedMealPlans');
  }

  Future<String?> _promptPlanName(
    BuildContext context, {
    required String title,
  }) async {
    final ctrl = TextEditingController();

    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Name your meal plan',
          ),
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

  /// Convert an effective entry into a storable snapshot.
  /// Stored snapshot format:
  /// - recipe: { kind: 'recipe', id: <int>, source?: <string> }
  /// - note:   { kind: 'note', text: <string> }
  ///
  /// ✅ Uses MealPlanEntryParser so notes/recipes are interpreted consistently.
  Map<String, dynamic>? _snapshotSlotEntry(String dayKey, String slot) {
    final raw = _ctrl.effectiveEntry(dayKey, slot);
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
      };
    }

    final note = (MealPlanEntryParser.entryNoteText(e) ?? '').trim();
    if (note.isEmpty) return null;

    return {
      'kind': 'note',
      'text': note,
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

  Future<void> _saveDayPlanSnapshot(String dayKey) async {
    final col = _savedPlansCol();
    if (col == null) return;

    final name = await _promptPlanName(context, title: 'Save day plan');
    if (name == null) return;

    final payload = _snapshotDay(dayKey);

    await col.add({
      'title': name,
      'type': 'day',
      'savedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'day': payload,
      'meta': {
        'fromDayKey': dayKey,
        'fromWeekId': _ctrl.weekId,
      },
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved "$name"')));
  }

  Future<void> _saveWeekPlanSnapshot() async {
    final col = _savedPlansCol();
    if (col == null) return;

    final name = await _promptPlanName(context, title: 'Save week plan');
    if (name == null) return;

    final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);

    final days = <String, dynamic>{};
    for (final dk in dayKeys) {
      days[dk] = _snapshotDay(dk);
    }

    await col.add({
      'title': name,
      'type': 'week',
      'weekId': _ctrl.weekId,
      'savedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'days': days,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved "$name"')));
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

  // ------------------------------------------------------------
  // Firestore live listener for allergy changes
  // ------------------------------------------------------------
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

  // ------------------------------------------------------------
  // ⭐ Favorites listener (read-only)
  // Expects: users/{uid}/favorites docs with field { recipeId: <int|string> }
  // ------------------------------------------------------------
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

  bool _isFavorited(int? recipeId) {
    if (recipeId == null) return false;
    return _favoriteIds.contains(recipeId);
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

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------

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

  /// Returns: "safe" | "swap" | "blocked"
  String _statusTextOf(Map<String, dynamic> recipe) {
    if (_ctrl.excludedAllergens.isEmpty && _ctrl.childAllergens.isEmpty) {
      return 'safe';
    }

    final ingredientsText = _ingredientsTextOf(recipe);
    if (ingredientsText.isEmpty) return 'safe';

    final allAllergies = <String>{
      ..._ctrl.excludedAllergens,
      ..._ctrl.childAllergens,
    };

    final res = AllergyEngine.evaluateRecipe(
      ingredientsText: ingredientsText,
      childAllergies: allAllergies.toList(),
      includeSwapRecipes: true,
    );

    final s = res.status.toString().toLowerCase();
    if (s.contains('safe')) return 'safe';
    if (s.contains('swap')) return 'swap';
    return 'blocked';
  }

  int? _recipeIdFrom(Map<String, dynamic> r) {
    return MealPlanEntryParser.recipeIdFromAny(r['id']);
  }

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

  List<int> _availableSafeRecipeIds() {
    final ids = <int>[];
    for (final r in _recipes) {
      if (!_ctrl.recipeAllowed(r)) continue;
      final rid = _recipeIdFrom(r);
      if (rid != null) ids.add(rid);
    }
    return ids;
  }

  String formatDayKeyPretty(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return dayKey;

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
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

    final weekday = weekdays[dt.weekday - 1];
    final mon = months[dt.month - 1];
    return '$weekday, ${dt.day} $mon';
  }

  String _weekdayLetter(DateTime dt) {
    switch (dt.weekday) {
      case DateTime.monday:
        return 'M';
      case DateTime.tuesday:
        return 'T';
      case DateTime.wednesday:
        return 'W';
      case DateTime.thursday:
        return 'T';
      case DateTime.friday:
        return 'F';
      case DateTime.saturday:
        return 'S';
      case DateTime.sunday:
        return 'S';
      default:
        return '';
    }
  }

  /// Build a raw slot map for a given day using controller effective entries.
  /// TodayMealPlanSection will parse entries via MealPlanEntryParser internally.
  Map<String, dynamic> _dayRawFromController(String dayKey) {
    final out = <String, dynamic>{};
    for (final slot in MealPlanSlots.order) {
      final raw = _ctrl.effectiveEntry(dayKey, slot);
      if (raw != null) out[slot] = raw;
    }
    return out;
  }

  Future<void> _chooseRecipe({
    required String dayKey,
    required String slot,
  }) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChooseRecipeSheet(
        recipes: _recipes,
        titleOf: _titleOf,
        thumbOf: _thumbOf,
        idOf: _recipeIdFrom,
        statusTextOf: _statusTextOf,
      ),
    );

    if (picked != null) {
      _ctrl.setDraftRecipe(dayKey, slot, picked, source: 'manual');
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
          decoration: const InputDecoration(
            hintText: "e.g. Out for dinner / Visiting family",
          ),
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

  Future<void> _clearSlot({
    required String dayKey,
    required String slot,
  }) async {
    final ids = _availableSafeRecipeIds();

    final raw = _ctrl.effectiveEntry(dayKey, slot);
    final parsed = MealPlanEntryParser.parse(raw);
    final currentId = MealPlanEntryParser.entryRecipeId(parsed);

    final next = _pickRandomDifferentId(
      availableIds: ids,
      currentId: currentId,
      dayKey: dayKey,
      slot: slot,
    );

    if (next != null) {
      _ctrl.setDraftRecipe(dayKey, slot, next, source: 'auto');
    } else {
      _ctrl.setDraftNote(dayKey, slot, '');
    }
  }

  Future<void> _inspireSlot({
    required String dayKey,
    required String slot,
  }) async {
    final ids = _availableSafeRecipeIds();

    final currentParsed = MealPlanEntryParser.parse(
      _ctrl.effectiveEntry(dayKey, slot),
    );
    final currentId = MealPlanEntryParser.entryRecipeId(currentParsed);

    final next = _pickRandomDifferentId(
      availableIds: ids,
      currentId: currentId,
      dayKey: dayKey,
      slot: slot,
    );

    if (next != null) {
      _ctrl.setDraftRecipe(dayKey, slot, next, source: 'auto');
    }
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

    final focusDayKey =
        (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty)
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
                    tooltip: 'Today',
                    icon: const Icon(Icons.today),
                    onPressed: () =>
                        setState(() => _mode = MealPlanViewMode.today),
                  ),
                  IconButton(
                    tooltip: 'Next 7 days',
                    icon: const Icon(Icons.calendar_month),
                    onPressed: () =>
                        setState(() => _mode = MealPlanViewMode.week),
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
              VoidCallback? onViewWeek,
              bool includeSaveDayPlanButton = true,
            }) {
              final dayRaw = _dayRawFromController(dayKey);

              final pretty = formatDayKeyPretty(dayKey).toUpperCase();

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  TodayMealPlanSection(
                    todayRaw: dayRaw,
                    recipes: _recipes,
                    favoriteIds: _favoriteIds,

                    // ✅ WEEK HERO NOW HAS THE DATE
                    heroTopText: heroTop,
                    heroBottomText: heroBottom,

                    onOpenMealPlan: () {
                      if (_mode == MealPlanViewMode.today) {
                        setState(() => _mode = MealPlanViewMode.week);
                      }
                    },

                    // ✅ Keep all functionality
                    onInspireSlot: (slot) =>
                        _inspireSlot(dayKey: dayKey, slot: slot),
                    onChooseSlot: (slot) =>
                        _chooseRecipe(dayKey: dayKey, slot: slot),
                    onNoteSlot: (slot) async {
                      final currentParsed = MealPlanEntryParser.parse(
                        _ctrl.effectiveEntry(dayKey, slot),
                      );
                      final initial =
                          MealPlanEntryParser.entryNoteText(currentParsed);
                      await _addOrEditNote(
                        dayKey: dayKey,
                        slot: slot,
                        initial: initial,
                      );
                    },
                    onClearSlot: (slot) =>
                        _clearSlot(dayKey: dayKey, slot: slot),

                    canSave: _ctrl.hasDraftChanges(dayKey),
                    onSaveChanges: () async {
                      await _ctrl.saveDay(dayKey);
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text('Saved ${formatDayKeyPretty(dayKey)}'),
                        ),
                      );
                    },
                  ),

                  // Extra buttons that existed in the old DayView
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Column(
                      children: [
                        if (includeSaveDayPlanButton) ...[
                          SizedBox(
                            height: 52,
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => _saveDayPlanSnapshot(dayKey),
                              child: const Text('SAVE DAY PLAN'),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (onViewWeek != null) ...[
                          SizedBox(
                            height: 52,
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: onViewWeek,
                              child: const Text('VIEW NEXT 7 DAYS'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }

            // ✅ TODAY MODE (colourful)
            if (_mode == MealPlanViewMode.today) {
              return buildColourfulDay(
                focusDayKey,
                heroTop: "TODAY’S",
                heroBottom: "MEAL PLAN",
                onViewWeek: () => setState(() => _mode = MealPlanViewMode.week),
              );
            }

            // ✅ WEEK MODE (tabs + colourful day section in each tab)
            final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
            final initialIndex = () {
              final idx = dayKeys.indexOf(focusDayKey);
              return idx >= 0 ? idx : 0;
            }();

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
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        for (final dayKey in dayKeys)
                          buildColourfulDay(
                            dayKey,

                            // ✅ NEW: Date in the hero (instead of "Monday Meal Plan")
                            heroTop: formatDayKeyPretty(dayKey).toUpperCase(),
                            heroBottom: 'MEAL PLAN',

                            includeSaveDayPlanButton: true,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _saveWeekPlanSnapshot,
                        child: const Text('SAVE WEEK PLAN'),
                      ),
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

// ----------------------------------------------------
// Choose Recipe Sheet (safe + needs swap + excluded)
// ----------------------------------------------------
class _ChooseRecipeSheet extends StatefulWidget {
  final List<Map<String, dynamic>> recipes;
  final String Function(Map<String, dynamic>) titleOf;
  final String? Function(Map<String, dynamic>) thumbOf;
  final int? Function(Map<String, dynamic>) idOf;

  /// Return: "safe" | "swap" | "blocked" (or null = safe)
  final String Function(Map<String, dynamic> recipe)? statusTextOf;

  const _ChooseRecipeSheet({
    required this.recipes,
    required this.titleOf,
    required this.thumbOf,
    required this.idOf,
    this.statusTextOf,
  });

  @override
  State<_ChooseRecipeSheet> createState() => _ChooseRecipeSheetState();
}

class _ChooseRecipeSheetState extends State<_ChooseRecipeSheet> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _status(Map<String, dynamic> r) {
    final s = widget.statusTextOf?.call(r);
    if (s == null || s.trim().isEmpty) return 'safe';
    return s.toLowerCase();
  }

  bool _isSafe(Map<String, dynamic> r) => _status(r) == 'safe';
  bool _needsSwap(Map<String, dynamic> r) => _status(r) == 'swap';
  bool _isBlocked(Map<String, dynamic> r) => _status(r) == 'blocked';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.recipes.where((r) {
      if (_isBlocked(r)) return false;

      if (_q.trim().isEmpty) return true;
      final t = widget.titleOf(r).toLowerCase();
      return t.contains(_q.toLowerCase());
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search recipes',
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final id = widget.idOf(r);
                  final title = widget.titleOf(r);
                  final thumb = widget.thumbOf(r);

                  final safe = _isSafe(r);
                  final swap = _needsSwap(r);

                  final enabled = id != null && (safe || swap);

                  return ListTile(
                    enabled: enabled,
                    leading: thumb == null
                        ? const Icon(Icons.restaurant_menu)
                        : Image.network(
                            thumb,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.restaurant_menu),
                          ),
                    title: Text(title),
                    subtitle: swap ? const Text('Needs swap') : null,
                    trailing:
                        swap ? const Icon(Icons.swap_horiz, size: 18) : null,
                    onTap: !enabled ? null : () => Navigator.of(context).pop(id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------
// Dialog result helper
// ----------------------------------------------------
enum _NoteResultKind { cancel, save }

class _NoteResult {
  final _NoteResultKind kind;
  final String? text;

  const _NoteResult._(this.kind, this.text);

  const _NoteResult.cancel() : this._(_NoteResultKind.cancel, null);
  _NoteResult.save(String text) : this._(_NoteResultKind.save, text);
}

// ----------------------------------------------------
// ✅ Allergy review dialog choice (kept for future use)
// ----------------------------------------------------
enum _AllergyReviewChoice { keep, review }

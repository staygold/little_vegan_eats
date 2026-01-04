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

// ✅ Import shopping sheet
import 'widgets/meal_plan_shopping_sheet.dart';

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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};

  final Random _rng = Random();
  final Map<String, List<int>> _recentBySlot = <String, List<int>>{};
  static const int _recentWindow = 12;

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  
  int? _pickRandomDifferentId({
    required List<int> availableIds,
    required int? currentId,
    required String dayKey,
    required String slot,
  }) {
    if (availableIds.isEmpty) return null;
    final key = '$dayKey|$slot';
    final recent = _recentBySlot.putIfAbsent(key, () => <int>[]);
    final fresh = availableIds.where((id) => id != currentId && !recent.contains(id));
    final pool = (fresh.isNotEmpty) ? fresh.toList() : availableIds.where((id) => id != currentId).toList();
    if (pool.isEmpty) return null;
    final next = pool[_rng.nextInt(pool.length)];
    recent.add(next);
    if (recent.length > _recentWindow) recent.removeAt(0);
    return next;
  }

  CollectionReference<Map<String, dynamic>>? _savedPlansCol() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid).collection('savedMealPlans');
  }

  Future<String?> _promptPlanName(BuildContext context, {required String title}) async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Name your meal plan')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    final name = (res ?? '').trim();
    if (name.isEmpty) return null;
    return name;
  }

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
      return {'kind': 'recipe', 'id': rid, if (src.trim().isNotEmpty) 'source': src.trim()};
    }
    final note = (MealPlanEntryParser.entryNoteText(e) ?? '').trim();
    if (note.isEmpty) return null;
    return {'kind': 'note', 'text': note};
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
    final col = _savedPlansCol();
    if (col == null) return;
    final name = await _promptPlanName(context, title: 'Add day plan to favourites');
    if (name == null) return;
    final payload = _snapshotDay(dayKey);
    await col.add({
      'title': name,
      'type': 'day',
      'savedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'day': payload,
      'meta': {'fromDayKey': dayKey, 'fromWeekId': _ctrl.weekId},
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "$name" to favourites')));
  }

  Future<void> _addWeekPlanToFavourites() async {
    final col = _savedPlansCol();
    if (col == null) return;
    final name = await _promptPlanName(context, title: 'Add week plan to favourites');
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "$name" to favourites')));
  }

  // ------------------------------------------------------------
  // ✅ SHOPPING LOGIC
  // ------------------------------------------------------------
  void _openShoppingSheet() {
    Map<String, dynamic> planData;
    
    // 1. Construct correct payload based on view mode
    if (_mode == MealPlanViewMode.today) {
      // Just the focused day
      final dayKey = (widget.focusDayKey?.isNotEmpty == true) 
          ? widget.focusDayKey! 
          : MealPlanKeys.todayKey();
      
      planData = {
        'type': 'day',
        'day': _snapshotDay(dayKey),
      };
    } else {
      // Full week
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

    // 2. Build Title Map from loaded recipes (for instant display)
    final knownTitles = <int, String>{};
    for (final r in _recipes) {
      final id = _recipeIdFrom(r);
      final title = _titleOf(r);
      if (id != null) knownTitles[id] = title;
    }

    // 3. Open Sheet with 3 arguments
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
    _userDocSub = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().listen((snap) {
      final sets = AllergyProfile.buildFromUserDoc(snap.data());
      _ctrl.setAllergySets(excludedAllergens: sets.excludedAllergens, childAllergens: sets.childAllergens);
      if (mounted) setState(() {});
    });
  }

  void _startFavoritesListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _favSub?.cancel();
    _favSub = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('favorites').snapshots().listen((snap) {
      final next = <int>{};
      for (final d in snap.docs) {
        final raw = d.data()['recipeId'];
        final id = (raw is int) ? raw : int.tryParse(raw?.toString() ?? '');
        if (id != null && id > 0) next.add(id);
      }
      if (!mounted) return;
      setState(() { _favoriteIds..clear()..addAll(next); });
    });
  }

  Future<void> _loadAllergies() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final sets = AllergyProfile.buildFromUserDoc(snap.data());
      _ctrl.setAllergySets(excludedAllergens: sets.excludedAllergens, childAllergens: sets.childAllergens);
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
    if (r['meta'] is Map && r['meta']['ingredient_swaps'] != null) return r['meta']['ingredient_swaps'].toString();
    return '';
  }

  String _statusTextOf(Map<String, dynamic> recipe) {
    if (_ctrl.excludedAllergens.isEmpty && _ctrl.childAllergens.isEmpty) return 'safe';
    final allAllergies = <String>{..._ctrl.excludedAllergens, ..._ctrl.childAllergens}.toList();
    final res = AllergyEngine.evaluate(recipeAllergyTags: [], swapFieldText: _swapTextOf(recipe), userAllergies: allAllergies);
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

  String formatDayKeyPretty(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return dayKey;
    const w = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${w[dt.weekday - 1]}, ${dt.day} ${m[dt.month - 1]}';
  }

  String _weekdayLetter(DateTime dt) {
    const l = ['M','T','W','T','F','S','S'];
    return l[dt.weekday - 1];
  }

  Map<String, dynamic> _dayRawFromController(String dayKey) {
    final out = <String, dynamic>{};
    for (final slot in MealPlanSlots.order) {
      final raw = _ctrl.effectiveEntry(dayKey, slot);
      if (raw != null) out[slot] = raw;
    }
    return out;
  }

  Future<void> _chooseRecipe({required String dayKey, required String slot}) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChooseRecipeSheet(recipes: _recipes, titleOf: _titleOf, thumbOf: _thumbOf, idOf: _recipeIdFrom, statusTextOf: _statusTextOf),
    );
    if (picked != null) _ctrl.setDraftRecipe(dayKey, slot, picked, source: 'manual');
  }

  Future<void> _addOrEditNote({required String dayKey, required String slot, String? initial}) async {
    final textCtrl = TextEditingController(text: initial ?? '');
    final result = await showDialog<_NoteResult>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(controller: textCtrl, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: "e.g. Out for dinner")),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(const _NoteResult.cancel()), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(_NoteResult.save(textCtrl.text)), child: const Text('Confirm')),
        ],
      ),
    );
    if (result == null || result.kind == _NoteResultKind.cancel) return;
    final text = (result.text ?? '').trim();
    if (text.isEmpty) return;
    _ctrl.setDraftNote(dayKey, slot, text);
  }

  Future<void> _clearSlot({required String dayKey, required String slot}) async {
    final ids = _ctrl.getCandidatesForSlot(slot, _recipes);
    final currentParsed = MealPlanEntryParser.parse(_ctrl.effectiveEntry(dayKey, slot));
    final currentId = MealPlanEntryParser.entryRecipeId(currentParsed);
    final next = _pickRandomDifferentId(availableIds: ids, currentId: currentId, dayKey: dayKey, slot: slot);
    if (next != null) _ctrl.setDraftRecipe(dayKey, slot, next, source: 'auto');
    else _ctrl.setDraftNote(dayKey, slot, '');
  }

  Future<void> _inspireSlot({required String dayKey, required String slot}) async {
    final ids = _ctrl.getCandidatesForSlot(slot, _recipes);
    final currentParsed = MealPlanEntryParser.parse(_ctrl.effectiveEntry(dayKey, slot));
    final currentId = MealPlanEntryParser.entryRecipeId(currentParsed);
    final next = _pickRandomDifferentId(availableIds: ids, currentId: currentId, dayKey: dayKey, slot: slot);
    if (next != null) _ctrl.setDraftRecipe(dayKey, slot, next, source: 'auto');
    else if (ids.isEmpty) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No safe recipes found')));
  }

  Future<bool> _handleBack() async {
    if (_reviewMode) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return false;
    }
    return true;
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Log in to view your meal plan')));
    if (_recipesLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final focusDayKey = (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty) ? widget.focusDayKey!.trim() : MealPlanKeys.todayKey();
    final now = DateTime.now();

    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        appBar: AppBar(
          leading: _reviewMode ? IconButton(icon: const Icon(Icons.close), onPressed: () => _handleBack()) : null,
          title: Text(_reviewMode ? 'Review meal plan' : (_mode == MealPlanViewMode.today ? "Today's meal plan" : "Next 7 days")),
          actions: _reviewMode
              ? []
              : [
                  IconButton(
                    tooltip: 'Add plan to favourites',
                    icon: const Icon(Icons.star_border_rounded),
                    onPressed: () async {
                      if (_mode == MealPlanViewMode.today) await _addDayPlanToFavourites(focusDayKey);
                      else await _addWeekPlanToFavourites();
                    },
                  ),
                  if (_mode == MealPlanViewMode.today)
                    IconButton(tooltip: 'View week', icon: const Icon(Icons.calendar_month), onPressed: () => setState(() => _mode = MealPlanViewMode.week))
                  else ...[
                    // ✅ Shopping List Button (Week Mode)
                    IconButton(tooltip: 'Shopping List', icon: const Icon(Icons.shopping_cart_outlined), onPressed: _openShoppingSheet),
                    IconButton(tooltip: 'View today', icon: const Icon(Icons.today), onPressed: () => setState(() => _mode = MealPlanViewMode.today)),
                  ],
                  // ✅ Shopping List Button (Today Mode - added here)
                  if (_mode == MealPlanViewMode.today)
                    IconButton(tooltip: 'Shopping List', icon: const Icon(Icons.shopping_cart_outlined), onPressed: _openShoppingSheet),
                ],
        ),
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final data = _ctrl.weekData;
            if (data == null) return const Center(child: CircularProgressIndicator());

            Widget buildColourfulDay(String dayKey, {required String heroTop, required String heroBottom}) {
              final dayRaw = _dayRawFromController(dayKey);
              final canSave = _ctrl.hasDraftChanges(dayKey);

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
                        onOpenMealPlan: null,
                        onInspireSlot: (slot) => _inspireSlot(dayKey: dayKey, slot: slot),
                        onChooseSlot: (slot) => _chooseRecipe(dayKey: dayKey, slot: slot),
                        onNoteSlot: (slot) async {
                          final initial = MealPlanEntryParser.entryNoteText(MealPlanEntryParser.parse(_ctrl.effectiveEntry(dayKey, slot)));
                          await _addOrEditNote(dayKey: dayKey, slot: slot, initial: initial);
                        },
                        onClearSlot: (slot) => _clearSlot(dayKey: dayKey, slot: slot),
                        canSave: false,
                        onSaveChanges: null,
                      ),
                    ],
                  ),
                  if (canSave)
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: Container(
                          decoration: const BoxDecoration(color: Color(0xFF044246), boxShadow: [BoxShadow(offset: Offset(0, -6), blurRadius: 18, color: Color.fromRGBO(0, 0, 0, 0.10))]),
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                          child: SizedBox(
                            height: 52, width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                await _ctrl.saveDay(dayKey);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${formatDayKeyPretty(dayKey)}')));
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF32998D), shape: const StadiumBorder()),
                              child: const Text('SAVE CHANGES'),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }

            if (_mode == MealPlanViewMode.today) return buildColourfulDay(focusDayKey, heroTop: "TODAY’S", heroBottom: "MEAL PLAN");

            final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
            final initialIndex = dayKeys.indexOf(focusDayKey) >= 0 ? dayKeys.indexOf(focusDayKey) : 0;

            return DefaultTabController(
              length: dayKeys.length,
              initialIndex: initialIndex.clamp(0, dayKeys.length - 1),
              child: Column(
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: TabBar(isScrollable: false, tabs: [for (final k in dayKeys) Tab(text: _weekdayLetter(MealPlanKeys.parseDayKey(k) ?? now))]),
                  ),
                  Expanded(child: TabBarView(children: [for (final dayKey in dayKeys) buildColourfulDay(dayKey, heroTop: formatDayKeyPretty(dayKey).toUpperCase(), heroBottom: '')])),
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
// Choose Recipe Sheet & Note Result (Unchanged)
// ----------------------------------------------------
class _ChooseRecipeSheet extends StatefulWidget {
  final List<Map<String, dynamic>> recipes;
  final String Function(Map<String, dynamic>) titleOf;
  final String? Function(Map<String, dynamic>) thumbOf;
  final int? Function(Map<String, dynamic>) idOf;
  final String Function(Map<String, dynamic> recipe)? statusTextOf;
  const _ChooseRecipeSheet({required this.recipes, required this.titleOf, required this.thumbOf, required this.idOf, this.statusTextOf});
  @override
  State<_ChooseRecipeSheet> createState() => _ChooseRecipeSheetState();
}

class _ChooseRecipeSheetState extends State<_ChooseRecipeSheet> {
  final _search = TextEditingController();
  String _q = '';
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  String _status(Map<String, dynamic> r) => widget.statusTextOf?.call(r)?.toLowerCase() ?? 'safe';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.recipes.where((r) => _status(r) != 'blocked' && (_q.isEmpty || widget.titleOf(r).toLowerCase().contains(_q.toLowerCase()))).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(999))),
            TextField(controller: _search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search recipes'), onChanged: (v) => setState(() => _q = v)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final id = widget.idOf(r);
                  final swap = _status(r) == 'swap';
                  return ListTile(
                    enabled: id != null,
                    leading: widget.thumbOf(r) == null ? const Icon(Icons.restaurant_menu) : Image.network(widget.thumbOf(r)!, width: 44, height: 44, fit: BoxFit.cover),
                    title: Text(widget.titleOf(r)),
                    subtitle: swap ? const Text('Needs swap') : null,
                    trailing: swap ? const Icon(Icons.swap_horiz, size: 18) : null,
                    onTap: id != null ? () => Navigator.of(context).pop(id) : null,
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

enum _NoteResultKind { cancel, save }
class _NoteResult {
  final _NoteResultKind kind;
  final String? text;
  const _NoteResult._(this.kind, this.text);
  const _NoteResult.cancel() : this._(_NoteResultKind.cancel, null);
  _NoteResult.save(String text) : this._(_NoteResultKind.save, text);
}
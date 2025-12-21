import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_detail_screen.dart';
import '../recipes/allergy_engine.dart';
import '../utils/text.dart';
import '../utils/images.dart';
import '../recipes/recipe_repository.dart';

class MealPlanScreen extends StatefulWidget {
  final String? savedWeekId; // if provided, load this saved plan instead of "this week"
  const MealPlanScreen({super.key, this.savedWeekId});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  bool _loading = true;
  String? _error;

  // Recipes (from cache)
  List<Map<String, dynamic>> _recipes = [];

  // Child profiles
  bool _loadingChildren = true;
  String? _childrenError;
  List<ChildProfile> _children = [];
  ChildProfile? _selectedChild;
  bool _safeForAllChildren = true; // default
  bool _includeSwapRecipes = false; // safest default

  // -----------------------
  // Weekly plan
  // -----------------------
  // Map: "YYYY-MM-DD" -> { breakfast: id, lunch: id, dinner: id, snack1: id, snack2: id }
  Map<String, Map<String, int?>> _weekMeals = {};

  // -----------------------
  // Save-changes tracking
  // -----------------------
  final Map<String, int?> _originalFlat = {}; // snapshot of saved/loaded plan
  bool _saving = false;

  bool get _hasChanges {
    final current = _snapshotFlat();
    if (_originalFlat.isEmpty) return true; // conservative
    for (final k in current.keys) {
      if (_originalFlat[k] != current[k]) return true;
    }
    return false;
  }

  // Always snapshot all 7 days so change detection is reliable.
  Map<String, int?> _snapshotFlat() {
    final out = <String, int?>{};
    final days = _weekDays(DateTime.now());

    for (final d in days) {
      final dayKey = _dateKey(d);
      final meals = _weekMeals[dayKey] ?? const <String, int?>{};

      out['$dayKey|breakfast'] = meals['breakfast'];
      out['$dayKey|lunch'] = meals['lunch'];
      out['$dayKey|dinner'] = meals['dinner'];
      out['$dayKey|snack1'] = meals['snack1'];
      out['$dayKey|snack2'] = meals['snack2'];
    }

    return out;
  }

  void _captureOriginalSnapshot() {
    _originalFlat
      ..clear()
      ..addAll(_snapshotFlat());
  }

  // ------------------------------------------------------------
  // Helpers (FORWARD 7 DAYS)
  // ------------------------------------------------------------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DateTime> _weekDays(DateTime now) {
    // If viewing a saved week, start from that savedWeekId date (YYYY-MM-DD)
    final saved = widget.savedWeekId;
    if (saved != null && saved.length == 10) {
      final y = int.tryParse(saved.substring(0, 4));
      final m = int.tryParse(saved.substring(5, 7));
      final d = int.tryParse(saved.substring(8, 10));
      if (y != null && m != null && d != null) {
        final start = DateTime(y, m, d);
        return List.generate(7, (i) => start.add(Duration(days: i)));
      }
    }

    // Default: week forward (today + next 6)
    final start = _dateOnly(now);
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  String _dateKey(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _weekId(DateTime now) {
    // If viewing saved week, use it
    if (widget.savedWeekId != null) return widget.savedWeekId!;
    // Otherwise "this week forward" id = today
    return _dateKey(_dateOnly(now));
  }

  DocumentReference<Map<String, dynamic>>? _weekPlanRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPlansWeeks')
        .doc(_weekId(DateTime.now()));
  }

  // ------------------------------------------------------------
  // Recipe field helpers
  // ------------------------------------------------------------

  String _titleOf(Map<String, dynamic> r) =>
      (r['title']?['rendered'] as String?)?.trim().isNotEmpty == true
          ? (r['title']['rendered'] as String)
          : 'Untitled';

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
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
      final notes = stripHtml((row['notes'] ?? '').toString());
      if (name.isNotEmpty) buf.write('$name ');
      if (notes.isNotEmpty) buf.write('$notes ');
    }
    return buf.toString().trim();
  }

  Map<String, dynamic>? _byId(int? id) {
    if (id == null) return null;
    for (final r in _recipes) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  // ------------------------------------------------------------
  // Allergy helpers
  // ------------------------------------------------------------

  String? _canonicalAllergyKey(String raw) {
    final s = raw.trim().toLowerCase();

    if (s == 'soy') return 'soy';
    if (s == 'peanut' || s == 'peanuts') return 'peanut';
    if (s == 'tree_nut' || s == 'tree nut' || s == 'tree nuts' || s == 'nuts' || s == 'nut') {
      return 'tree_nut';
    }
    if (s == 'sesame') return 'sesame';
    if (s == 'gluten' || s == 'wheat') return 'gluten';

    if (s == 'coconut') return 'coconut';
    if (s == 'seed' || s == 'seeds') return 'seed';

    return null;
  }

  String _prettyAllergy(String key) {
    switch (key) {
      case 'soy':
        return 'Soy';
      case 'peanut':
        return 'Peanuts';
      case 'tree_nut':
        return 'Tree nuts';
      case 'sesame':
        return 'Sesame';
      case 'gluten':
        return 'Gluten/Wheat';
      case 'coconut':
        return 'Coconut';
      case 'seed':
        return 'Seeds';
      default:
        return key;
    }
  }

  String _combinedAllergiesLabel() {
    final set = <String>{};
    for (final c in _children) {
      // RESPECT TOGGLE:
      if (c.hasAllergies && c.allergies.isNotEmpty) {
        set.addAll(c.allergies);
      }
    }
    final list = set.toList()..sort();
    return list.isEmpty ? 'None' : list.map(_prettyAllergy).join(', ');
  }

  bool _isRecipeAllowedForChild(Map<String, dynamic> r, ChildProfile c) {
    // If toggle OFF or empty → allow
    if (!c.hasAllergies || c.allergies.isEmpty) return true;

    final res = AllergyEngine.evaluateRecipe(
      ingredientsText: _ingredientsTextOf(r),
      childAllergies: c.allergies,
      includeSwapRecipes: _includeSwapRecipes,
    );

    return res.status == AllergyStatus.safe || res.status == AllergyStatus.swapRequired;
  }

  bool _isRecipeAllowed(Map<String, dynamic> r) {
    if (_children.isEmpty) return true;

    if (_safeForAllChildren) {
      // Must pass every child that has allergies enabled
      for (final c in _children) {
        if (!_isRecipeAllowedForChild(r, c)) return false;
      }
      return true;
    } else {
      final c = _selectedChild;
      if (c == null) return true;
      return _isRecipeAllowedForChild(r, c);
    }
  }

  // ------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await _loadChildren();
    await _loadRecipesFromCache();
    await _loadOrGenerateWeekPlan();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  bool _weekHasInvalidIds() {
    for (final day in _weekMeals.values) {
      for (final id in day.values) {
        if (id != null && _byId(id) == null) return true;
      }
    }
    return false;
  }

  Future<void> _loadChildren() async {
    setState(() {
      _loadingChildren = true;
      _childrenError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _children = [];
          _selectedChild = null;
          _safeForAllChildren = true;
          _includeSwapRecipes = false;
          _loadingChildren = false;
        });
        return;
      }

      final doc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final raw = data['children'];

      final kids = <ChildProfile>[];

      if (raw is List) {
        for (final c in raw) {
          if (c is! Map) continue;

          final name = (c['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final hasAllergies = (c['hasAllergies'] == true);

          final allergiesRaw = c['allergies'];
          final parsed = <String>[];
          if (allergiesRaw is List) {
            for (final a in allergiesRaw) {
              final key = _canonicalAllergyKey(a.toString());
              if (key != null) parsed.add(key);
            }
          }

          // RESPECT TOGGLE: if OFF -> empty list no matter what's in Firestore
          final canonical = hasAllergies ? (parsed.toSet().toList()..sort()) : <String>[];

          kids.add(
            ChildProfile(
              name: name,
              hasAllergies: hasAllergies,
              allergies: canonical,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _children = kids;
        _selectedChild = kids.isNotEmpty ? kids.first : null;
        _safeForAllChildren = true;
        _includeSwapRecipes = false;
        _loadingChildren = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _childrenError = e.toString();
        _loadingChildren = false;
      });
    }
  }

  Future<void> _loadRecipesFromCache() async {
    try {
      final recipes = await RecipeRepository.ensureRecipesLoaded();
      if (!mounted) return;
      setState(() => _recipes = recipes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recipes = [];
        _error = 'Could not load recipes: $e';
      });
    }
  }

  // ------------------------------------------------------------
  // Weekly load/save
  // ------------------------------------------------------------

  Map<String, Map<String, int?>> _emptyWeekPlan() {
    final days = _weekDays(DateTime.now());
    final out = <String, Map<String, int?>>{};
    for (final d in days) {
      final key = _dateKey(d);
      out[key] = {
        'breakfast': null,
        'lunch': null,
        'dinner': null,
        'snack1': null,
        'snack2': null,
      };
    }
    return out;
  }

  Future<void> _loadOrGenerateWeekPlan() async {
    final ref = _weekPlanRef();

    // Not logged in → generate locally (no saving)
    if (ref == null) {
      _weekMeals = _generateNewWeekPlan();
      _captureOriginalSnapshot();
      return;
    }

    try {
      final snap = await ref.get();

      if (snap.exists) {
        final data = snap.data() ?? {};
        final rawDays = data['days'];

        final loaded = _emptyWeekPlan();

        if (rawDays is Map) {
          rawDays.forEach((dayKey, mealsVal) {
            final day = dayKey.toString();
            if (mealsVal is Map && loaded.containsKey(day)) {
              loaded[day] = {
                'breakfast': mealsVal['breakfast'] as int?,
                'lunch': mealsVal['lunch'] as int?,
                'dinner': mealsVal['dinner'] as int?,
                'snack1': mealsVal['snack1'] as int?,
                'snack2': mealsVal['snack2'] as int?,
              };
            }
          });
        }

        _weekMeals = loaded;

        // If ANY recipe ID no longer exists → regenerate week
        if (_weekHasInvalidIds()) {
          _weekMeals = _generateNewWeekPlan();
          await _saveWeekPlan();
        }

        _fillMissingMealsInWeek();
        if (mounted) setState(() {});
        _captureOriginalSnapshot();
        return;
      }

      // No week plan yet → generate + save baseline
      _weekMeals = _generateNewWeekPlan();
      if (mounted) setState(() {});
      await _saveWeekPlan(); // baseline save
      _captureOriginalSnapshot();
    } catch (_) {
      // Firestore fails → still generate locally so app works
      _weekMeals = _generateNewWeekPlan();
      if (mounted) setState(() {});
      _captureOriginalSnapshot();
    }
  }

  Future<void> _saveWeekPlan() async {
    final ref = _weekPlanRef();
    if (ref == null) return;

    await ref.set({
      'weekId': _weekId(DateTime.now()),
      'includeSwapRecipes': _includeSwapRecipes,
      'safeForAllChildren': _safeForAllChildren,
      'selectedChildName': _selectedChild?.name,
      'days': _weekMeals,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveChanges() async {
    if (_saving) return;

    final ref = _weekPlanRef();
    if (ref == null) {
      _captureOriginalSnapshot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved locally (not logged in)')),
        );
      }
      return;
    }

    setState(() => _saving = true);

    try {
      await _saveWeekPlan();
      _captureOriginalSnapshot();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSingleDay(String dayKey) async {
    if (_saving) return;

    final ref = _weekPlanRef();
    if (ref == null) {
      _captureOriginalSnapshot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved locally (not logged in)')),
        );
      }
      return;
    }

    final dayMeals = _weekMeals[dayKey];
    if (dayMeals == null) return;

    setState(() => _saving = true);

    try {
      await ref.set({
        'weekId': _weekId(DateTime.now()),
        'days': {dayKey: dayMeals},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _captureOriginalSnapshot();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save day: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------
  // Plan generation
  // ------------------------------------------------------------

  List<Map<String, dynamic>> _allowedPool() {
    if (_recipes.isEmpty) return [];
    return _recipes.where(_isRecipeAllowed).toList();
  }

  int? _pickRandomId(List<Map<String, dynamic>> pool, Set<int> used) {
    if (pool.isEmpty) return null;

    final rnd = Random();
    for (int i = 0; i < 60; i++) {
      final r = pool[rnd.nextInt(pool.length)];
      final id = r['id'];
      if (id is int && !used.contains(id)) {
        used.add(id);
        return id;
      }
    }

    // Allow duplicates if needed
    final r = pool[rnd.nextInt(pool.length)];
    final id = r['id'];
    return id is int ? id : null;
  }

  Map<String, Map<String, int?>> _generateNewWeekPlan() {
    final pool = _allowedPool();
    final used = <int>{};

    final days = _weekDays(DateTime.now());
    final out = <String, Map<String, int?>>{};

    for (final d in days) {
      final key = _dateKey(d);
      out[key] = {
        'breakfast': _pickRandomId(pool, used),
        'lunch': _pickRandomId(pool, used),
        'dinner': _pickRandomId(pool, used),
        'snack1': _pickRandomId(pool, used),
        'snack2': _pickRandomId(pool, used),
      };
    }

    return out;
  }

  void _fillMissingMealsInWeek() {
    final pool = _allowedPool();
    final used = <int>{};

    for (final day in _weekMeals.values) {
      for (final id in day.values) {
        if (id is int) used.add(id);
      }
    }

    _weekMeals.forEach((_, meals) {
      meals.forEach((slot, id) {
        if (id == null) meals[slot] = _pickRandomId(pool, used);
      });
    });
  }

  void _regenerateAllWeek() {
    setState(() => _weekMeals = _generateNewWeekPlan());
  }

  void _regenSlot(String dayKey, String slotKey) {
    final pool = _allowedPool();
    if (pool.isEmpty) return;

    final used = <int>{};
    final dayMeals = _weekMeals[dayKey];
    if (dayMeals != null) {
      for (final id in dayMeals.values) {
        if (id is int) used.add(id);
      }
    }

    final currentId = _weekMeals[dayKey]?[slotKey];
    if (currentId is int) used.remove(currentId);

    final newId = _pickRandomId(pool, used);

    setState(() {
      _weekMeals[dayKey] ??= {};
      _weekMeals[dayKey]![slotKey] = newId;
    });
  }

  // ------------------------------------------------------------
  // UI helpers
  // ------------------------------------------------------------

  String _weekdayLabel(DateTime d) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[d.weekday - 1];
  }

  String _niceDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_recipes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("This Week's Meal Plan")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error ??
                  'No recipes available yet. Open the recipe list once so recipes can be cached.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final hasAnyAllergies =
        _children.any((c) => c.hasAllergies && c.allergies.isNotEmpty);

    final days = _weekDays(DateTime.now());
    final start = days.first;
    final end = days.last;

    final selectedAllergies = (_selectedChild != null && _selectedChild!.hasAllergies)
        ? _selectedChild!.allergies
        : const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Text("This Week's Meal Plan (${_niceDate(start)}–${_niceDate(end)})"),
        actions: [
          IconButton(
            tooltip: 'Regenerate week',
            icon: const Icon(Icons.refresh),
            onPressed: _regenerateAllWeek,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          // Allergy controls
          if (_loadingChildren) ...[
            Row(
              children: const [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Loading child profiles...'),
              ],
            ),
            const SizedBox(height: 12),
          ] else if (_childrenError != null) ...[
            Row(
              children: [
                const Icon(Icons.error_outline, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Could not load children: $_childrenError',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(onPressed: _loadChildren, child: const Text('Retry')),
              ],
            ),
            const SizedBox(height: 12),
          ] else if (_children.isNotEmpty) ...[
            Row(
              children: [
                const Text('Suitable for:'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _safeForAllChildren ? '__all__' : _selectedChild?.name,
                    items: [
                      const DropdownMenuItem(value: '__all__', child: Text('All children')),
                      ..._children.map(
                        (c) => DropdownMenuItem(value: c.name, child: Text(c.name)),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;

                      setState(() {
                        _safeForAllChildren = (v == '__all__');
                        _selectedChild = _safeForAllChildren
                            ? (_children.isNotEmpty ? _children.first : null)
                            : _children.firstWhere((c) => c.name == v);

                        _includeSwapRecipes = false; // safest reset
                      });

                      _regenerateAllWeek();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hasAnyAllergies
                    ? (_safeForAllChildren
                        ? 'Allergies considered: ${_combinedAllergiesLabel()}'
                        : (selectedAllergies.isEmpty
                            ? 'No allergies saved.'
                            : 'Allergies: ${selectedAllergies.map(_prettyAllergy).join(', ')}'))
                    : 'No allergies saved.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (hasAnyAllergies) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include recipes that need swaps'),
                subtitle: const Text('Shows recipes with a safe replacement suggestion.'),
                value: _includeSwapRecipes,
                onChanged: (val) {
                  setState(() => _includeSwapRecipes = val);
                  _regenerateAllWeek();
                },
              ),
            ],
            const Divider(height: 24),
          ],

          // Week days
          ...days.map((d) {
            final dayKey = _dateKey(d);
            final meals = _weekMeals[dayKey] ?? const <String, int?>{};
            final label = '${_weekdayLabel(d)} ${_niceDate(d)}';

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _daySection(
                context: context,
                dayKey: dayKey,
                label: label,
                meals: meals,
              ),
            );
          }),

          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (!_hasChanges || _saving) ? null : _saveChanges,
              child: Text(_saving ? 'SAVING...' : (_hasChanges ? 'SAVE CHANGES' : 'NO CHANGES')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _daySection({
    required BuildContext context,
    required String dayKey,
    required String label,
    required Map<String, int?> meals,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),

            _mealCard(context: context, dayKey: dayKey, slotKey: 'breakfast', title: 'Breakfast', recipeId: meals['breakfast']),
            const SizedBox(height: 10),
            _mealCard(context: context, dayKey: dayKey, slotKey: 'lunch', title: 'Lunch', recipeId: meals['lunch']),
            const SizedBox(height: 10),
            _mealCard(context: context, dayKey: dayKey, slotKey: 'dinner', title: 'Dinner', recipeId: meals['dinner']),

            const SizedBox(height: 10),
            Text('Snacks', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            _mealCard(context: context, dayKey: dayKey, slotKey: 'snack1', title: 'Snack 1', recipeId: meals['snack1']),
            const SizedBox(height: 10),
            _mealCard(context: context, dayKey: dayKey, slotKey: 'snack2', title: 'Snack 2', recipeId: meals['snack2']),

            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _saving ? null : () => _saveSingleDay(dayKey),
                child: Text(_saving ? 'SAVING...' : 'SAVE DAY'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mealCard({
    required BuildContext context,
    required String dayKey,
    required String slotKey,
    required String title,
    required int? recipeId,
  }) {
    final r = _byId(recipeId);

    final recipeTitle = (r == null) ? 'No recipe found' : _titleOf(r);
    final thumb = (r == null) ? null : _thumbOf(r);
    final id = (r == null) ? null : (r['id'] as int?);

    String? tag;
    String? swapHint;

    final anyActiveAllergies =
        _children.any((c) => c.hasAllergies && c.allergies.isNotEmpty);

    if (r != null && _children.isNotEmpty && anyActiveAllergies) {
      final ingredientsText = _ingredientsTextOf(r);

      if (_safeForAllChildren) {
        bool anySwap = false;
        String? firstSwap;

        for (final c in _children) {
          if (!c.hasAllergies || c.allergies.isEmpty) continue;

          final res = AllergyEngine.evaluateRecipe(
            ingredientsText: ingredientsText,
            childAllergies: c.allergies,
            includeSwapRecipes: true, // tag purposes
          );

          if (res.status == AllergyStatus.swapRequired) {
            anySwap = true;
            firstSwap ??= (res.swapNotes.isNotEmpty ? res.swapNotes.first : null);
          }
        }

        tag = anySwap ? '⚠️ Swap required (one or more children)' : '✅ Safe for all children';
        swapHint = firstSwap;
      } else {
        final c = _selectedChild;
        if (c != null && c.hasAllergies && c.allergies.isNotEmpty) {
          final res = AllergyEngine.evaluateRecipe(
            ingredientsText: ingredientsText,
            childAllergies: c.allergies,
            includeSwapRecipes: true,
          );

          if (res.status == AllergyStatus.safe) {
            tag = '✅ Safe for ${c.name}';
          } else if (res.status == AllergyStatus.swapRequired) {
            tag = '⚠️ Swap required';
            if (res.swapNotes.isNotEmpty) swapHint = res.swapNotes.first;
          }
        }
      }
    }

    return Card(
      elevation: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: SizedBox(
          width: 60,
          height: 60,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: thumb == null
                ? const Icon(Icons.restaurant_menu)
                : Image.network(
                    thumb,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      final fallbackUrl = fallbackFromJetpack(thumb);
                      if (fallbackUrl == thumb) return const Icon(Icons.restaurant_menu);

                      return Image.network(
                        fallbackUrl,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const Icon(Icons.restaurant_menu),
                      );
                    },
                  ),
          ),
        ),
        title: Text('$title • $recipeTitle'),
        subtitle: (tag == null && swapHint == null)
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tag != null) Text(tag!, style: Theme.of(context).textTheme.bodySmall),
                    if (swapHint != null) ...[
                      const SizedBox(height: 2),
                      Text(swapHint!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
        trailing: IconButton(
          tooltip: 'Replace',
          icon: const Icon(Icons.refresh),
          onPressed: () => _regenSlot(dayKey, slotKey),
        ),
        onTap: id == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: id)),
                ),
      ),
    );
  }
}

// lib/meal_plan/widgets/meal_plan_shopping_sheet.dart

import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../lists/shopping_repo.dart';
import '../../recipes/recipe_repository.dart';
import '../../recipes/serving_engine.dart';
import '../../utils/text.dart'; // ✅ stripHtml parity with RecipeDetailScreen
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_slots.dart';
import '../../app/sub_header_bar.dart';

class _S {
  static const Color bg = Color(0xFFECF3F4);
  static const EdgeInsets metaPad = EdgeInsets.fromLTRB(16, 0, 16, 10);

  static TextStyle meta(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
            height: 1.2,
            fontSize: 14,
            fontVariations: const [FontVariation('wght', 600)],
            color: Colors.black.withOpacity(0.65),
          );

  static TextStyle h2(BuildContext context) =>
      (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
            fontVariations: const [FontVariation('wght', 800)],
          );

  static TextStyle header(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
            fontVariations: const [FontVariation('wght', 900)],
            letterSpacing: 0.6,
            color: Colors.black.withOpacity(0.70),
          );

  static TextStyle cardTitle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
            fontVariations: const [FontVariation('wght', 800)],
            height: 1.15,
          );

  static TextStyle cardSub(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
            fontVariations: const [FontVariation('wght', 650)],
            height: 1.2,
            color: Colors.black.withOpacity(0.62),
          );
}

class MealPlanShoppingSheet extends StatefulWidget {
  final Map<String, dynamic> planData; // 'type': 'week' or 'day'
  final Map<int, String> knownTitles; // titles to render instantly

  const MealPlanShoppingSheet({
    super.key,
    required this.planData,
    this.knownTitles = const {},
  });

  static Future<void> show(
    BuildContext context,
    Map<String, dynamic> planData,
    Map<int, String> knownTitles,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanShoppingSheet(
          planData: planData,
          knownTitles: knownTitles,
        ),
      ),
    );
  }

  @override
  State<MealPlanShoppingSheet> createState() => _MealPlanShoppingSheetState();
}

class _MealPlanShoppingSheetState extends State<MealPlanShoppingSheet> {
  // Step 0 = select meals, Step 1 = select list
  int _step = 0;
  final PageController _pageCtrl = PageController();

  // Plan selection
  final Set<String> _selectedKeys = {};
  final Map<String, int> _slotToRecipeId = {};
  late Map<int, String> _titles;

  // Family profile defaults (used ONLY to seed shared cards)
  int _profileAdults = 2;
  int _profileKids = 1;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  // Per-card state (shared recipes)
  final Map<String, int> _adultsByKey = {};
  final Map<String, int> _kidsByKey = {};
  final Set<String> _touchedPeopleKeys = {};

  // Per-card state (item recipes)
  final Map<String, int> _batchByKey = {};

  // Recipe mode + metadata cache
  final Map<int, bool> _isItemModeById = {};
  final Map<int, int> _baseServingsById = {}; // "adult portions" (base servings count)
  final Map<int, int?> _itemsPerPersonById = {};
  final Map<int, String> _itemLabelById = {};
  final Map<int, int> _itemsMadeById = {}; // baseServings * ipp (items mode only)

  // ✅ full recipe map cache (used for exact serving advice line + multiplier)
  final Map<int, Map<String, dynamic>> _recipeMapById = {};

  // List picker state
  final _listNameCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titles = Map.from(widget.knownTitles);
    _parsePlan();
    _wireFamilyProfile();
    _primeRecipeMetaCache();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    _pageCtrl.dispose();
    _listNameCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Family profile (defaults only; NOT global UI)
  // ---------------------------------------------------------------------------

  void _wireFamilyProfile() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _profileSub?.cancel();

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _profileAdults = 2;
          _profileKids = 1;
        });
        return;
      }

      final docRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      _profileSub = docRef.snapshots().listen((snap) {
        final data = snap.data();
        if (data == null) return;

        final adults = (data['adults'] as List?) ?? const [];
        final children = (data['children'] as List?) ?? const [];

        final adultCount = adults
            .where((e) =>
                e is Map &&
                (e['name'] ?? '').toString().trim().isNotEmpty)
            .length;
        final kidCount = children
            .where((e) =>
                e is Map &&
                (e['name'] ?? '').toString().trim().isNotEmpty)
            .length;

        final nextAdults = adultCount > 0 ? adultCount : 1;
        final nextKids = kidCount;

        if (!mounted) return;

        setState(() {
          _profileAdults = nextAdults;
          _profileKids = nextKids;

          // Apply defaults to any shared-recipe cards the user hasn't touched yet
          for (final key in _slotToRecipeId.keys) {
            final rid = _slotToRecipeId[key];
            if (rid == null) continue;
            final isItem = _isItemModeById[rid] == true;
            if (isItem) continue;

            if (!_touchedPeopleKeys.contains(key)) {
              _adultsByKey[key] = _adultsByKey[key] ?? _profileAdults;
              _kidsByKey[key] = _kidsByKey[key] ?? _profileKids;
            }
          }
        });
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Plan parsing
  // ---------------------------------------------------------------------------

  void _parsePlan() {
    final type = widget.planData['type'] ?? 'week';

    void processDay(String dayKey, Map dayData) {
      for (final slot in MealPlanSlots.order) {
        final entry = dayData[slot];
        if (entry is Map &&
            (entry['kind'] == 'recipe' || entry.containsKey('recipeId'))) {
          final rawId = entry['recipeId'] ?? entry['id'];
          final rid = int.tryParse(rawId.toString());
          if (rid == null) continue;

          final key = '$dayKey|$slot';
          _slotToRecipeId[key] = rid;

          // Default selected
          _selectedKeys.add(key);

          // Title placeholder if needed
          _titles.putIfAbsent(rid, () => 'Recipe #$rid');

          // Defaults
          _batchByKey[key] = 1;
        }
      }
    }

    if (type == 'day') {
      final day = widget.planData['day'];
      if (day is Map) processDay('Today', day);
    } else {
      final days = widget.planData['days'];
      if (days is Map) {
        final keys = days.keys.toList()..sort();
        for (final k in keys) {
          if (days[k] is Map) processDay(k.toString(), days[k]);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Recipe meta helpers (mirrors RecipeDetailScreen tag reading)
  // ---------------------------------------------------------------------------

  String _termSlug(Map<String, dynamic>? recipe, String groupKey) {
    final tags = recipe?['tags'];
    if (tags is Map) {
      final list = tags[groupKey];
      if (list is List && list.isNotEmpty && list.first is Map) {
        final m = list.first as Map;
        final slug = (m['slug'] ?? '').toString().trim();
        if (slug.isNotEmpty) return slug;
      }
    }
    return '';
  }

  String _termName(Map<String, dynamic>? recipe, String groupKey) {
    final tags = recipe?['tags'];
    if (tags is Map) {
      final list = tags[groupKey];
      if (list is List && list.isNotEmpty && list.first is Map) {
        final m = list.first as Map;
        final name = (m['name'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    }
    return '';
  }

  int? _termNameInt(Map<String, dynamic>? recipe, String groupKey) {
    final s = _termName(recipe, groupKey);
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  bool _isItemsMode(Map<String, dynamic>? recipe) {
    final slug = _termSlug(recipe, 'serving_mode').toLowerCase();
    return slug == 'item' || slug == 'items';
  }

  String _itemLabelSingular(Map<String, dynamic>? recipe) {
    final label = _termName(recipe, 'item_label').toLowerCase().trim();
    return label.isNotEmpty ? label : 'item';
  }

  int? _itemsPerPerson(Map<String, dynamic>? recipe) =>
      _termNameInt(recipe, 'items_per_person');

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  int _servingsFromRecipeMap(Map<String, dynamic> raw) {
    final root = (raw['recipe'] is Map) ? (raw['recipe'] as Map) : raw;

    final candidates = [
      root['servings'],
      root['servings_number'],
      root['servings_amount'],
      root['wprm_servings'],
      root['yield'],
      raw['servings'],
      raw['servings_number'],
      raw['servings_amount'],
      raw['wprm_servings'],
      raw['yield'],
    ];

    for (final c in candidates) {
      final n = _toInt(c);
      if (n > 0) return n;
    }
    return 1;
  }

  Future<void> _primeRecipeMetaCache() async {
    final ids = _slotToRecipeId.values.toSet().toList();

    for (final id in ids) {
      if (_isItemModeById.containsKey(id)) continue;

      try {
        final raw = await RecipeRepository.getRecipeById(id);

        final recipe = (raw['recipe'] is Map)
            ? Map<String, dynamic>.from(raw['recipe'] as Map)
            : Map<String, dynamic>.from(raw);

        final baseServings = _servingsFromRecipeMap(raw);
        final itemsMode = _isItemsMode(recipe);
        final ipp = itemsMode ? _itemsPerPerson(recipe) : null;
        final label = itemsMode ? _itemLabelSingular(recipe) : '';

        int itemsMade = 0;
        if (itemsMode && ipp != null && ipp > 0) {
          itemsMade = (baseServings * ipp).clamp(0, 999999);
        }

        if (!mounted) return;
        setState(() {
          _baseServingsById[id] = baseServings;
          _isItemModeById[id] = itemsMode;
          _itemsPerPersonById[id] = ipp;
          _itemLabelById[id] = label;
          if (itemsMode) _itemsMadeById[id] = itemsMade;

          // ✅ cache full recipe map for exact shared “You need…” line + multiplier
          _recipeMapById[id] = recipe;
        });

        // Apply per-card defaults
        if (!mounted) return;
        setState(() {
          for (final key in _slotToRecipeId.keys) {
            if (_slotToRecipeId[key] != id) continue;

            if (itemsMode) {
              _batchByKey[key] = _batchByKey[key] ?? 1;
            } else {
              if (!_touchedPeopleKeys.contains(key)) {
                _adultsByKey[key] = _adultsByKey[key] ?? _profileAdults;
                _kidsByKey[key] = _kidsByKey[key] ?? _profileKids;
              }
            }
          }
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _baseServingsById[id] = 1;
          _isItemModeById[id] = false; // assume shared
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ✅ Shared card subtitle: EXACT same logic as RecipeDetailScreen (via ServingEngine)
  // ---------------------------------------------------------------------------

  String _sharedNeedsLine({
    required int recipeId,
    required int adults,
    required int kids,
  }) {
    final recipe = _recipeMapById[recipeId];
    if (recipe == null) return 'You need the equivalent of ~0 adult portions';

    try {
      final advice =
          buildServingAdvice(recipe: recipe, adults: adults, kids: kids);
      final line = advice.detailLine.trim();
      return line.isNotEmpty
          ? line
          : 'You need the equivalent of ~0 adult portions';
    } catch (_) {
      return 'You need the equivalent of ~0 adult portions';
    }
  }

  // ---------------------------------------------------------------------------
  // ✅ Shared scaling: AUTO-APPLY RecipeDetailScreen "recommended" multiplier
  // (NO update button; shopping sheet always uses the recommended multiplier)
  // ---------------------------------------------------------------------------

  double _recommendedScaleForShared({
    required Map<String, dynamic> recipe,
    required int adults,
    required int kids,
  }) {
    try {
      final advice =
          buildServingAdvice(recipe: recipe, adults: adults, kids: kids);

      final needsMore = advice.multiplierRaw > 1.0;
      final showHalf = advice.canHalf && !needsMore;

      final rec = showHalf ? 0.5 : advice.recommendedMultiplier;
      if (rec == null || rec.isNaN || rec <= 0) return 1.0;
      return rec;
    } catch (_) {
      return 1.0;
    }
  }

  double _ingredientScaleForKey(String key, int rid) {
    final isItem = _isItemModeById[rid] == true;

    if (isItem) {
      final b = (_batchByKey[key] ?? 1).clamp(1, 20);
      return b.toDouble();
    }

    final a = (_adultsByKey[key] ?? _profileAdults).clamp(0, 20);
    final k = (_kidsByKey[key] ?? _profileKids).clamp(0, 20);

    final recipe = _recipeMapById[rid];
    if (recipe == null) return 1.0;
    return _recommendedScaleForShared(recipe: recipe, adults: a, kids: k);
  }

  String _fmtMultiplier(double v) {
    final s = v.toStringAsFixed(1);
    final clean = s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    return '${clean}x';
  }

  String _sharedSubtitleLine(String key, int rid, int adults, int kids) {
    final needs = _sharedNeedsLine(recipeId: rid, adults: adults, kids: kids);

    final recipe = _recipeMapById[rid];
    if (recipe == null) return needs;

    final scale = _recommendedScaleForShared(recipe: recipe, adults: adults, kids: kids);
    if ((scale - 1.0).abs() < 0.001) return needs;

    final label =
        (scale - 0.5).abs() < 0.001 ? 'Half batch' : '${_fmtMultiplier(scale)} batch';
    return '$needs • Using $label';
  }

  // ---------------------------------------------------------------------------
  // ✅ EXACT ingredient scaling/parsing logic from RecipeDetailScreen
  // ---------------------------------------------------------------------------

  bool _rowHasConverted2(Map row) {
    final converted = row['converted'];
    if (converted is Map) {
      final c2 = converted['2'] ?? converted[2];
      if (c2 is Map) {
        final amt = c2['amount']?.toString().trim() ?? '';
        final unit = c2['unit']?.toString().trim() ?? '';
        return amt.isNotEmpty || unit.isNotEmpty;
      }
    }
    return false;
  }

  Map<String, dynamic>? _converted2(Map row) {
    final converted = row['converted'];
    if (converted is Map) {
      final c2 = converted['2'] ?? converted[2];
      if (c2 is Map) return Map<String, dynamic>.from(c2.cast<String, dynamic>());
    }
    return null;
  }

  double? _parseAmountToDouble(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    const unicode = {
      '½': 0.5,
      '⅓': 1 / 3,
      '⅔': 2 / 3,
      '¼': 0.25,
      '¾': 0.75,
      '⅛': 0.125,
      '⅜': 0.375,
      '⅝': 0.625,
      '⅞': 0.875
    };
    if (unicode.containsKey(s)) return unicode[s];

    final mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(s);
    if (mixed != null) {
      final whole = double.parse(mixed.group(1)!);
      final a = double.parse(mixed.group(2)!);
      final b = double.parse(mixed.group(3)!);
      if (b == 0) return null;
      return whole + (a / b);
    }

    final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(s);
    if (frac != null) {
      final a = double.parse(frac.group(1)!);
      final b = double.parse(frac.group(2)!);
      if (b == 0) return null;
      return a / b;
    }

    return double.tryParse(s);
  }

  String _fmtSmart(double v) {
    if ((v - v.roundToDouble()).abs() < 0.0001) return v.round().toString();
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  String _scaledAmount(String rawAmount, double mult) {
    final a = rawAmount.trim();
    if (a.isEmpty || (mult - 1.0).abs() < 0.0000001) return a;

    final mX = RegExp(r'^\s*([0-9]+(?:\.\d+)?)(\s*x\s*)$', caseSensitive: false).firstMatch(a);
    if (mX != null) return '${_fmtSmart(double.parse(mX.group(1)!) * mult)} x';

    final mPrefix = RegExp(
      r'^\s*([0-9]+(?:\.\d+)?(?:\s+[0-9]+\s*/\s*[0-9]+|(?:\s*/\s*[0-9]+)?)|[½⅓⅔¼¾⅛⅜⅝⅞])',
    ).firstMatch(a);

    if (mPrefix != null) {
      final prefix = mPrefix.group(1)!.trim();
      final parsed = _parseAmountToDouble(prefix);
      if (parsed != null) {
        final scaled = _fmtSmart(parsed * mult);
        return a.replaceFirst(mPrefix.group(1)!, scaled).trim();
      }
    }

    final mNum = RegExp(r'^\s*([0-9]+(?:\.\d+)?)').firstMatch(a);
    if (mNum != null) {
      return a.replaceFirst(mNum.group(1)!, _fmtSmart(double.parse(mNum.group(1)!) * mult)).trim();
    }

    return a;
  }

  List<ShoppingIngredient> _ingredientsToShoppingIngredientsExact(
    Map<String, dynamic>? recipe,
    double scale,
  ) {
    if (recipe == null) return const [];

    final ingredientsFlat =
        (recipe['ingredients_flat'] is List) ? (recipe['ingredients_flat'] as List) : const [];
    if (ingredientsFlat.isEmpty) return const [];

    final out = <ShoppingIngredient>[];

    for (final row in ingredientsFlat) {
      if (row is! Map) continue;

      final type = (row['type'] ?? '').toString().toLowerCase();
      if (type == 'group' || type == 'header') continue;

      final name = (row['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final notes = stripHtml((row['notes'] ?? '').toString()).trim();

      final metricAmount = _scaledAmount((row['amount'] ?? '').toString(), scale).trim();
      final metricUnit = (row['unit'] ?? '').toString().trim();

      String usAmount = '';
      String usUnit = '';
      if (_rowHasConverted2(row)) {
        final c2 = _converted2(row);
        usAmount = _scaledAmount((c2?['amount'] ?? '').toString(), scale).trim();
        usUnit = (c2?['unit'] ?? '').toString().trim();
      }

      out.add(
        ShoppingIngredient(
          name: name,
          notes: notes,
          metricAmount: metricAmount,
          metricUnit: metricUnit,
          usAmount: usAmount,
          usUnit: usUnit,
        ),
      );
    }

    return out;
  }

  // ---------------------------------------------------------------------------
  // Add to list execution
  // ---------------------------------------------------------------------------

  Future<void> _executeAdd({String? existingListId, String? newListName}) async {
    setState(() => _isLoading = true);

    try {
      String listId = existingListId ?? '';

      if (newListName != null && newListName.trim().isNotEmpty) {
        final ref = await ShoppingRepo.instance.createList(newListName.trim());
        listId = ref.id;
      }
      if (listId.isEmpty) throw Exception('No list selected');

      int addedRecipeCount = 0;

      for (final key in _selectedKeys) {
        final rid = _slotToRecipeId[key];
        if (rid == null) continue;

        final raw = await RecipeRepository.getRecipeById(rid);

        final recipe = (raw['recipe'] is Map)
            ? Map<String, dynamic>.from(raw['recipe'] as Map)
            : Map<String, dynamic>.from(raw);

        // keep cache in sync
        _recipeMapById[rid] = recipe;

        final ingredientScale = _ingredientScaleForKey(key, rid);

        final ingredients = _ingredientsToShoppingIngredientsExact(recipe, ingredientScale);
        if (ingredients.isEmpty) continue;

        final title = _titles[rid] ?? 'Recipe';

        await ShoppingRepo.instance.addIngredients(
          listId: listId,
          ingredients: ingredients,
          recipeId: rid,
          recipeTitle: title,
        );

        addedRecipeCount++;
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $addedRecipeCount recipes to shopping list')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _goToStep2() {
    if (_selectedKeys.isEmpty) return;
    setState(() => _step = 1);
    _pageCtrl.animateToPage(
      1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _goBack() {
    setState(() => _step = 0);
    _pageCtrl.animateToPage(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  // ---------------------------------------------------------------------------
  // ✅ Week tab helpers (match MealPlanScreen vibe)
  // ---------------------------------------------------------------------------

  String _weekdayLetter(DateTime dt) {
    const l = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return l[dt.weekday - 1];
  }

  List<String> _orderedWeekDayKeys() {
    // We only call this when planData.type == 'week'
    final days = widget.planData['days'];
    if (days is! Map) return const [];

    final keys = days.keys.map((e) => e.toString()).toList();

    keys.sort((a, b) {
      final da = MealPlanKeys.parseDayKey(a);
      final db = MealPlanKeys.parseDayKey(b);
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.compareTo(b);
    });

    return keys;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final subtitle = (widget.planData['type'] == 'day') ? 'Today' : 'This week';

    final bottomBar = (_step == 0)
        ? SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: _S.bg,
                border: Border(top: BorderSide(color: Colors.black.withOpacity(0.06))),
              ),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedKeys.isEmpty || _isLoading ? null : _goToStep2,
                  style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
                  child: Text('Add ${_selectedKeys.length} recipes to shopping list'),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    return Scaffold(
      backgroundColor: _S.bg,
      body: Column(
        children: [
          const SubHeaderBar(title: 'Add to shopping list'),
          Padding(
            padding: _S.metaPad,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _step == 0 ? 'Select recipes ($subtitle)' : 'Select list',
                    style: _S.meta(context),
                  ),
                ),
                if (_step == 1)
                  TextButton.icon(
                    onPressed: _isLoading ? null : _goBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Back'),
                  ),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep1SelectMeals(),
                _buildStep2SelectList(),
              ],
            ),
          ),
          bottomBar,
        ],
      ),
    );
  }

  String _slotHeaderLabel(String slot) {
    final s = slot.toLowerCase();
    if (s.contains('breakfast')) return 'BREAKFAST';
    if (s.contains('lunch')) return 'LUNCH';
    if (s.contains('dinner')) return 'DINNER';
    if (s.contains('snack')) return 'SNACK';
    return slot.toUpperCase();
  }

  int _slotScore(String s) {
    final x = s.toLowerCase();
    if (x.contains('breakfast')) return 1;
    if (x.contains('lunch')) return 2;
    if (x.contains('dinner')) return 3;
    if (x.contains('snack')) return 4;
    return 99;
  }

  /// ✅ Day-mode (single day) stays as-is.
  /// ✅ Week-mode now uses the SAME day tabs pattern as MealPlanScreen.
  Widget _buildStep1SelectMeals() {
    final isDayMode = widget.planData['type'] == 'day';

    if (isDayMode) {
      // Existing behaviour for "day" (single day): one list.
      final grouped = <String, List<String>>{};
      for (final key in _slotToRecipeId.keys) {
        final day = key.split('|').first;
        grouped.putIfAbsent(day, () => []).add(key);
      }
      final days = grouped.keys.toList()..sort();

      return ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          ...days.map((dayKey) {
            final slotKeys = grouped[dayKey]!;
            slotKeys.sort((a, b) {
              final sa = a.split('|').last;
              final sb = b.split('|').last;
              final pa = _slotScore(sa);
              final pb = _slotScore(sb);
              if (pa != pb) return pa.compareTo(pb);
              return sa.compareTo(sb);
            });

            final bySlot = <String, List<String>>{};
            for (final k in slotKeys) {
              final slot = k.split('|').last;
              bySlot.putIfAbsent(slot, () => []).add(k);
            }

            final orderedSlots = bySlot.keys.toList()
              ..sort((a, b) => _slotScore(a).compareTo(_slotScore(b)));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final slot in orderedSlots) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Text(_slotHeaderLabel(slot), style: _S.header(context)),
                  ),
                  for (final key in bySlot[slot]!) _mealCard(key),
                ],
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
        ],
      );
    }

    // ✅ Week-mode: Day tabs (like MealPlanScreen)
    final dayKeys = _orderedWeekDayKeys();
    if (dayKeys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No meals found in this plan.',
          style: TextStyle(color: Colors.black.withOpacity(0.6)),
        ),
      );
    }

    final now = DateTime.now();
    int initialIndex = 0;
    final todayKey = MealPlanKeys.todayKey();
    final idx = dayKeys.indexOf(todayKey);
    if (idx >= 0) initialIndex = idx;

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
                    text: _weekdayLetter(MealPlanKeys.parseDayKey(k) ?? now),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final dayKey in dayKeys) _buildDayTab(dayKey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayTab(String dayKey) {
    // Pull the keys for THIS day only
    final keysForDay = _slotToRecipeId.keys
        .where((k) => k.startsWith('$dayKey|'))
        .toList();

    if (keysForDay.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              _prettyDay(dayKey),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.black.withOpacity(0.72),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'No meals planned for this day.',
              style: TextStyle(color: Colors.black.withOpacity(0.6)),
            ),
          ),
        ],
      );
    }

    // Group by slot for this day
    final bySlot = <String, List<String>>{};
    for (final k in keysForDay) {
      final slot = k.split('|').last;
      bySlot.putIfAbsent(slot, () => []).add(k);
    }

    final orderedSlots = bySlot.keys.toList()
      ..sort((a, b) => _slotScore(a).compareTo(_slotScore(b)));

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            _prettyDay(dayKey),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black.withOpacity(0.72),
            ),
          ),
        ),
        for (final slot in orderedSlots) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Text(_slotHeaderLabel(slot), style: _S.header(context)),
          ),
          for (final key in bySlot[slot]!) _mealCard(key),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _mealCard(String key) {
    final rid = _slotToRecipeId[key];
    final title = (rid != null) ? (_titles[rid] ?? 'Recipe') : 'Recipe';

    final selected = _selectedKeys.contains(key);
    final isItem = (rid != null) ? (_isItemModeById[rid] == true) : false;

    // Shared defaults
    final adults = (_adultsByKey[key] ?? _profileAdults).clamp(0, 20);
    final kids = (_kidsByKey[key] ?? _profileKids).clamp(0, 20);

    // Item defaults
    final batch = (_batchByKey[key] ?? 1).clamp(1, 20);
    final itemLabel = (rid != null) ? (_itemLabelById[rid] ?? 'item') : 'item';
    final itemsMadeBase = (rid != null) ? (_itemsMadeById[rid] ?? 0) : 0;

    String subtitleLine;

    if (isItem) {
      final itemsMadeScaled =
          (itemsMadeBase > 0) ? (itemsMadeBase * batch).clamp(0, 999999) : 0;
      if (itemsMadeBase > 0) {
        final plural = (itemsMadeScaled == 1) ? itemLabel : '${itemLabel}s';
        subtitleLine = 'Makes $itemsMadeScaled $plural';
      } else {
        subtitleLine = 'Makes items';
      }
    } else {
      if (rid == null) {
        subtitleLine = 'You need the equivalent of ~0 adult portions';
      } else {
        subtitleLine = _sharedSubtitleLine(key, rid, adults, kids);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
          boxShadow: const [
            BoxShadow(
              offset: Offset(0, 6),
              blurRadius: 18,
              color: Color.fromRGBO(0, 0, 0, 0.06),
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedKeys.add(key);

                      if (isItem) {
                        _batchByKey[key] = _batchByKey[key] ?? 1;
                      } else {
                        _adultsByKey[key] = _adultsByKey[key] ?? _profileAdults;
                        _kidsByKey[key] = _kidsByKey[key] ?? _profileKids;
                      }
                    } else {
                      _selectedKeys.remove(key);
                    }
                  });
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: _S.cardTitle(context), maxLines: 2),
                      const SizedBox(height: 8),
                      Text(subtitleLine, style: _S.cardSub(context)),
                      if (!isItem) ...[
                        const SizedBox(height: 12),
                        _PeopleStepperRow(
                          label: 'Adults',
                          value: adults,
                          enabled: selected,
                          onChanged: (next) {
                            setState(() {
                              _touchedPeopleKeys.add(key);
                              _adultsByKey[key] = next.clamp(0, 20);
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        _PeopleStepperRow(
                          label: 'Kids',
                          value: kids,
                          enabled: selected,
                          onChanged: (next) {
                            setState(() {
                              _touchedPeopleKeys.add(key);
                              _kidsByKey[key] = next.clamp(0, 20);
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (isItem) ...[
                const SizedBox(width: 10),
                _BatchPill(
                  value: batch,
                  enabled: selected,
                  onChanged: (next) => setState(() => _batchByKey[key] = next),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep2SelectList() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Text('Choose a list to add ingredients to.', style: _S.meta(context)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create new list',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.black.withOpacity(0.80),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _listNameCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'e.g. Week 1 Shop',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.black.withOpacity(0.10)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.black.withOpacity(0.10)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.black.withOpacity(0.22), width: 1.4),
                    ),
                  ),
                  onSubmitted: (_) {
                    final name = _listNameCtrl.text.trim();
                    if (name.isNotEmpty && !_isLoading) _executeAdd(newListName: name);
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            final name = _listNameCtrl.text.trim();
                            if (name.isNotEmpty) _executeAdd(newListName: name);
                          },
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Create & add'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Your lists', style: _S.h2(context)),
        ),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.60,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ShoppingRepo.instance.listsStream(),
            builder: (ctx, snap) {
              final docs = snap.data?.docs ?? [];

              if (snap.connectionState == ConnectionState.waiting && docs.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No lists yet. Create one above.',
                    style: TextStyle(color: Colors.black.withOpacity(0.6)),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.black.withOpacity(0.06)),
                itemBuilder: (ctx, i) {
                  final d = docs[i];
                  final name = (d.data()['name'] ?? 'Shopping List').toString();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: const Icon(Icons.add_rounded),
                    onTap: _isLoading ? null : () => _executeAdd(existingListId: d.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _prettyDay(String dayKey) {
    if (dayKey == 'Today') return 'Today';
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return dayKey;
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${w[dt.weekday - 1]} ${dt.day}';
  }
}

// -----------------------------------------------------------------------------
// UI bits
// -----------------------------------------------------------------------------

class _PeopleStepperRow extends StatelessWidget {
  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _PeopleStepperRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F5F4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
            _IconBtn(
              icon: Icons.remove_rounded,
              enabled: enabled && value > 0,
              onTap: () => onChanged(value - 1),
            ),
            const SizedBox(width: 10),
            Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(width: 10),
            _IconBtn(
              icon: Icons.add_rounded,
              enabled: enabled && value < 20,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchPill extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _BatchPill({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(1, 20);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withOpacity(0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconBtn(
              icon: Icons.remove_rounded,
              enabled: enabled && v > 1,
              onTap: () => onChanged((v - 1).clamp(1, 20)),
            ),
            const SizedBox(width: 10),
            Text('x$v', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            const SizedBox(width: 10),
            _IconBtn(
              icon: Icons.add_rounded,
              enabled: enabled && v < 20,
              onTap: () => onChanged((v + 1).clamp(1, 20)),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: enabled ? Colors.black.withOpacity(0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? Colors.black.withOpacity(0.75) : Colors.black.withOpacity(0.25),
        ),
      ),
    );
  }
}

// lib/meal_plan/widgets/meal_plan_shopping_sheet.dart

import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../lists/shopping_repo.dart';
// ✅ FIXED: Using the file name from your screenshot
import '../../lists/shopping_list_detail_screen.dart'; 

import '../../recipes/family_profile_repository.dart';
import '../../recipes/recipe_repository.dart';
import '../../recipes/serving_engine.dart';
import '../../utils/text.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_slots.dart';
import '../core/meal_plan_repository.dart';
import '../../app/sub_header_bar.dart';
import '../../recipes/family_profile.dart';
import '../../recipes/recipe_detail_screen.dart';

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
  // ---------------------------------------------------------------------------
  // Debug
  // ---------------------------------------------------------------------------

  static const bool _debugShop = true;

  void _dlog(String msg) {
    if (!_debugShop) return;
    // ignore: avoid_print
    print('SHOP DEBUG → $msg');
  }

  bool _isKeyInAllowedHorizon(String key) {
    final parts = key.split('|');
    if (parts.isEmpty) return false;
    final dayKey = parts.first.trim();
    return _allowedDayKeys.contains(dayKey);
  }

  // Step 0 = horizon, Step 1 = select meals, Step 2 = select list
  int _step = 0;
  final PageController _pageCtrl = PageController();

  // Plan selection
  final Set<String> _selectedKeys = {};
  final Map<String, int> _slotToRecipeId = {};
  late Map<int, String> _titles;

  // Local mutable plan data
  late Map<String, dynamic> _currentPlanData;

  // Track fetched days
  final Set<String> _fetchedDayKeys = {};
  bool _isFetchingMoreData = false;

  // Day grouping map (dayKey -> keys in that day)
  final Map<String, List<String>> _keysByDay = {};
  final List<String> _allDayKeysSorted = [];

  // Horizon config
  int _daysAhead = 5; // default
  late DateTime _anchorDate; // Start date for horizon
  late Set<String> _allowedDayKeys; // within horizon
  List<String> _horizonDayKeysSorted = [];

  // Track which day page we are reviewing in Step 1
  int _reviewPageIndex = 0;

  static const bool _backfillPastPlannedDays = true;

  // Family profile repo
  final FamilyProfileRepository _familyRepo = FamilyProfileRepository();
  int _profileAdults = 2;
  int _profileKids = 1;
  StreamSubscription<FamilyProfile>? _familySub;

  final Map<String, int> _adultsByKey = {};
  final Map<String, int> _kidsByKey = {};
  final Set<String> _touchedPeopleKeys = {};
  final Map<String, int> _batchByKey = {};

  final Map<int, bool> _isItemModeById = {};
  final Map<int, int> _baseServingsById = {};
  final Map<int, int?> _itemsPerPersonById = {};
  final Map<int, String> _itemLabelById = {};
  final Map<int, int> _itemsMadeById = {};
  final Map<int, Map<String, dynamic>> _recipeMapById = {};

  final _listNameCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titles = Map.from(widget.knownTitles);

    // Deep copy planData to allow safe merging
    _currentPlanData = Map<String, dynamic>.from(widget.planData);
    if (_currentPlanData['days'] is Map) {
      _currentPlanData['days'] =
          Map<String, dynamic>.from(_currentPlanData['days']);
    } else {
      _currentPlanData['days'] = <String, dynamic>{};
    }

    // Mark passed data as fetched so we don't re-fetch it unnecessarily
    final type = (_currentPlanData['type'] ?? 'week').toString();
    if (type == 'week') {
      final days = _currentPlanData['days'] as Map;
      _fetchedDayKeys.addAll(days.keys.map((k) => k.toString()));
    } else if (type == 'day') {
      String? key;
      if (_currentPlanData.containsKey('dateKey')) {
        key = _currentPlanData['dateKey'];
      } else if (_currentPlanData.containsKey('dayKey')) {
        key = _currentPlanData['dayKey'];
      } else {
        key = MealPlanKeys.todayKey();
      }
      _fetchedDayKeys.add(key!);
    }

    // Anchor Date is strictly TODAY.
    _anchorDate = _dateOnly(DateTime.now());

    _dlog("Anchor Date set to: $_anchorDate");

    _parsePlan();
    _wireFamilyProfile();
    _primeRecipeMetaCache();

    _buildDayIndex();
    _applyHorizon(daysAhead: _daysAhead, jumpToReview: false);
  }

  @override
  void dispose() {
    _familySub?.cancel();
    _pageCtrl.dispose();
    _listNameCtrl.dispose();
    super.dispose();
  }

  void _wireFamilyProfile() {
    _familySub?.cancel();

    _familySub = _familyRepo.watchFamilyProfile().listen((family) {
      final adultCount =
          family.adults.where((p) => p.name.trim().isNotEmpty).length;

      final kidCount =
          family.children.where((p) => p.name.trim().isNotEmpty).length;

      final nextAdults = adultCount > 0 ? adultCount : 1;
      final nextKids = kidCount;

      if (!mounted) return;

      setState(() {
        _profileAdults = nextAdults;
        _profileKids = nextKids;

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
    }, onError: (e) {
      _dlog('familyProfile watch error=$e');
      if (!mounted) return;
      setState(() {
        _profileAdults = 2;
        _profileKids = 1;
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Plan parsing
  // ---------------------------------------------------------------------------

  void _parsePlan() {
    _slotToRecipeId.clear();

    bool isRecipeEntry(dynamic entry) {
      if (entry is! Map) return false;
      return entry['kind'] == 'recipe' ||
          entry.containsKey('recipeId') ||
          entry.containsKey('id');
    }

    int? recipeIdFrom(dynamic entry) {
      if (entry is! Map) return null;
      final rawId = entry['recipeId'] ?? entry['id'];
      if (rawId == null) return null;
      return int.tryParse(rawId.toString());
    }

    void processDay(String dayKey, Map dayData) {
      // Handle nested 'slots' from Firestore documents
      Map targetMap = dayData;
      if (dayData.containsKey('slots') && dayData['slots'] is Map) {
        targetMap = dayData['slots'];
      }

      final slots = targetMap.keys
          .map((k) => k.toString())
          .where((slot) => isRecipeEntry(targetMap[slot]))
          .toList();

      slots.sort((a, b) {
        final pa = _slotScore(a);
        final pb = _slotScore(b);
        if (pa != pb) return pa.compareTo(pb);
        return a.compareTo(b);
      });

      for (final slot in slots) {
        final entry = targetMap[slot];
        final rid = recipeIdFrom(entry);
        if (rid == null) continue;

        final key = '$dayKey|$slot';
        _slotToRecipeId[key] = rid;

        // Auto-select if new
        if (!_selectedKeys.contains(key)) {
          _selectedKeys.add(key);
        }

        _titles.putIfAbsent(rid, () => 'Recipe #$rid');
        _batchByKey[key] = _batchByKey[key] ?? 1;
      }
    }

    // 1. Process 'days' map
    final days = _currentPlanData['days'];
    if (days is Map) {
      final keys = days.keys.map((k) => k.toString()).toList()..sort();
      for (final k in keys) {
        final d = days[k];
        if (d is Map) processDay(k, Map.from(d));
      }
    }

    // 2. Process 'day' map
    final singleDay = _currentPlanData['day'];
    if (singleDay is Map) {
      String dayKey = MealPlanKeys.todayKey();
      if (_currentPlanData.containsKey('dateKey')) {
        dayKey = _currentPlanData['dateKey'].toString();
      } else if (_currentPlanData.containsKey('dayKey')) {
        dayKey = _currentPlanData['dayKey'].toString();
      }

      bool alreadyProcessed = false;
      for (var existingKey in _slotToRecipeId.keys) {
        if (existingKey.startsWith('$dayKey|')) {
          alreadyProcessed = true;
          break;
        }
      }

      if (!alreadyProcessed) {
        processDay(dayKey, Map.from(singleDay));
      }
    }

    _dlog('parsePlan slotToRecipeId count=${_slotToRecipeId.length}');
  }

  void _buildDayIndex() {
    _keysByDay.clear();

    for (final key in _slotToRecipeId.keys) {
      final parts = key.split('|');
      if (parts.isEmpty) continue;
      final dayKey = parts.first.trim();
      if (dayKey.isEmpty) continue;
      _keysByDay.putIfAbsent(dayKey, () => []).add(key);
    }

    for (final dayKey in _keysByDay.keys) {
      _keysByDay[dayKey]!.sort((a, b) {
        final sa = a.split('|').last;
        final sb = b.split('|').last;
        final pa = _slotScore(sa);
        final pb = _slotScore(sb);
        if (pa != pb) return pa.compareTo(pb);
        return sa.compareTo(sb);
      });
    }

    _allDayKeysSorted
      ..clear()
      ..addAll(_keysByDay.keys);

    _allDayKeysSorted.sort((a, b) {
      final da = MealPlanKeys.parseDayKey(a);
      final db = MealPlanKeys.parseDayKey(b);
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.compareTo(b);
    });
  }

  // ---------------------------------------------------------------------------
  // Horizon selection
  // ---------------------------------------------------------------------------

  void _applyHorizon({required int daysAhead, required bool jumpToReview}) {
    _checkAndFetchMissingDays(daysAhead);

    final nextDaysAhead = daysAhead.clamp(1, 14);
    final start = _anchorDate;
    final end = _anchorDate.add(Duration(days: nextDaysAhead - 1));

    _dlog('applyHorizon daysAhead=$nextDaysAhead start=$start end=$end');

    final allowed = <String>{};
    final futureAllowed = <String>[];
    final pastEligible = <String>[];

    for (final dayKey in _allDayKeysSorted) {
      final dt = MealPlanKeys.parseDayKey(dayKey);
      if (dt == null) {
        allowed.add(dayKey);
        continue;
      }

      final d = _dateOnly(dt.toLocal());
      if (!d.isBefore(start) && !d.isAfter(end)) {
        allowed.add(dayKey);
        futureAllowed.add(dayKey);
      } else if (d.isBefore(start)) {
        pastEligible.add(dayKey);
      }
    }

    // Guard against empty list to prevent crash
    if (_backfillPastPlannedDays && _allDayKeysSorted.isNotEmpty) {
      final targetPlannedDays =
          nextDaysAhead.clamp(1, _allDayKeysSorted.length);
      final already = allowed.length;
      final need = (targetPlannedDays - already).clamp(0, 999);

      if (need > 0 && pastEligible.isNotEmpty) {
        final take = need.clamp(0, pastEligible.length);
        final backfill = pastEligible.reversed.take(take).toList().reversed;
        for (final d in backfill) {
          allowed.add(d);
        }
      }
    }

    final horizonDays = _allDayKeysSorted.where(allowed.contains).toList();

    final nextSelected = <String>{};
    for (final dayKey in horizonDays) {
      nextSelected.addAll(_keysByDay[dayKey] ?? const <String>[]);
    }

    setState(() {
      _daysAhead = nextDaysAhead;
      _allowedDayKeys = allowed;
      _horizonDayKeysSorted = horizonDays;
      _reviewPageIndex = 0;

      _selectedKeys.addAll(nextSelected);
      _selectedKeys.retainWhere((k) => allowed.contains(k.split('|').first));
    });

    if (jumpToReview) _goToStep1Review();
  }

  // ---------------------------------------------------------------------------
  // Fetching Logic
  // ---------------------------------------------------------------------------

  String _formatDateKey(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  Future<void> _checkAndFetchMissingDays(int daysAhead) async {
    final requiredKeys = <String>[];
    for (int i = 0; i < daysAhead; i++) {
      requiredKeys.add(_formatDateKey(_anchorDate.add(Duration(days: i))));
    }

    final missing =
        requiredKeys.where((k) => !_fetchedDayKeys.contains(k)).toList();
    if (missing.isEmpty) return;

    if (_isFetchingMoreData) return;

    setState(() => _isFetchingMoreData = true);

    try {
      final startDate = _anchorDate;
      final endDate = _anchorDate.add(Duration(days: daysAhead));

      _dlog("Batch fetching from $_anchorDate to $endDate");

      final newDaysData = await _fetchPlanBatch(startDate, endDate);

      if (newDaysData.isNotEmpty) {
        if (_currentPlanData['days'] is! Map) {
          _currentPlanData['days'] = <String, dynamic>{};
        }

        final currentDaysMap = _currentPlanData['days'] as Map;

        newDaysData.forEach((key, val) {
          currentDaysMap[key] = val;
          _fetchedDayKeys.add(key);
        });

        _parsePlan();
        _buildDayIndex();

        await _primeRecipeMetaCache();

        if (mounted) {
          _applyHorizon(daysAhead: daysAhead, jumpToReview: false);
        }
      } else {
        _dlog("Fetched data was empty.");
      }
    } catch (e) {
      _dlog('Error fetching more meal plans: $e');
    } finally {
      if (mounted) setState(() => _isFetchingMoreData = false);
    }
  }

  Future<Map<String, dynamic>> _fetchPlanBatch(
      DateTime start, DateTime end) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};

    final out = <String, dynamic>{};
    final repo = MealPlanRepository(FirebaseFirestore.instance);

    final startKey = _formatDateKey(start);
    final endKey = _formatDateKey(end);

    try {
      final programId = await repo.getActiveProgramId(uid: uid);
      _dlog("Active Program ID: $programId");

      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];

      // 1. Legacy Days
      // ignore: deprecated_member_use
      futures.add(repo.programDaysColLegacy(uid: uid)
          .where('dateKey', isGreaterThanOrEqualTo: startKey)
          .where('dateKey', isLessThanOrEqualTo: endKey)
          .get());

      // 2. Active Program Days
      if (programId != null) {
        futures.add(repo
            .programDaysColForProgram(uid: uid, programId: programId)
            .where('dateKey', isGreaterThanOrEqualTo: startKey)
            .where('dateKey', isLessThanOrEqualTo: endKey)
            .get());
      } else {
        futures.add(Future.value(null));
      }

      // 3. Ad-hoc Days
      futures.add(repo.adhocDaysCol(uid: uid)
          .where('dateKey', isGreaterThanOrEqualTo: startKey)
          .where('dateKey', isLessThanOrEqualTo: endKey)
          .get());

      final results = await Future.wait(futures);

      void mergeSnapshot(QuerySnapshot<Map<String, dynamic>>? snap) {
        if (snap == null) return;
        for (final doc in snap.docs) {
          final data = doc.data();
          if (data['slots'] is Map && (data['slots'] as Map).isNotEmpty) {
            final key = data['dayKey'] ?? data['dateKey'] ?? doc.id;
            out[key.toString()] = data;
          }
        }
      }

      // A. Legacy
      // ignore: unnecessary_cast
      mergeSnapshot(results[0] as QuerySnapshot<Map<String, dynamic>>?);

      // B. Program
      if (results[1] != null) {
        // ignore: unnecessary_cast
        mergeSnapshot(results[1] as QuerySnapshot<Map<String, dynamic>>?);
      }

      // C. Ad-hoc
      // ignore: unnecessary_cast
      mergeSnapshot(results.last as QuerySnapshot<Map<String, dynamic>>?);
    } catch (e) {
      _dlog("Batch fetch error: $e");
    }

    return out;
  }

  // ... (All Helpers unchanged)
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
          _recipeMapById[id] = recipe;
        });

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
      } catch (e) {
        _dlog('primeRecipeMetaCache failed for id=$id err=$e');
        if (!mounted) return;
        setState(() {
          _baseServingsById[id] = 1;
          _isItemModeById[id] = false;
        });
      }
    }
  }

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
      return line.isNotEmpty ? line : 'You need the equivalent of ~0 adult portions';
    } catch (_) {
      return 'You need the equivalent of ~0 adult portions';
    }
  }

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

    final scale =
        _recommendedScaleForShared(recipe: recipe, adults: adults, kids: kids);
    if ((scale - 1.0).abs() < 0.001) return needs;

    final label = (scale - 0.5).abs() < 0.001
        ? 'Half batch'
        : '${_fmtMultiplier(scale)} batch';
    return '$needs • Using $label';
  }

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

    final mX = RegExp(r'^\s*([0-9]+(?:\.\d+)?)(\s*x\s*)$',
            caseSensitive: false)
        .firstMatch(a);
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
      return a
          .replaceFirst(
              mNum.group(1)!, _fmtSmart(double.parse(mNum.group(1)!) * mult))
          .trim();
    }

    return a;
  }

  List<ShoppingIngredient> _ingredientsToShoppingIngredientsExact(
    Map<String, dynamic>? recipe,
    double scale,
  ) {
    if (recipe == null) return const [];

    final ingredientsFlat = (recipe['ingredients_flat'] is List)
        ? (recipe['ingredients_flat'] as List)
        : const [];
    if (ingredientsFlat.isEmpty) return const [];

    final out = <ShoppingIngredient>[];

    for (final row in ingredientsFlat) {
      if (row is! Map) continue;

      final type = (row['type'] ?? '').toString().toLowerCase();
      if (type == 'group' || type == 'header') continue;

      final name = (row['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final notes = stripHtml((row['notes'] ?? '').toString()).trim();

      final metricAmount =
          _scaledAmount((row['amount'] ?? '').toString(), scale).trim();
      final metricUnit = (row['unit'] ?? '').toString().trim();

      String usAmount = '';
      String usUnit = '';
      if (_rowHasConverted2(row)) {
        final c2 = _converted2(row);
        usAmount =
            _scaledAmount((c2?['amount'] ?? '').toString(), scale).trim();
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

  Future<void> _executeAdd({String? existingListId, String? newListName}) async {
    setState(() => _isLoading = true);

    try {
      String listId = existingListId ?? '';
      // We'll use this name for navigation if it's a new list
      String finalListName = newListName ?? 'Shopping List'; 

      if (newListName != null && newListName.trim().isNotEmpty) {
        final ref = await ShoppingRepo.instance.createList(newListName.trim());
        listId = ref.id;
        finalListName = newListName.trim();
      }
      
      if (listId.isEmpty) throw Exception('No list selected');

      // If using an existing list, we try to grab the name from our titles map or repo
      // But since we don't have it easily here, we will pass a generic fallback 
      // or the known new name.
      
      int addedRecipeCount = 0;

      _dlog('executeAdd selectedKeys=${_selectedKeys.length}');

      for (final key in _selectedKeys) {
        final rid = _slotToRecipeId[key];
        if (rid == null) continue;

        final raw = await RecipeRepository.getRecipeById(rid);

        final recipe = (raw['recipe'] is Map)
            ? Map<String, dynamic>.from(raw['recipe'] as Map)
            : Map<String, dynamic>.from(raw);

        _recipeMapById[rid] = recipe;

        final ingredientScale = _ingredientScaleForKey(key, rid);

        final ingredients =
            _ingredientsToShoppingIngredientsExact(recipe, ingredientScale);
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
      
      // ✅ FIX: Added listName argument
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ShoppingListDetailScreen(
            listId: listId,
            listName: finalListName, // Passing the name we know or a fallback
          ),
        ),
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $addedRecipeCount recipes to shopping list')),
      );
    } catch (e) {
      _dlog('executeAdd error=$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToStep1Review() {
    setState(() => _step = 1);
    _pageCtrl.animateToPage(
      1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _goToStep2List() {
    if (_selectedKeys.isEmpty) return;
    setState(() => _step = 2);
    _pageCtrl.animateToPage(
      2,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _goBack() {
    final next = (_step - 1).clamp(0, 2);
    setState(() => _step = next);
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomBar = SafeArea(
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
          child: _buildBottomButton(),
        ),
      ),
    );

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
                    _step == 0
                        ? 'Choose days'
                        : _step == 1
                            ? 'Select meals'
                            : 'Select list',
                    style: _S.meta(context),
                  ),
                ),
                // ✅ Removed "Back" button per request
              ],
            ),
          ),
          if (_isLoading || _isFetchingMoreData) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep0Horizon(),
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

  Widget _buildBottomButton() {
    if (_step == 0) {
      final plannedCount = _horizonDayKeysSorted.length;
      final hasMeals = _selectedKeys.isNotEmpty;
      return ElevatedButton(
        onPressed: (!hasMeals || _isLoading) ? null : _goToStep1Review,
        style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
        child: Text(
          plannedCount == 0 ? 'No planned meals' : 'Review meals',
        ),
      );
    }

    if (_step == 1) {
      return ElevatedButton(
        onPressed: (_selectedKeys.isEmpty || _isLoading) ? null : _goToStep2List,
        style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
        child: Text('Add ${_selectedKeys.length} recipes to shopping list'),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildStep0Horizon() {
    final plannedDays = _horizonDayKeysSorted;
    final preview = _horizonPreviewText();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
      children: [
        Text(
          'Shop for the next…',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Colors.black.withOpacity(0.86),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _chip(
              label: '3 days',
              selected: _daysAhead == 3,
              onTap: () => _applyHorizon(daysAhead: 3, jumpToReview: false),
            ),
            _chip(
              label: '5 days',
              selected: _daysAhead == 5,
              onTap: () => _applyHorizon(daysAhead: 5, jumpToReview: false),
            ),
            _chip(
              label: '7 days',
              selected: _daysAhead == 7,
              onTap: () => _applyHorizon(daysAhead: 7, jumpToReview: false),
            ),
            _chip(
              label: 'Custom',
              selected: !{3, 5, 7}.contains(_daysAhead),
              onTap: () => _showCustomDaysPicker(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_basket_outlined, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preview,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withOpacity(0.75),
                  ),
                ),
              ),
              if (_isFetchingMoreData)
                const SizedBox(
                  width: 16, height: 16, 
                  child: CircularProgressIndicator(strokeWidth: 2)
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Divider(height: 1, color: Colors.black.withOpacity(0.08)),
        const SizedBox(height: 14),
        Text(
          'Planned days in this window',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.black.withOpacity(0.78),
          ),
        ),
        const SizedBox(height: 10),
        if (plannedDays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _isFetchingMoreData 
                ? 'Checking plan...'
                : 'No meals planned in the next $_daysAhead days.',
              style: TextStyle(color: Colors.black.withOpacity(0.6)),
            ),
          )
        else
          ...plannedDays.map((dayKey) {
            final dt = MealPlanKeys.parseDayKey(dayKey);
            final title = dt == null ? dayKey : _prettyDayWithDate(dt);
            final mealCount = (_keysByDay[dayKey] ?? const <String>[]).length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      '$mealCount meal${mealCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withOpacity(0.60),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  String _horizonPreviewText() {
    final start = _anchorDate;
    final end = _anchorDate.add(Duration(days: _daysAhead - 1));

    final rangeText = '${_prettyShortDay(start)} → ${_prettyShortDay(end)}';

    final plannedDays = _horizonDayKeysSorted.length;
    final meals = _selectedKeys.length;

    if (plannedDays == 0) {
      return 'Next $_daysAhead days ($rangeText) • No planned meals';
    }

    return 'Next $_daysAhead days ($rangeText) • $plannedDays planned day${plannedDays == 1 ? '' : 's'} • $meals meal${meals == 1 ? '' : 's'}';
  }

  Future<void> _showCustomDaysPicker() async {
    final next = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        int v = _daysAhead.clamp(1, 14);
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFECF3F4),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Custom window',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'How many days ahead do you want to shop for?',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.62),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (ctx, setInner) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withOpacity(0.08)),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: v <= 1 ? null : () => setInner(() => v -= 1),
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '$v day${v == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: v >= 14 ? null : () => setInner(() => v += 1),
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(v),
                      style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
                      child: const Text('Use this window'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (next == null) return;

    _applyHorizon(daysAhead: next, jumpToReview: false);
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.black.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withOpacity(0.10)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: Colors.black.withOpacity(0.80),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ✅ UPDATED: Step 1 (Day Selector View)
  // ---------------------------------------------------------------------------

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

  Widget _buildStep1SelectMeals() {
    final dayKeys = _horizonDayKeysSorted;

    if (dayKeys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No planned meals in the next $_daysAhead days.',
          style: TextStyle(color: Colors.black.withOpacity(0.6)),
        ),
      );
    }

    final currentDayKey = dayKeys[_reviewPageIndex];

    return Column(
      children: [
        // 1. Navigation Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _reviewPageIndex > 0 
                    ? () => setState(() => _reviewPageIndex--) 
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 28),
              ),
              // Center Date Title
              Text(
                _prettyDay(currentDayKey),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              IconButton(
                onPressed: _reviewPageIndex < dayKeys.length - 1
                    ? () => setState(() => _reviewPageIndex++) 
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 28),
              ),
            ],
          ),
        ),
        
        // 2. Meal List for Current Day
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              ..._buildDayMeals(currentDayKey),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDayMeals(String dayKey) {
    final keysForDay = (_keysByDay[dayKey] ?? const <String>[]).toList();
    if (keysForDay.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Center(
            child: Text(
              'No meals planned for this day.',
              style: TextStyle(color: Colors.black.withOpacity(0.6)),
            ),
          ),
        ),
      ];
    }

    final bySlot = <String, List<String>>{};
    for (final k in keysForDay) {
      final slot = k.split('|').last;
      bySlot.putIfAbsent(slot, () => []).add(k);
    }

    final orderedSlots = bySlot.keys.toList()
      ..sort((a, b) => _slotScore(a).compareTo(_slotScore(b)));

    final out = <Widget>[];
    for (final slot in orderedSlots) {
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text(_slotHeaderLabel(slot), style: _S.header(context)),
        ),
      );
      for (final key in bySlot[slot]!) {
        out.add(_mealCard(key));
      }
    }
    return out;
  }

  Widget _mealCard(String key) {
    if (!_isKeyInAllowedHorizon(key)) return const SizedBox.shrink();

    final rid = _slotToRecipeId[key];
    final title = (rid != null) ? (_titles[rid] ?? 'Recipe') : 'Recipe';

    final selected = _selectedKeys.contains(key);
    final isItem = (rid != null) ? (_isItemModeById[rid] == true) : false;

    final adults = (_adultsByKey[key] ?? _profileAdults).clamp(0, 20);
    final kids = (_kidsByKey[key] ?? _profileKids).clamp(0, 20);

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
                      InkWell(
                        onTap: (rid == null)
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RecipeDetailScreen(id: rid),
                                  ),
                                );
                              },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: _S.cardTitle(context),
                                maxLines: 2,
                              ),
                            ),
                            // ✅ Removed separate icon
                          ],
                        ),
                      ),
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

  // ---------------------------------------------------------------------------
  // Step 2: List picker
  // ---------------------------------------------------------------------------

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
                    hintText: 'e.g. Week shop',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                      borderSide:
                          BorderSide(color: Colors.black.withOpacity(0.22), width: 1.4),
                    ),
                  ),
                  onSubmitted: (_) {
                    final name = _listNameCtrl.text.trim();
                    if (name.isNotEmpty && !_isLoading) {
                      _executeAdd(newListName: name);
                    }
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
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
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

  // ---------------------------------------------------------------------------
  // Misc helpers
  // ---------------------------------------------------------------------------

  String _prettyDay(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return dayKey;
    return _prettyDayWithDate(dt);
  }

  static String _prettyDayWithDate(DateTime dt) {
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${w[dt.weekday - 1]} ${dt.day} ${m[dt.month - 1]}';
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static String _prettyShortDay(DateTime dt) {
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${w[dt.weekday - 1]} ${dt.day}';
  }

  static Widget _pill({
    required String label,
    required VoidCallback? onTap,
    required bool selected,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.black.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withOpacity(0.10)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: onTap == null
                ? Colors.black.withOpacity(0.35)
                : Colors.black.withOpacity(0.80),
          ),
        ),
      ),
    );
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
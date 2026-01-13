// lib/meal_plan/builder/meal_plan_builder_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../recipes/recipe_repository.dart';
import '../core/meal_plan_controller.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';
import '../meal_plan_screen.dart';
import 'meal_plan_builder_service.dart';

import '../../recipes/family_profile_repository.dart';
import '../../recipes/recipe_index_builder.dart';
import '../../utils/text.dart'; // Ensure this exists for stripHtml

/// Controls how this builder is launched
enum MealPlanBuilderEntry { dayOnly, weekOnly, choose, adhocDay }

// ✅ simple audience values
const String kAudienceFamily = 'family';
const String kAudienceKids = 'kids';

class MealPlanBuilderScreen extends StatefulWidget {
  final String weekId;
  final MealPlanBuilderEntry entry;
  final String? initialSelectedDayKey;

  const MealPlanBuilderScreen({
    super.key,
    required this.weekId,
    this.entry = MealPlanBuilderEntry.choose,
    this.initialSelectedDayKey,
  });

  @override
  State<MealPlanBuilderScreen> createState() => _MealPlanBuilderScreenState();
}

class _MealPlanBuilderScreenState extends State<MealPlanBuilderScreen> {
  final TextEditingController _planNameController = TextEditingController();

  // ✅ Programs model inputs
  int _weeks = 2; 
  final Set<int> _weekdays = <int>{}; 
  String _startDayKey = MealPlanKeys.todayKey();

  // Meal structure
  bool _breakfast = true;
  bool _lunch = true;
  bool _dinner = true;
  int _snacksPerDay = 1;

  // ✅ Audience targeting
  String _breakfastAudience = kAudienceFamily;
  String _lunchAudience = kAudienceFamily;
  String _dinnerAudience = kAudienceFamily;
  String _snackAudience = kAudienceKids; 

  // ✅ Allergy Policy
  bool _includeSwaps = true;

  bool _busy = false;

  // -----------------------------
  // ✅ NORMALIZATION HELPERS (Robust Version)
  // -----------------------------
  String _titleOf(Map<String, dynamic> r) =>
      (r['title']?['rendered'] as String?)?.trim().isNotEmpty == true
          ? (r['title']['rendered'] as String)
          : 'Untitled';

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

  // ✅ ROBUST SWAP EXTRACTION (Matches Recipe List)
  String _swapTextOf(Map<String, dynamic> r) {
    // 1. Normalized top-level field
    if (r['ingredient_swaps'] != null) {
      return r['ingredient_swaps'].toString().trim();
    }

    final recipe = r['recipe'];
    if (recipe is Map) {
      // 2. ✅ Check custom_fields (The critical missing link)
      final custom = recipe['custom_fields'];
      if (custom is Map) {
        final val = custom['ingredient_swaps'];
        if (val != null && val.toString().trim().isNotEmpty) {
          return val.toString().trim();
        }
      }

      // 3. Legacy locations
      if (recipe['swap_text'] != null) return recipe['swap_text'].toString().trim();
      if (recipe['swaps'] != null) return recipe['swaps'].toString().trim();
    }
    
    // 4. Meta fallback
    if (r['meta'] is Map) {
      final meta = r['meta'] as Map;
      if (meta['ingredient_swaps'] != null) {
        return meta['ingredient_swaps'].toString().trim();
      }
    }

    return '';
  }

  // Generic term extractor
  List<String> _termsOfField(Map<String, dynamic> r, String field) {
    final v = r[field];
    List<String> raw = [];
    if (v is List) {
      raw = v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    } else if (v is int) {
      raw = [v.toString()];
    } else if (v is String && v.trim().isNotEmpty) {
      raw = [v.trim()];
    }
    return raw;
  }

  List<String> _collectionNamesFromRecipeTags(Map<String, dynamic> r) {
    try {
      final recipe = r['recipe'];
      if (recipe is Map) {
        final tags = recipe['tags'];
        if (tags is Map) {
          final cols = tags['collections'] ?? tags['collection'];
          if (cols is List) {
            final out = <String>[];
            for (final c in cols) {
              if (c is Map) {
                final name = (c['name'] ?? '').toString().trim();
                if (name.isNotEmpty) out.add(name);
              } else if (c is String) {
                final s = c.trim();
                if (s.isNotEmpty) out.add(s);
              }
            }
            if (out.isNotEmpty) return out.toSet().toList()..sort();
          }
        }
      }
    } catch (_) {}
    return const [];
  }

  List<String> _collectionsOf(Map<String, dynamic> r) {
    final fromTags = _collectionNamesFromRecipeTags(r);
    if (fromTags.isNotEmpty) return fromTags;
    return _termsOfField(r, 'wprm_collections');
  }

  List<String> _allergyTagsOf(Map<String, dynamic> r) {
    try {
      final recipe = r['recipe'];
      if (recipe is Map && recipe['tags'] is Map) {
        final tags = recipe['tags'] as Map;
        final a = tags['allergies'];
        if (a is List) {
          final out = <String>[];
          for (final item in a) {
            if (item is Map) {
              final name = (item['name'] ?? '').toString().trim();
              if (name.isNotEmpty) out.add(name);
            }
          }
          if (out.isNotEmpty) return out.toSet().toList()..sort();
        }
      }
    } catch (_) {}
    return _termsOfField(r, 'wprm_allergies');
  }

  // ✅ Normalizer using the robust extractor
 Map<String, dynamic> _normaliseForIndex(Map<String, dynamic> r) {
    final id = r['id'];
    if (id is! int) return const {};

    return <String, dynamic>{
      'id': id,
      'title': _titleOf(r),
      'ingredients': _ingredientsTextOf(r),
      'wprm_course': _termsOfField(r, 'wprm_course'),
      'wprm_collections': _collectionsOf(r),
      'wprm_cuisine': _termsOfField(r, 'wprm_cuisine'),
      'wprm_suitable_for': _termsOfField(r, 'wprm_suitable_for'),
      'wprm_nutrition_tag': _termsOfField(r, 'wprm_nutrition_tag'),
      
      'recipe': r['recipe'],
      'meta': r['meta'],
      
      // ✅ This now carries the correct text to the controller
      'ingredient_swaps': _swapTextOf(r),
      
      'wprm_allergies': _allergyTagsOf(r),
    };
  }

  // -----------------------------
  // Date helpers
  // -----------------------------
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isPastDay(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return true;

    final todayOnly = _dateOnly(DateTime.now());
    final dayOnly = _dateOnly(dt);

    return dayOnly.isBefore(todayOnly);
  }

  String _firstNonPastKey(List<String> keys) {
    for (final k in keys) {
      if (!_isPastDay(k)) return k;
    }
    return keys.isNotEmpty ? keys.last : MealPlanKeys.todayKey();
  }

  int? _weekdayForDayKey(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    return dt?.weekday; 
  }

  void _ensureDefaultWeekdaysSelected() {
    if (_weekdays.isNotEmpty) return;
    final wd = _weekdayForDayKey(_startDayKey);
    if (wd != null && wd >= 1 && wd <= 7) {
      _weekdays.add(wd);
    }
  }

  @override
  void initState() {
    super.initState();

    final weekKeys = MealPlanKeys.weekDayKeys(widget.weekId);

    final initDay = (widget.initialSelectedDayKey ?? '').trim();
    if (initDay.isNotEmpty && !_isPastDay(initDay)) {
      _startDayKey = initDay;
    } else if (weekKeys.isNotEmpty) {
      _startDayKey = _firstNonPastKey(weekKeys);
    }

    _ensureDefaultWeekdaysSelected();

    if (widget.entry == MealPlanBuilderEntry.dayOnly) {
      _weeks = 1;
      final wd = _weekdayForDayKey(_startDayKey) ?? DateTime.now().weekday;
      _weekdays
        ..clear()
        ..add(wd);
    }

    if (widget.entry == MealPlanBuilderEntry.weekOnly) {
      _weeks = 1;
      _weekdays
        ..clear()
        ..addAll([1, 2, 3, 4, 5, 6, 7]);
    }

    if (widget.entry == MealPlanBuilderEntry.adhocDay) {
      _weeks = 1;
      final wd = _weekdayForDayKey(_startDayKey) ?? DateTime.now().weekday;
      _weekdays
        ..clear()
        ..add(wd);
    }
  }

  @override
  void dispose() {
    _planNameController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------
  // CREATE ACTIONS
  // -----------------------------------------------------------------

  Map<String, String> _audiencesPayload() {
    return <String, String>{
      'breakfast': _breakfastAudience,
      'lunch': _lunchAudience,
      'dinner': _dinnerAudience,
      'snack': _snackAudience,
    };
  }

  Future<void> _createAdhocOneOffDay({
    required String dayKey,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _busy = true);

    try {
      final recipes = await RecipeRepository.ensureRecipesLoaded();
      if (recipes.isEmpty) throw Exception('No recipes available.');

      // ✅ FIX: Normalise using new logic
      final normalisedRecipes = <Map<String, dynamic>>[];
      for (final r in recipes) {
        final m = _normaliseForIndex(r);
        if (m.isNotEmpty) normalisedRecipes.add(m);
      }

      final controller = MealPlanController(
        auth: FirebaseAuth.instance,
        repo: MealPlanRepository(FirebaseFirestore.instance),
        profileRepo: FamilyProfileRepository(),
        // ✅ Use normalised index
        recipeIndexById: RecipeIndexBuilder.buildById(normalisedRecipes),
        initialWeekId: widget.weekId,
      );

      controller.setAllergyPolicy(includeSwaps: _includeSwaps);
      controller.start(); 

      final builder = MealPlanBuilderService(controller);

      await builder.buildAdhocDay(
        dateKey: dayKey,
        availableRecipes: recipes,
        includeBreakfast: _breakfast,
        includeLunch: _lunch,
        includeDinner: _dinner,
        snackCount: _snacksPerDay,
        mealAudiences: _audiencesPayload(),
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MealPlanScreen(
            weekId: widget.weekId,
            focusDayKey: dayKey,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Could not create one-off day'),
          content: Text('Something went wrong.\n\n$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createMealPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final weekKeys = MealPlanKeys.weekDayKeys(widget.weekId);
    final safeStartKey = _isPastDay(_startDayKey) ? _firstNonPastKey(weekKeys) : _startDayKey;

    if (widget.entry == MealPlanBuilderEntry.adhocDay) {
      await _createAdhocOneOffDay(dayKey: safeStartKey);
      return;
    }

    final cleanWeekdays = _weekdays.where((e) => e >= 1 && e <= 7).toList()..sort();

    if (cleanWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one day.')),
      );
      return;
    }

    setState(() => _busy = true);

    try {
      final recipes = await RecipeRepository.ensureRecipesLoaded();
      if (recipes.isEmpty) throw Exception('No recipes available.');

      // ✅ FIX: Normalise using new logic
      final normalisedRecipes = <Map<String, dynamic>>[];
      for (final r in recipes) {
        final m = _normaliseForIndex(r);
        if (m.isNotEmpty) normalisedRecipes.add(m);
      }

      final controller = MealPlanController(
        auth: FirebaseAuth.instance,
        repo: MealPlanRepository(FirebaseFirestore.instance),
        profileRepo: FamilyProfileRepository(),
        // ✅ Use normalised index
        recipeIndexById: RecipeIndexBuilder.buildById(normalisedRecipes),
        initialWeekId: widget.weekId,
      );

      controller.setAllergyPolicy(includeSwaps: _includeSwaps);
      controller.start();

      final builder = MealPlanBuilderService(controller);

      await builder.buildAndActivate(
        title: _planNameController.text.trim().isNotEmpty ? _planNameController.text.trim() : 'My Meal Plan',
        availableRecipes: recipes,
        startDayKey: safeStartKey,
        weeks: _weeks,
        weekdays: cleanWeekdays,
        includeBreakfast: _breakfast,
        includeLunch: _lunch,
        includeDinner: _dinner,
        includeSnacks: _snacksPerDay > 0,
        snackCount: _snacksPerDay,
        mealAudiences: _audiencesPayload(),
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MealPlanScreen(
            weekId: widget.weekId,
            focusDayKey: safeStartKey,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Could not create plan'),
          content: Text('Something went wrong.\n\n$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -----------------------------------------------------------------
  // UI helpers
  // -----------------------------------------------------------------
  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      );

  Widget _card({required Widget child}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 10),
                blurRadius: 24,
                color: Color.fromRGBO(0, 0, 0, 0.08),
              )
            ],
          ),
          child: child,
        ),
      );

  String _weekdayLabel(int w) {
    switch (w) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekKeys = MealPlanKeys.weekDayKeys(widget.weekId);

    if (weekKeys.isNotEmpty && _isPastDay(_startDayKey)) {
      final fixed = _firstNonPastKey(weekKeys);
      if (fixed != _startDayKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _startDayKey = fixed);
        });
      }
    }

    final isAdhoc = widget.entry == MealPlanBuilderEntry.adhocDay;

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        title: Text(isAdhoc ? 'One-off day' : 'Build meal plan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 140),
          children: [
            if (!isAdhoc) ...[
              _sectionTitle('PLAN NAME'),
              _card(
                child: TextField(
                  controller: _planNameController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. School nights',
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            _sectionTitle('START DATE'),
            _card(
              child: Column(
                children: weekKeys.map<Widget>((dk) {
                  final disabled = _isPastDay(dk);
                  return _RadioRow(
                    title: MealPlanKeys.formatPretty(dk),
                    selected: _startDayKey == dk,
                    enabled: !disabled,
                    onTap: () {
                      setState(() {
                        _startDayKey = dk;
                        _ensureDefaultWeekdaysSelected();
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            if (!isAdhoc) ...[
              _sectionTitle('DAYS'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose the days you want meals planned (e.g. Mon/Wed/Fri).',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.55),
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(7, (i) {
                        final w = i + 1;
                        final selected = _weekdays.contains(w);
                        return _ChipToggle(
                          label: _weekdayLabel(w),
                          selected: selected,
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _weekdays.remove(w);
                              } else {
                                _weekdays.add(w);
                              }
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tip: most people pick 3–5 days.',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.50),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _sectionTitle('LENGTH'),
              _card(
                child: Row(
                  children: [1, 2, 3, 4].map((n) {
                    final disabled = widget.entry == MealPlanBuilderEntry.dayOnly && n != 1;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: n == 4 ? 0 : 10),
                        child: Opacity(
                          opacity: disabled ? 0.45 : 1.0,
                          child: _SegButton(
                            label: '$n wk',
                            selected: _weeks == n,
                            onTap: disabled ? () {} : () => setState(() => _weeks = n),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            
            _sectionTitle('ALLERGY SETTINGS'),
            _card(
              child: Column(
                children: [
                  _ToggleRow(
                    title: 'Include recipes that need swaps',
                    value: _includeSwaps,
                    onChanged: (v) => setState(() => _includeSwaps = v),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Allows recipes that require ingredient replacements to be safe.',
                      style: TextStyle(
                        fontSize: 12, 
                        color: Colors.black.withOpacity(0.5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            _sectionTitle('MEALS'),
            _card(
              child: Column(
                children: [
                  _ToggleRow(
                    title: 'Breakfast',
                    value: _breakfast,
                    onChanged: (v) => setState(() => _breakfast = v),
                  ),
                  if (_breakfast) ...[
                    const SizedBox(height: 8),
                    _AudienceRow(
                      title: 'For',
                      value: _breakfastAudience,
                      onChanged: (v) => setState(() => _breakfastAudience = v),
                    ),
                  ],
                  const Divider(height: 18),
                  _ToggleRow(
                    title: 'Lunch',
                    value: _lunch,
                    onChanged: (v) => setState(() => _lunch = v),
                  ),
                  if (_lunch) ...[
                    const SizedBox(height: 8),
                    _AudienceRow(
                      title: 'For',
                      value: _lunchAudience,
                      onChanged: (v) => setState(() => _lunchAudience = v),
                    ),
                  ],
                  const Divider(height: 18),
                  _ToggleRow(
                    title: 'Family dinner',
                    value: _dinner,
                    onChanged: (v) => setState(() => _dinner = v),
                  ),
                  if (_dinner) ...[
                    const SizedBox(height: 8),
                    _AudienceRow(
                      title: 'For',
                      value: _dinnerAudience,
                      onChanged: (v) => setState(() => _dinnerAudience = v),
                    ),
                  ],
                ],
              ),
            ),
            _sectionTitle('SNACKS PER DAY'),
            _card(
              child: Row(
                children: [0, 1, 2].map((n) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: n == 2 ? 0 : 10),
                      child: _SegButton(
                        label: '$n',
                        selected: _snacksPerDay == n,
                        onTap: () => setState(() => _snacksPerDay = n),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            if (_snacksPerDay > 0) ...[
              _sectionTitle('SNACKS ARE FOR'),
              _card(
                child: _AudienceRow(
                  title: 'Snacks',
                  value: _snackAudience,
                  onChanged: (v) => setState(() => _snackAudience = v),
                ),
              ),
            ],
            if (widget.entry == MealPlanBuilderEntry.dayOnly && !isAdhoc) ...[
              _sectionTitle('NOTE'),
              _card(
                child: Text(
                  'Day plan mode creates a 1-week program on the selected weekday.',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: const BoxDecoration(color: Color(0xFF044246)),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _createMealPlan,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF32998D),
                shape: const StadiumBorder(),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isAdhoc ? 'CREATE ONE-OFF DAY' : 'CREATE MEAL PLAN',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------- UI ATOMS ---------- */

class _SegButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF044246) : const Color(0xFFF1F5F6),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.35,
            color: selected ? Colors.white : Colors.black.withOpacity(0.65),
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String title;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _RadioRow({
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? Colors.black : Colors.black.withOpacity(0.35);

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? const Color(0xFF32998D) : Colors.black.withOpacity(0.35),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w800, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChipToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF044246) : const Color(0xFFF1F5F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.35,
            color: selected ? Colors.white : Colors.black.withOpacity(0.65),
          ),
        ),
      ),
    );
  }
}

class _AudienceRow extends StatelessWidget {
  final String title;
  final String value;
  final ValueChanged<String> onChanged;

  const _AudienceRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.black.withOpacity(0.7),
            ),
          ),
        ),
        _AudienceChip(
          label: 'Family',
          selected: value == kAudienceFamily,
          onTap: () => onChanged(kAudienceFamily),
        ),
        const SizedBox(width: 8),
        _AudienceChip(
          label: 'Kids',
          selected: value == kAudienceKids,
          onTap: () => onChanged(kAudienceKids),
        ),
      ],
    );
  }
}

class _AudienceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AudienceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF044246) : const Color(0xFFF1F5F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.3,
            color: selected ? Colors.white : Colors.black.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}
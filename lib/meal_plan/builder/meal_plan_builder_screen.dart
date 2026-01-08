// lib/meal_plan/builder/meal_plan_builder_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';
import '../core/meal_plan_controller.dart';
import '../meal_plan_screen.dart';
import '../services/meal_plan_manager.dart'; // ✅ Added Manager
import '../../recipes/recipe_repository.dart';

import 'meal_plan_builder_service.dart';

enum _HorizonUI { day, week }

/// Controls how this builder is launched
enum MealPlanBuilderEntry { dayOnly, weekOnly, choose }

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

  _HorizonUI _horizon = _HorizonUI.week;

  bool _breakfast = true;
  bool _lunch = true;
  bool _dinner = true;
  int _snacksPerDay = 1;

  String _selectedDayKey = MealPlanKeys.todayKey();
  bool _busy = false;

  // -----------------------------
  // ✅ Recurring UI state
  // -----------------------------
  bool _makeRecurring = false;

  // Day plan: weekdays 1..7 (Mon..Sun)
  final Set<int> _recurringWeekdays = <int>{};

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

  @override
  void initState() {
    super.initState();

    final weekKeys = MealPlanKeys.weekDayKeys(widget.weekId);

    final initDay = (widget.initialSelectedDayKey ?? '').trim();
    if (initDay.isNotEmpty && !_isPastDay(initDay)) {
      _selectedDayKey = initDay;
    } else if (weekKeys.isNotEmpty) {
      _selectedDayKey = _firstNonPastKey(weekKeys);
    }

    if (widget.entry == MealPlanBuilderEntry.dayOnly) {
      _horizon = _HorizonUI.day;
    } else if (widget.entry == MealPlanBuilderEntry.weekOnly) {
      _horizon = _HorizonUI.week;
    }
  }

  @override
  void dispose() {
    _planNameController.dispose();
    super.dispose();
  }

  int? _weekdayForDayKey(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return null;
    return dt.weekday;
  }

  void _ensureDefaultWeekdaySelected() {
    if (_recurringWeekdays.isNotEmpty) return;
    final wd = _weekdayForDayKey(_selectedDayKey);
    if (wd != null && wd >= 1 && wd <= 7) {
      _recurringWeekdays.add(wd);
    }
  }

  // -----------------------------------------------------------------
  // ✅ CONFLICT CHECK & AUTO-DISABLE LOGIC
  // -----------------------------------------------------------------

  Future<bool> _checkRecurringConflicts(String uid, bool isDayPlan) async {
    final repo = MealPlanRepository(FirebaseFirestore.instance);
    final manager = MealPlanManager(
        auth: FirebaseAuth.instance,
        firestore: FirebaseFirestore.instance); 

    final conflicts = <Map<String, dynamic>>[];
    String? conflictMessage;

    // 1. Fetch ALL existing Recurring Day Plans
    final existingDayPlans = await repo.listRecurringDayPlans(uid: uid);

    if (isDayPlan) {
      // --- CREATING DAY PLAN ---
      // Conflict if: New days overlap with existing days
      for (final plan in existingDayPlans) {
        final planDays = List<int>.from(plan['recurringWeekdays'] ?? []);
        final overlaps = planDays.any((d) => _recurringWeekdays.contains(d));
        if (overlaps) {
          conflicts.add(plan);
        }
      }

      if (conflicts.isNotEmpty) {
         final names = conflicts.map((e) => e['title'] ?? 'Untitled').join('\n• ');
         conflictMessage = 'You already have recurring plans set for these days:\n\n• $names\n\nSaving this will replace them.';
      }

    } else {
      // --- CREATING WEEK PLAN ---
      // Conflict if: 
      // 1. Any Recurring Week Plan exists
      // 2. ANY Recurring Day Plan exists (Week Plan overrides everything)
      
      // Check existing Week Plan
      final activeWeekId = await repo.getActiveRecurringWeekPlanId(uid: uid);
      if (activeWeekId != null) {
        final oldPlan = await repo.getSavedPlan(uid: uid, planId: activeWeekId);
        if (oldPlan != null) {
           conflicts.add({
             'id': activeWeekId, 
             'title': oldPlan['title'], 
             'planType': 'week' // Explicit type for disabler
           });
        }
      }

      // Check ALL Day Plans (They all conflict with a full week plan)
      if (existingDayPlans.isNotEmpty) {
        conflicts.addAll(existingDayPlans);
      }

      if (conflicts.isNotEmpty) {
        final names = conflicts.map((e) => e['title'] ?? 'Untitled').toSet().join('\n• ');
        conflictMessage = 'Setting this Recurring Week Plan will stop and replace these existing plans:\n\n• $names';
      }
    }

    // -------------------------------------
    // EXECUTE WARNING & DISABLE
    // -------------------------------------
    if (conflicts.isNotEmpty && conflictMessage != null) {
      final confirm = await _showConflictDialog(
        title: 'Replace existing plans?',
        content: conflictMessage!,
      );

      if (confirm) {
        // ✅ AUTO-DISABLE THE OLD PLANS
        for (final p in conflicts) {
          final pId = p['id'];
          // Determine type safely (day list returns data, week check we built manually)
          String pType = (p['planType'] ?? p['type'] ?? 'day').toString().toLowerCase();
          
          // Safety fallback: if it has 'recurringWeekdays', it's a day plan
          if (p['recurringWeekdays'] != null) pType = 'day';

          // ✅ If we're creating a WEEK recurring plan in the future,
// keep existing recurring plans active until the new start date.
final stopFrom = isDayPlan
    ? DateTime.now()
    : (MealPlanKeys.parseDayKey(_selectedDayKey) ?? DateTime.now());

await manager.setSavedPlanRecurring(
  planId: pId,
  planType: pType,
  enabled: false,
  stopFromDate: stopFrom,
);
        }
      }
      return confirm;
    }

    return true; // No conflict, proceed
  }

  Future<bool> _showConflictDialog({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF32998D),
            ),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // -----------------------------------------------------------------
  // CREATE ACTION
  // -----------------------------------------------------------------

  Future<void> _createMealPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Validate inputs locally first
    final isDayPlan = _horizon == _HorizonUI.day;
    if (_makeRecurring && isDayPlan) {
      final clean = _recurringWeekdays
          .where((e) => e >= 1 && e <= 7)
          .toList()
        ..sort();
      if (clean.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one recurring day.')),
        );
        return;
      }
    }

    // 2. Check conflicts (Pre-flight)
    if (_makeRecurring) {
      final proceed = await _checkRecurringConflicts(user.uid, isDayPlan);
      if (!proceed) return; // User cancelled
    }

    // 3. Proceed with creation
    setState(() => _busy = true);

    try {
      final recipes = await RecipeRepository.ensureRecipesLoaded();
      if (recipes.isEmpty) {
        throw Exception('No recipes available.');
      }

      final controller = MealPlanController(
        auth: FirebaseAuth.instance,
        repo: MealPlanRepository(FirebaseFirestore.instance),
        initialWeekId: widget.weekId,
      );

      final builder = MealPlanBuilderService(controller);

      final weekKeys = MealPlanKeys.weekDayKeys(widget.weekId);
      final safeDayKey = _isPastDay(_selectedDayKey)
          ? _firstNonPastKey(weekKeys)
          : _selectedDayKey;

      await builder.buildAndActivate(
        title: _planNameController.text.trim().isNotEmpty
            ? _planNameController.text.trim()
            : (isDayPlan ? 'My Day Plan' : 'My Week Plan'),
        availableRecipes: recipes,
        isDayPlan: isDayPlan,
        includeBreakfast: _breakfast,
        includeLunch: _lunch,
        includeDinner: _dinner,
        includeSnacks: _snacksPerDay > 0,
        snackCount: _snacksPerDay,
        targetDayKey: isDayPlan ? safeDayKey : null,
        weekPlanStartDayKey: isDayPlan ? null : safeDayKey,

        // ✅ recurring
        makeRecurring: _makeRecurring,
        recurringWeekdays: isDayPlan
            ? (_recurringWeekdays.toList()..sort())
            : null,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MealPlanScreen(
            weekId: widget.weekId,
            focusDayKey: isDayPlan ? safeDayKey : null,
            initialViewMode: MealPlanViewMode.week,
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
    final canChooseHorizon = widget.entry == MealPlanBuilderEntry.choose;
    final isDayPlan = _horizon == _HorizonUI.day;

    // If the current selection becomes invalid, correct it.
    if (weekKeys.isNotEmpty && _isPastDay(_selectedDayKey)) {
      final fixed = _firstNonPastKey(weekKeys);
      if (fixed != _selectedDayKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedDayKey = fixed);
        });
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        title: const Text('Build meal plan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _sectionTitle('PLAN NAME'),
            _card(
              child: TextField(
                controller: _planNameController,
                decoration: const InputDecoration(
                  hintText: 'e.g. My Week Plan',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),

            if (canChooseHorizon) ...[
              _sectionTitle('PLAN TYPE'),
              _card(
                child: Row(
                  children: [
                    Expanded(
                      child: _SegButton(
                        label: 'Day plan',
                        selected: _horizon == _HorizonUI.day,
                        onTap: () {
                          setState(() {
                            _horizon = _HorizonUI.day;
                            if (_makeRecurring) _ensureDefaultWeekdaySelected();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SegButton(
                        label: 'Week plan',
                        selected: _horizon == _HorizonUI.week,
                        onTap: () => setState(() => _horizon = _HorizonUI.week),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            _sectionTitle(isDayPlan ? 'SELECT DAY' : 'START DAY'),
            _card(
              child: Column(
                children: weekKeys.map((dk) {
                  final disabled = _isPastDay(dk);
                  return _RadioRow(
                    title: MealPlanKeys.formatPretty(dk),
                    selected: _selectedDayKey == dk,
                    enabled: !disabled,
                    onTap: () {
                      setState(() {
                        _selectedDayKey = dk;
                        if (_makeRecurring && isDayPlan) {
                          _ensureDefaultWeekdaySelected();
                        }
                      });
                    },
                  );
                }).toList(),
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
                  const Divider(height: 18),
                  _ToggleRow(
                    title: 'Lunch',
                    value: _lunch,
                    onChanged: (v) => setState(() => _lunch = v),
                  ),
                  const Divider(height: 18),
                  _ToggleRow(
                    title: 'Family dinner',
                    value: _dinner,
                    onChanged: (v) => setState(() => _dinner = v),
                  ),
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

            // -----------------------------
            // ✅ RECURRING
            // -----------------------------
            _sectionTitle('RECURRING'),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ToggleRow(
                    title: isDayPlan
                        ? 'Make this day plan recurring'
                        : 'Make this week plan recurring',
                    value: _makeRecurring,
                    onChanged: (v) {
                      setState(() {
                        _makeRecurring = v;
                        if (v && isDayPlan) {
                          _ensureDefaultWeekdaySelected();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isDayPlan
                        ? 'If enabled, this plan can automatically apply on selected weekdays.'
                        : 'If enabled, this week plan becomes your default template for future weeks.',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.55),
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),

                  // Day plan: weekday selection UI
                  if (isDayPlan && _makeRecurring) ...[
                    const SizedBox(height: 14),
                    Text(
                      'REPEAT ON',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.75),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(7, (i) {
                        final w = i + 1; // 1..7
                        final selected = _recurringWeekdays.contains(w);
                        return _ChipToggle(
                          label: _weekdayLabel(w),
                          selected: selected,
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _recurringWeekdays.remove(w);
                              } else {
                                _recurringWeekdays.add(w);
                              }
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tip: you can pick multiple days (e.g. Mon/Wed/Fri).',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.50),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
                  : const Text(
                      'CREATE MEAL PLAN',
                      style: TextStyle(fontWeight: FontWeight.w900),
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
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF044246) : const Color(0xFFF3F6F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF044246),
            fontWeight: FontWeight.w900,
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
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
        Switch(value: value, onChanged: onChanged),
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
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w700,
      color: enabled ? Colors.black : Colors.black.withOpacity(0.35),
    );

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(title, style: titleStyle)),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: !enabled
                  ? Colors.black.withOpacity(0.25)
                  : (selected ? const Color(0xFF044246) : Colors.black38),
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
    final bg = selected ? const Color(0xFF044246) : const Color(0xFFF3F6F6);
    final fg = selected ? Colors.white : const Color(0xFF044246);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF044246) : Colors.black.withOpacity(0.10),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
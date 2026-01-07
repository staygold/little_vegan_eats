// lib/meal_plan/builder/meal_plan_builder_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/meal_plan_keys.dart';
import '../core/meal_plan_repository.dart';
import '../core/meal_plan_controller.dart';
import '../meal_plan_screen.dart';
import '../../recipes/recipe_repository.dart';

import 'meal_plan_builder_service.dart';

enum _HorizonUI { day, week }

class MealPlanBuilderScreen extends StatefulWidget {
  /// ✅ Optional: preselect the day when building a day plan.
  /// (Used by week-first empty-day CTA.)
  final String? initialSelectedDayKey;

  /// ✅ Optional: start on Day or Week. Defaults to week.
  final bool? startAsDayPlan;

  const MealPlanBuilderScreen({
    super.key,
    this.initialSelectedDayKey,
    this.startAsDayPlan,
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

  /// ✅ 0, 1, or 2 snacks
  int _snacksPerDay = 1;

  String _selectedDayKey = MealPlanKeys.todayKey();

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    final initDay = (widget.initialSelectedDayKey ?? '').trim();
    if (initDay.isNotEmpty) _selectedDayKey = initDay;

    if (widget.startAsDayPlan == true) {
      _horizon = _HorizonUI.day;
    }
  }

  @override
  void dispose() {
    _planNameController.dispose();
    super.dispose();
  }

  String get _weekId => MealPlanKeys.currentWeekId();
  List<String> get _next7DayKeys => MealPlanKeys.weekDayKeys(_weekId);

  String _prettyDay(String dayKey) {
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showInfo({
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  bool get _atLeastOneMealSelected =>
      _breakfast || _lunch || _dinner || _snacksPerDay > 0;

  Future<void> _createMealPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _showInfo(
        title: 'Not signed in',
        message: 'Please log in to build a meal plan.',
      );
      return;
    }

    if (!_atLeastOneMealSelected) {
      await _showInfo(
        title: 'Nothing selected',
        message: 'Select at least one meal or snack to generate a plan.',
      );
      return;
    }

    setState(() => _busy = true);

    try {
      final recipes = await RecipeRepository.ensureRecipesLoaded();
      if (recipes.isEmpty) {
        _snack('No recipes available to generate a plan yet.');
        setState(() => _busy = false);
        return;
      }

      final controller = MealPlanController(
        auth: FirebaseAuth.instance,
        repo: MealPlanRepository(FirebaseFirestore.instance),
        initialWeekId: _weekId,
      );

      final builderService = MealPlanBuilderService(controller);

      final isDayPlan = _horizon == _HorizonUI.day;

      await builderService.buildAndActivate(
        title: _planNameController.text.trim().isNotEmpty
            ? _planNameController.text.trim()
            : (isDayPlan ? "My Day Plan" : "My Week Plan"),
        availableRecipes: recipes,
        daysToPlan: isDayPlan ? 1 : 7,
        includeBreakfast: _breakfast,
        includeLunch: _lunch,
        includeDinner: _dinner,
        includeSnacks: _snacksPerDay > 0,
        snackCount: _snacksPerDay,

        // ✅ Day plan activates ONLY the selected day
        targetDayKey: isDayPlan ? _selectedDayKey : null,
      );

      if (!mounted) return;

      if (isDayPlan) {
        // ✅ CHANGE: go back to WEEK view, focused on the day we just created
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MealPlanScreen(
              weekId: _weekId,
              focusDayKey: _selectedDayKey,
              initialViewMode: MealPlanViewMode.week, // ✅ forces full week UI
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MealPlanScreen(
              weekId: _weekId,
              initialViewMode: MealPlanViewMode.week,
            ),
          ),
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print(e);
      await _showInfo(
        title: 'Could not create plan',
        message: 'Something went wrong. Try again.\n\n$e',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
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
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayKeys = _next7DayKeys;

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        title: const Text('Build meal plan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: [
            const SizedBox(height: 12),

            _sectionTitle('PLAN NAME'),
            _card(
              child: TextField(
                controller: _planNameController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Summer Shred or My Week',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),

            _sectionTitle('PLAN TYPE'),
            _card(
              child: Row(
                children: [
                  Expanded(
                    child: _SegButton(
                      label: 'Day plan',
                      selected: _horizon == _HorizonUI.day,
                      onTap: () => setState(() => _horizon = _HorizonUI.day),
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

            if (_horizon == _HorizonUI.day) ...[
              _sectionTitle('SELECT DAY'),
              _card(
                child: Column(
                  children: [
                    for (final dk in dayKeys)
                      _RadioRow(
                        title: _prettyDay(dk),
                        selected: _selectedDayKey == dk,
                        onTap: () => setState(() => _selectedDayKey = dk),
                      ),
                  ],
                ),
              ),
            ],

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
                children: [
                  Expanded(
                    child: _SegButton(
                      label: '0',
                      selected: _snacksPerDay == 0,
                      onTap: () => setState(() => _snacksPerDay = 0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SegButton(
                      label: '1',
                      selected: _snacksPerDay == 1,
                      onTap: () => setState(() => _snacksPerDay = 1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SegButton(
                      label: '2',
                      selected: _snacksPerDay == 2,
                      onTap: () => setState(() => _snacksPerDay = 2),
                    ),
                  ),
                ],
              ),
            ),

            _sectionTitle('SUMMARY'),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryLine(label: 'Week', value: _weekId),
                  const SizedBox(height: 6),
                  _SummaryLine(
                    label: 'Plan type',
                    value: (_horizon == _HorizonUI.day) ? 'Day' : 'Week',
                  ),
                  if (_horizon == _HorizonUI.day) ...[
                    const SizedBox(height: 6),
                    _SummaryLine(label: 'Day', value: _prettyDay(_selectedDayKey)),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_breakfast) const _Chip(text: 'Breakfast'),
                      if (_lunch) const _Chip(text: 'Lunch'),
                      if (_dinner) const _Chip(text: 'Dinner'),
                      if (_snacksPerDay > 0) _Chip(text: 'Snacks x$_snacksPerDay'),
                    ],
                  ),
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
          child: SizedBox(
            height: 52,
            width: double.infinity,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

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
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF044246) : const Color(0xFFF3F6F6),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
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
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _RadioRow({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? const Color(0xFF044246) : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.black.withOpacity(0.55),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: Color(0xFF044246),
        ),
      ),
    );
  }
}

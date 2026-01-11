// lib/meal_plan/saved_meal_plans_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_repository.dart';
import 'builder/meal_plan_builder_service.dart';
import 'core/meal_plan_controller.dart';
import 'core/meal_plan_keys.dart';
import 'core/meal_plan_repository.dart';

class SavedMealPlansScreen extends StatefulWidget {
  const SavedMealPlansScreen({super.key});

  @override
  State<SavedMealPlansScreen> createState() => _SavedMealPlansScreenState();
}

class _SavedMealPlansScreenState extends State<SavedMealPlansScreen> {
  static const Color _brandDark = Color(0xFF005A4F);
  static const Color _brandTeal = Color(0xFF32998D);
  static const Color _bg = Color(0xFFECF3F4);

  late final MealPlanRepository _repo;

  bool _saving = false;

  final TextEditingController _nameCtrl = TextEditingController();
  bool _nameDirty = false;

  // local weekday selection (Mon=1..Sun=7)
  Set<int> _weekdays = <int>{};

  // ✅ prevents “flash” by stopping hydration from overwriting local taps
  bool _weekdaysDirty = false;

  @override
  void initState() {
    super.initState();
    _repo = MealPlanRepository(FirebaseFirestore.instance);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ----------------------------
  // Helpers
  // ----------------------------

  String _weekdayShort(int w) {
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
        return '';
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _fmtKey(DateTime d) => MealPlanKeys.dayKey(d);

  DateTime? _parseKey(String? k) => k == null ? null : MealPlanKeys.parseDayKey(k);

  List<String> _computeScheduledDates({
    required DateTime start,
    required int weeks,
    required Set<int> weekdays, // Mon=1..Sun=7
  }) {
    final out = <String>[];
    if (weeks <= 0 || weekdays.isEmpty) return out;

    final startDay = _dateOnly(start);
    final totalDays = weeks * 7;

    for (int i = 0; i < totalDays; i++) {
      final d = startDay.add(Duration(days: i));
      if (weekdays.contains(d.weekday)) {
        out.add(_fmtKey(d));
      }
    }
    return out;
  }

  // hydrate UI from program doc safely
  void _hydrateFromProgram(Map<String, dynamic> program) {
    final name = (program['name'] ?? '').toString().trim();
    if (!_nameDirty) {
      _nameCtrl.text = name.isEmpty ? 'My Meal Plan' : name;
    }

    final rawWds = program['weekdays'];
    final nextSet = <int>{};
    if (rawWds is List) {
      for (final v in rawWds) {
        final n = int.tryParse(v.toString()) ?? 0;
        if (n >= 1 && n <= 7) nextSet.add(n);
      }
    }

    // ✅ Only hydrate weekdays when user isn't actively editing
    if (!_saving && !_weekdaysDirty) {
      _weekdays = nextSet;
    }
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  bool _asBool(dynamic v, {bool fallback = false}) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
    return fallback;
  }

  /// Pull meal-structure prefs from program doc (with sane defaults).
  Map<String, dynamic> _mealPrefsFromProgram(Map<String, dynamic> program) {
    final cfgRaw = program['config'];
    final cfg = (cfgRaw is Map) ? Map<String, dynamic>.from(cfgRaw) : <String, dynamic>{};

    // ✅ Defaults: breakfast/lunch/dinner on, snacks on with 1 snack
    return {
      'includeBreakfast': _asBool(cfg['includeBreakfast'], fallback: true),
      'includeLunch': _asBool(cfg['includeLunch'], fallback: true),
      'includeDinner': _asBool(cfg['includeDinner'], fallback: true),
      'includeSnacks': _asBool(cfg['includeSnacks'], fallback: true),
      'snackCount': _asInt(cfg['snackCount'], fallback: 1).clamp(0, 2),
    };
  }

  /// Determine which dates are newly added (and not in the past).
  List<String> _addedFutureDates({
    required List<String> oldScheduled,
    required List<String> newScheduled,
  }) {
    final oldSet = oldScheduled.toSet();
    final today = MealPlanKeys.todayKey();

    final added = <String>[];
    for (final dk in newScheduled) {
      if (!oldSet.contains(dk) && dk.compareTo(today) >= 0) {
        added.add(dk);
      }
    }
    return added;
  }

  /// Determine which dates are removed (and not in the past).
  List<String> _removedFutureDates({
    required List<String> oldScheduled,
    required List<String> newScheduled,
  }) {
    final newSet = newScheduled.toSet();
    final today = MealPlanKeys.todayKey();

    final removed = <String>[];
    for (final dk in oldScheduled) {
      if (!newSet.contains(dk) && dk.compareTo(today) >= 0) {
        removed.add(dk);
      }
    }
    return removed;
  }

  Future<int> _backfillProgramDays({
    required String uid,
    required String programId,
    required Map<String, dynamic> program,
    required List<String> oldScheduled,
    required List<String> newScheduled,
  }) async {
    final addedDates = _addedFutureDates(oldScheduled: oldScheduled, newScheduled: newScheduled);
    if (addedDates.isEmpty) return 0;

    final recipes = await RecipeRepository.ensureRecipesLoaded(backgroundRefresh: false);
    if (recipes.isEmpty) return 0;

    // Controller is only used for candidate selection + allergy filtering helpers.
    final controller = MealPlanController(
      auth: FirebaseAuth.instance,
      repo: MealPlanRepository(FirebaseFirestore.instance),
    );

    final service = MealPlanBuilderService(controller);
    final prefs = _mealPrefsFromProgram(program);

    return service.backfillNewProgramDays(
      programId: programId,
      oldScheduledDates: oldScheduled,
      newScheduledDates: newScheduled,
      availableRecipes: recipes,
      includeBreakfast: prefs['includeBreakfast'] as bool,
      includeLunch: prefs['includeLunch'] as bool,
      includeDinner: prefs['includeDinner'] as bool,
      includeSnacks: prefs['includeSnacks'] as bool,
      snackCount: prefs['snackCount'] as int,
    );
  }

  /// ✅ Delete program-day docs for removed future dates (and legacy mirror if you still keep it).
  Future<int> _pruneRemovedProgramDays({
    required String uid,
    required String programId,
    required List<String> oldScheduled,
    required List<String> newScheduled,
  }) async {
    final removed = _removedFutureDates(oldScheduled: oldScheduled, newScheduled: newScheduled);
    if (removed.isEmpty) return 0;

    // We do sequential deletes for simplicity (counts are small: weekdays changes usually removes a few days).
    for (final dk in removed) {
      await _repo.deleteProgramDayInProgram(uid: uid, programId: programId, dateKey: dk);

      // Optional legacy mirror delete (safe even if doc doesn't exist)
      await _repo.deleteProgramDay(uid: uid, dateKey: dk);
    }

    return removed.length;
  }

  String _scheduleSnackText({required int added, required int removed, required String base}) {
    if (added <= 0 && removed <= 0) return base;
    if (added > 0 && removed > 0) return '$base (+$added added, -$removed removed)';
    if (added > 0) return '$base (+$added added)';
    return '$base (-$removed removed)';
  }

  // ----------------------------
  // Actions
  // ----------------------------

  Future<void> _saveName({
    required String uid,
    required String programId,
  }) async {
    final name = _nameCtrl.text.trim();
    final safeName = name.isEmpty ? 'My Meal Plan' : name;

    setState(() => _saving = true);
    try {
      await _repo.updateProgram(
        uid: uid,
        programId: programId,
        patch: {'name': safeName},
      );
      if (!mounted) return;
      setState(() => _nameDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan name updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveWeekdays({
    required String uid,
    required String programId,
    required Map<String, dynamic> program,
  }) async {
    final list = _weekdays.toList()..sort();

    final startKey = (program['startDate'] ?? '').toString().trim();
    final weeksRaw = program['weeks'];
    final weeks = (weeksRaw is int) ? weeksRaw : int.tryParse(weeksRaw?.toString() ?? '') ?? 0;

    final startDt = _parseKey(startKey);

    // ✅ capture old schedule
    final oldScheduled = (program['scheduledDates'] is List)
        ? (program['scheduledDates'] as List).map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];

    final scheduled = (startDt != null && weeks > 0)
        ? _computeScheduledDates(start: startDt, weeks: weeks, weekdays: _weekdays)
        : <String>[];

    final endKey = scheduled.isNotEmpty ? scheduled.last : (startDt != null ? _fmtKey(startDt) : '');

    setState(() => _saving = true);
    try {
      // ✅ update program doc first (source of truth)
      await _repo.updateProgram(
        uid: uid,
        programId: programId,
        patch: {
          'weekdays': list,
          if (scheduled.isNotEmpty) 'scheduledDates': scheduled,
          if (endKey.isNotEmpty) 'endDate': endKey,
        },
      );

      // ✅ prune removed future days
      final removed = await _pruneRemovedProgramDays(
        uid: uid,
        programId: programId,
        oldScheduled: oldScheduled,
        newScheduled: scheduled,
      );

      // ✅ backfill newly added future days
      final added = await _backfillProgramDays(
        uid: uid,
        programId: programId,
        program: program,
        oldScheduled: oldScheduled,
        newScheduled: scheduled,
      );

      if (!mounted) return;
      setState(() => _weekdaysDirty = false); // ✅ we’re now in sync with Firestore

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_scheduleSnackText(added: added, removed: removed, base: 'Schedule updated'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _extendWeeks({
    required String uid,
    required String programId,
    required Map<String, dynamic> program,
  }) async {
    final startKey = (program['startDate'] ?? '').toString().trim();
    final startDt = _parseKey(startKey);
    if (startDt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Missing start date')));
      return;
    }

    final weeksRaw = program['weeks'];
    final currentWeeks = (weeksRaw is int) ? weeksRaw : int.tryParse(weeksRaw?.toString() ?? '') ?? 0;

    // ✅ capture old schedule
    final oldScheduled = (program['scheduledDates'] is List)
        ? (program['scheduledDates'] as List).map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];

    final extra = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int v = 1;
        return AlertDialog(
          title: const Text('Extend plan'),
          content: Row(
            children: [
              const Text('Add weeks:'),
              const SizedBox(width: 12),
              StatefulBuilder(
                builder: (context, setLocal) {
                  return DropdownButton<int>(
                    value: v,
                    items: const [1, 2, 3, 4, 6, 8, 12]
                        .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                        .toList(),
                    onChanged: (n) => setLocal(() => v = n ?? 1),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, v), child: const Text('Extend')),
          ],
        );
      },
    );

    if (extra == null) return;

    final nextWeeks = currentWeeks + extra;
    final scheduled = _computeScheduledDates(start: startDt, weeks: nextWeeks, weekdays: _weekdays);
    final endKey = scheduled.isNotEmpty ? scheduled.last : _fmtKey(startDt);

    setState(() => _saving = true);
    try {
      await _repo.updateProgram(
        uid: uid,
        programId: programId,
        patch: {
          'weeks': nextWeeks,
          'scheduledDates': scheduled,
          'endDate': endKey,
        },
      );

      // Extend should typically only add, but if weekdays were edited earlier and not saved,
      // this keeps behaviour consistent.
      final removed = await _pruneRemovedProgramDays(
        uid: uid,
        programId: programId,
        oldScheduled: oldScheduled,
        newScheduled: scheduled,
      );

      final added = await _backfillProgramDays(
        uid: uid,
        programId: programId,
        program: program,
        oldScheduled: oldScheduled,
        newScheduled: scheduled,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_scheduleSnackText(added: added, removed: removed, base: 'Plan extended'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stopProgram({
    required String uid,
    required String programId,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop this plan?'),
        content: const Text(
          'This will stop your current meal plan.\n\n'
          'You can create a new plan any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Stop plan'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await _repo.updateProgram(
        uid: uid,
        programId: programId,
        patch: {
          'status': 'stopped',
          'stoppedAt': FieldValue.serverTimestamp(),
        },
      );

      // ✅ clear pointer in settings (the one hub + MealPlanScreen use)
      await _repo.setActiveProgramId(uid: uid, programId: null);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan stopped')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ----------------------------
  // Build
  // ----------------------------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Log in')));
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Plan settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _brandDark,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('mealPlan')
            .doc('settings')
            .snapshots(),
        builder: (context, stateSnap) {
          if (stateSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final state = stateSnap.data?.data() ?? <String, dynamic>{};
          final programId = (state['activeProgramId'] ?? '').toString().trim();

          if (programId.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _EmptySettingsCard(
                brandDark: _brandDark,
                brandTeal: _brandTeal,
                onBack: () => Navigator.of(context).pop(),
              ),
            );
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _repo.programDoc(uid: user.uid, programId: programId).snapshots(),
            builder: (context, progSnap) {
              if (progSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final exists = progSnap.data?.exists ?? false;
              final program = exists ? progSnap.data?.data() : null;

              if (program == null) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Loading plan…',
                          style: TextStyle(color: _brandDark, fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your plan pointer exists but the plan document is missing.',
                          style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _brandTeal,
                              side: BorderSide(color: _brandTeal, width: 2),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text(
                              'BACK',
                              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              _hydrateFromProgram(program);

              final weeksRaw = program['weeks'];
              final weeks = (weeksRaw is int) ? weeksRaw : int.tryParse(weeksRaw?.toString() ?? '') ?? 0;
              final startKey = (program['startDate'] ?? '').toString().trim();
              final endKey = (program['endDate'] ?? '').toString().trim();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                children: [
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PLAN NAME', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _nameCtrl,
                          onChanged: (_) => setState(() => _nameDirty = true),
                          decoration: const InputDecoration(
                            hintText: 'My Meal Plan',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : () => _saveName(uid: user.uid, programId: programId),
                            style: ElevatedButton.styleFrom(backgroundColor: _brandTeal, shape: const StadiumBorder()),
                            child: const Text(
                              'SAVE NAME',
                              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WEEKLY SCHEDULE',
                          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            for (int w = 1; w <= 7; w++) ...[
                              Expanded(
                                child: _WeekdayToggle(
                                  label: _weekdayShort(w),
                                  selected: _weekdays.contains(w),
                                  brandDark: _brandDark,
                                  brandTeal: _brandTeal,
                                  onTap: _saving
                                      ? null
                                      : () {
                                          setState(() {
                                            _weekdaysDirty = true;
                                            if (_weekdays.contains(w)) {
                                              _weekdays.remove(w);
                                            } else {
                                              _weekdays.add(w);
                                            }
                                          });
                                        },
                                ),
                              ),
                              if (w != 7) const SizedBox(width: 8),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => _saveWeekdays(uid: user.uid, programId: programId, program: program),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _brandTeal,
                              side: BorderSide(color: _brandTeal, width: 2),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text(
                              'SAVE SCHEDULE',
                              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DURATION', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                        const SizedBox(height: 10),
                        Text(
                          weeks > 0 ? '$weeks week${weeks == 1 ? '' : 's'}' : 'Not set',
                          style: TextStyle(color: Colors.black.withOpacity(0.65), fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        if (startKey.isNotEmpty || endKey.isNotEmpty)
                          Text(
                            [
                              if (startKey.isNotEmpty) 'Starts: ${MealPlanKeys.formatPretty(startKey)}',
                              if (endKey.isNotEmpty) 'Ends: ${MealPlanKeys.formatPretty(endKey)}',
                            ].join('   •   '),
                            style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w600),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving
                                ? null
                                : () => _extendWeeks(uid: user.uid, programId: programId, program: program),
                            style: ElevatedButton.styleFrom(backgroundColor: _brandTeal, shape: const StadiumBorder()),
                            child: const Text(
                              'EXTEND PLAN',
                              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('STOP PLAN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                        const SizedBox(height: 10),
                        Text(
                          'This will stop your current plan and remove it from the hub.',
                          style: TextStyle(color: Colors.black.withOpacity(0.60), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _saving ? null : () => _stopProgram(uid: user.uid, programId: programId),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red, width: 2),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text(
                              'STOP MY PLAN',
                              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, 10),
            blurRadius: 22,
            color: Color.fromRGBO(0, 0, 0, 0.08),
          )
        ],
      ),
      child: child,
    );
  }
}

class _WeekdayToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final Color brandDark;
  final Color brandTeal;
  final VoidCallback? onTap;

  const _WeekdayToggle({
    required this.label,
    required this.selected,
    required this.brandDark,
    required this.brandTeal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? brandDark : Colors.white;
    final fg = selected ? Colors.white : brandDark.withOpacity(0.75);
    final border = selected ? Colors.transparent : brandDark.withOpacity(0.12);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.1,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _EmptySettingsCard extends StatelessWidget {
  final Color brandDark;
  final Color brandTeal;
  final VoidCallback onBack;

  const _EmptySettingsCard({
    required this.brandDark,
    required this.brandTeal,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(offset: Offset(0, 10), blurRadius: 22, color: Color.fromRGBO(0, 0, 0, 0.08))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No active plan', style: TextStyle(color: brandDark, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            'Create a plan first, then you can edit your schedule and extend it here.',
            style: TextStyle(color: Colors.black.withOpacity(0.62), fontWeight: FontWeight.w600, height: 1.25),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onBack,
              style: ElevatedButton.styleFrom(backgroundColor: brandTeal, shape: const StadiumBorder()),
              child: const Text('BACK', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3)),
            ),
          ),
        ],
      ),
    );
  }
}

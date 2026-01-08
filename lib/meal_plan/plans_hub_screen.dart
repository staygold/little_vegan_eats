// lib/meal_plan/plans_hub_screen.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core/meal_plan_keys.dart';
import 'core/meal_plan_repository.dart';
import 'services/meal_plan_manager.dart';
import 'meal_plan_screen.dart';
import 'builder/meal_plan_builder_screen.dart';
import 'saved_meal_plans_screen.dart';

class PlansHubScreen extends StatefulWidget {
  const PlansHubScreen({super.key});

  @override
  State<PlansHubScreen> createState() => _PlansHubScreenState();
}

class _PlansHubScreenState extends State<PlansHubScreen> {
  static const Color _brandDark = Color(0xFF005A4F);
  static const Color _brandTeal = Color(0xFF32998D);
  static const Color _bg = Color(0xFFECF3F4);

  late final MealPlanRepository _repo;

  // 0 = this week, positive = future weeks
  int _weekOffset = 0;

  // ✅ ALLOW 1 YEAR OF SCROLLING
  static const int _maxWeeksForward = 52;

  @override
  void initState() {
    super.initState();
    _repo = MealPlanRepository(FirebaseFirestore.instance);
    _triggerWeekCheck();
  }

  @override
  void didUpdateWidget(covariant PlansHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _triggerWeekCheck();
  }

  // ---------- LOGIC TRIGGERS ----------

  void _triggerWeekCheck() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final weekId = _weekIdForOffset(_weekOffset);
    _repo.ensureWeekExists(uid: uid, weekId: weekId);
  }

  // ---------- DATE HELPERS ----------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isPastDay(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return true;
    return _dateOnly(dt).isBefore(_dateOnly(DateTime.now()));
  }

  String _monthShort(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final idx = (m - 1).clamp(0, 11);
    return months[idx];
  }

  String _weekRangeLabel(String weekId) {
    final dayKeys = MealPlanKeys.weekDayKeys(weekId);
    if (dayKeys.isEmpty) return 'This week';

    final start = MealPlanKeys.parseDayKey(dayKeys.first);
    final end = MealPlanKeys.parseDayKey(dayKeys.last);
    if (start == null || end == null) return 'This week';

    if (start.month == end.month) {
      return '${start.day}–${end.day} ${_monthShort(start.month)}';
    }
    return '${start.day} ${_monthShort(start.month)}–${end.day} ${_monthShort(end.month)}';
  }

  String _weekIdForOffset(int offset) {
    final base = MealPlanKeys.parseDayKey(MealPlanKeys.currentWeekId()) ?? DateTime.now();
    final monday = MealPlanKeys.weekStartMonday(base);
    final target = monday.add(Duration(days: 7 * offset));
    return MealPlanKeys.weekIdForDate(target);
  }

  // Local dayKey formatter to avoid relying on any extra helpers.
  String _dayKeyForDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  // ---------- NAVIGATION ----------

  void _navigateToBuilder({
    required String weekId,
    required MealPlanBuilderEntry entry,
    String? dayKey,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MealPlanBuilderScreen(
            weekId: weekId,
            entry: entry,
            initialSelectedDayKey: dayKey,
          ),
        ),
      );
    });
  }

  void _openMealPlanWeek(String weekId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanScreen(
          weekId: weekId,
          initialViewMode: MealPlanViewMode.week,
        ),
      ),
    );
  }

  void _openMealPlanForDay(String weekId, String dayKey) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanScreen(
          weekId: weekId,
          focusDayKey: dayKey,
          initialViewMode: MealPlanViewMode.today,
        ),
      ),
    );
  }

  void _openSavedPlansList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedMealPlansScreen()),
    );
  }

  // ✅ NEW: pick start date (today → 14 days ahead) for week-only builder
  Future<DateTime?> _pickWeekPlanStartDate() async {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final last = today.add(const Duration(days: 14));

    return showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: last,
      helpText: 'Choose start date',
      fieldHintText: 'YYYY-MM-DD',
    );
  }

  // ✅ NEW: create week plan flow (date picker → ensure week doc exists → open week-only builder)
  Future<void> _onCreateWeekPlanPressed() async {
    final picked = await _pickWeekPlanStartDate();
    if (picked == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final weekId = MealPlanKeys.weekIdForDate(picked);
    final dayKey = _dayKeyForDate(picked);

    // Ensure the week doc exists before builder loads
    _repo.ensureWeekExists(uid: uid, weekId: weekId);

    _navigateToBuilder(
      weekId: weekId,
      entry: MealPlanBuilderEntry.weekOnly,
      dayKey: dayKey, // ✅ anchor/start day for week plan builder
    );
  }

  // ---------- DATA HELPERS ----------

  Map<String, dynamic> _mapOrEmpty(dynamic v) =>
      (v is Map) ? Map<String, dynamic>.from(v as Map) : <String, dynamic>{};

  bool _isMeaningful(dynamic v) {
    if (v == null) return false;
    if (v is Map) return v.isNotEmpty;
    if (v is List) return v.isNotEmpty;
    if (v is String) return v.trim().isNotEmpty;
    if (v is num) return true;
    if (v is bool) return v; // only count true as meaningful
    return true; // fallback: if something is stored, treat as meaningful
  }

  /// ✅ FIX:
  /// Day-only plans are often stored as refs/ids (strings) not nested maps.
  /// Treat any non-title meaningful field as “has a plan”.
  bool _dayHasPlan(dynamic dayData) {
    final m = _mapOrEmpty(dayData);
    if (m.isEmpty) return false;

    for (final entry in m.entries) {
      final k = entry.key.toString();
      if (k == 'title') continue;

      if (_isMeaningful(entry.value)) return true;
    }

    return false;
  }

  Stream<bool> _hasAnySavedPlansStream(String uid) {
    // We only need to know if the library is empty.
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedMealPlans')
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty);
  }

  /// ✅ If weekPlanStartDayKey isn't written on the *first* week (common when the builder creates it),
  /// infer it from the earliest day in THIS week that actually has planned entries.
  String? _inferWeekPlanStartDayKey({
    required List<String> weekKeys,
    required Map<String, dynamic> daysMap,
  }) {
    for (final dk in weekKeys) {
      final dayData = daysMap[dk];
      if (_dayHasPlan(dayData)) return dk;
    }
    return null;
  }

  ({bool isWeekPlan, String title, String? weekStartDayKey}) _resolvePlanMeta(
    Map<String, dynamic> weekDocData, {
    required List<String> weekKeys,
    required Map<String, dynamic> daysMap,
  }) {
    final config = _mapOrEmpty(weekDocData['config']);
    final title = (config['title'] ?? '').toString().trim();

    final horizon = (config['horizon'] ?? config['mode'] ?? config['activeMode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final sourceWeekPlanId = (config['sourceWeekPlanId'] ?? '').toString().trim();

    final startKey = (config['weekPlanStartDayKey'] ??
            config['appliedFromDayKey'] ??
            config['startDayKey'])
        ?.toString()
        .trim();
    String? weekStartDayKey = (startKey != null && startKey.isNotEmpty) ? startKey : null;

    final isWeekPlan = sourceWeekPlanId.isNotEmpty || horizon == 'week';

    // ✅ IMPORTANT FIX:
    // If we have a week plan but no start key (often the first week),
    // infer it from the first planned day in this week so Day 1.. displays.
    if (isWeekPlan && (weekStartDayKey == null || weekStartDayKey.isEmpty)) {
      weekStartDayKey = _inferWeekPlanStartDayKey(weekKeys: weekKeys, daysMap: daysMap);
    }

    return (
      isWeekPlan: isWeekPlan,
      title: title.isNotEmpty ? title : 'My Week Plan',
      weekStartDayKey: (weekStartDayKey != null && weekStartDayKey.isNotEmpty) ? weekStartDayKey : null,
    );
  }

  int? _dayIndexForWeekPlan({
    required String dayKey,
    required String? startDayKey,
  }) {
    if (startDayKey == null || startDayKey.trim().isEmpty) return null;

    final start = MealPlanKeys.parseDayKey(startDayKey);
    final current = MealPlanKeys.parseDayKey(dayKey);

    if (start == null || current == null) return null;

    final diff = current.difference(start).inDays;
    if (diff < 0) return null;

    return (diff % 7) + 1;
  }

  // ---------- ACTIONS ----------

  Future<void> _onClearWeekPressed({
    required String weekId,
    required bool weekPlanPresent,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear entire week?"),
        content: Text(
          weekPlanPresent
              ? "Weekly plan will be removed. This will clear all meals currently scheduled for this week."
              : "This will remove all plans currently scheduled for this week.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Clear All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await MealPlanManager().clearWeekCompletely(weekId: weekId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Week cleared')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear week: $e')));
    }
  }

  Future<void> _removeDayPlan(String weekId, String dayKey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove this day plan?"),
        content: Text("Clear the meals for ${MealPlanKeys.formatPretty(dayKey)}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await MealPlanManager().removeDayFromWeek(weekId: weekId, dayKey: dayKey);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to remove day plan: $e')));
    }
  }

  /// ✅ SUPER NUKE: Deletes ALL weeks, saved plans, and settings.
  Future<void> _nukeWeekDoc(String ignoredWeekId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("🔥 SUPER NUKE (DEBUG)"),
        content: const Text(
          "This will delete:\n"
          "1. ALL Calendar Weeks\n"
          "2. ALL Saved Plans (Templates)\n"
          "3. ALL Settings\n\n"
          "This simulates a brand new user.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "DELETE EVERYTHING",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      // 1. Delete Weeks
      final weeks = await userRef.collection('mealPlansWeeks').get();
      for (final doc in weeks.docs) batch.delete(doc.reference);

      // 2. Delete Saved Plans (Templates)
      final plans = await userRef.collection('savedMealPlans').get();
      for (final doc in plans.docs) batch.delete(doc.reference);

      // 3. Reset Settings
      batch.delete(userRef.collection('mealPlan').doc('settings'));

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('💥 Everything deleted! Fresh start.')));

      setState(() {
        _weekOffset = 0;
      });
      _triggerWeekCheck();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nuke failed: $e')));
    }
  }

  // ---------- EMPTY STATE UI ----------

  Widget _emptyState({
    required String weekLabel,
    required VoidCallback onCreate,
    required VoidCallback onSavedPlans,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No meal plans yet',
                style: TextStyle(
                  color: _brandDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create your first weekly plan to get started. You can also save plans as templates and reuse them later.',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.65),
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onCreate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandTeal,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    'CREATE A MEAL PLAN',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onSavedPlans,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _brandTeal,
                    side: const BorderSide(color: _brandTeal, width: 2),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    'VIEW SAVED PLANS',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Week: $weekLabel',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.45),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in')));
    }

    final weekId = _weekIdForOffset(_weekOffset);
    final weekLabel = _weekRangeLabel(weekId);
    final isThisWeek = _weekOffset == 0;
    final weekKeys = MealPlanKeys.weekDayKeys(weekId);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Meal Planner'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: const TextStyle(
          color: _brandDark,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: _brandDark),
            tooltip: 'Saved Plans',
            onPressed: _openSavedPlansList,
          ),
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              tooltip: 'NUKE EVERYTHING',
              onPressed: () => _nukeWeekDoc(weekId),
            ),
        ],
      ),
      body: Column(
        children: [
          _WeekSwitcherHeader(
            label: isThisWeek ? "THIS WEEK" : "WEEK",
            range: weekLabel,
            brandDark: _brandDark,
            canGoPrev: _weekOffset > 0,
            canGoNext: _weekOffset < _maxWeeksForward,
            onPrev: () {
              setState(() => _weekOffset = (_weekOffset - 1).clamp(0, _maxWeeksForward));
              _triggerWeekCheck();
            },
            onNext: () {
              setState(() => _weekOffset = (_weekOffset + 1).clamp(0, _maxWeeksForward));
              _triggerWeekCheck();
            },
          ),
          Expanded(
            child: StreamBuilder<bool>(
              stream: _hasAnySavedPlansStream(user.uid),
              builder: (context, savedSnap) {
                final hasSavedPlans = savedSnap.data ?? false;

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('mealPlansWeeks')
                      .doc(weekId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting ||
                        savedSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final weekExists = snapshot.hasData && snapshot.data != null && snapshot.data!.exists;
                    final data = weekExists ? (snapshot.data!.data() ?? {}) : <String, dynamic>{};

                    final config = _mapOrEmpty(data['config']);
                    final daysMap = _mapOrEmpty(data['days']);

                    final hasAny = weekExists ? MealPlanRepository.hasAnyPlannedEntries(data) : false;

                    // ✅ GLOBAL EMPTY STATE:
                    // No saved plans AND nothing scheduled in this week
                    if (!hasSavedPlans && !hasAny) {
                      return _emptyState(
                        weekLabel: weekLabel,
                        onCreate: _onCreateWeekPlanPressed,
                        onSavedPlans: _openSavedPlansList,
                      );
                    }

                    final meta = _resolvePlanMeta(
                      data,
                      weekKeys: weekKeys,
                      daysMap: daysMap,
                    );
                    final isWeekPlan = meta.isWeekPlan;
                    final planTitle = meta.title;
                    final startDayKey = meta.weekStartDayKey;

                    final weekPlanPresent = weekExists && isWeekPlan;
                    final dayPlanTitles = _mapOrEmpty(config['dayPlanTitles']);

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
                      children: [
                        _TopActionsCard(
                          brandDark: _brandDark,
                          brandTeal: _brandTeal,
                          weekHasAnything: hasAny,
                          onOpenWeek: hasAny ? () => _openMealPlanWeek(weekId) : null,
                          onCreateWeekPlan: _onCreateWeekPlanPressed,
                          onSavedPlans: _openSavedPlansList,
                          onClearWeek: () => _onClearWeekPressed(
                            weekId: weekId,
                            weekPlanPresent: weekPlanPresent,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'YOUR WEEK',
                          style: TextStyle(
                            color: _brandDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),

                        ...weekKeys.map((dayKey) {
                          final dayData = daysMap[dayKey];
                          final active = _dayHasPlan(dayData);

                          final isPast = _isPastDay(dayKey);
                          final canTap = active || !isPast;

                          String subtitle;
                          if (active) {
                            if (isWeekPlan) {
                              final n = _dayIndexForWeekPlan(
                                dayKey: dayKey,
                                startDayKey: startDayKey,
                              );
                              subtitle = (n != null) ? '$planTitle · Day $n' : planTitle;
                              if (isPast) subtitle = 'Past day · $subtitle';
                            } else {
                              final titleFromConfig = (dayPlanTitles[dayKey] ?? '').toString().trim();
                              final titleFromDay = (dayData is Map && dayData['title'] != null)
                                  ? dayData['title'].toString().trim()
                                  : '';
                              final cfgTitle = (config['title'] ?? '').toString().trim();

                              subtitle = titleFromConfig.isNotEmpty
                                  ? titleFromConfig
                                  : (titleFromDay.isNotEmpty
                                      ? titleFromDay
                                      : (cfgTitle.isNotEmpty ? cfgTitle : 'Day plan'));
                            }
                          } else {
                            subtitle = isPast ? 'Past day (can’t add)' : 'No plan set';
                          }

                          return _DaySlotCard(
                            title: MealPlanKeys.formatPretty(dayKey),
                            subtitle: subtitle,
                            brandTeal: _brandTeal,
                            active: active,
                            disabled: !canTap,
                            isPast: isPast,
                            showAdd: !active && !isPast,
                            onTap: () {
                              if (!canTap) return;
                              if (active) {
                                _openMealPlanForDay(weekId, dayKey);
                              } else {
                                _navigateToBuilder(
                                  weekId: weekId,
                                  entry: MealPlanBuilderEntry.dayOnly,
                                  dayKey: dayKey,
                                );
                              }
                            },
                            onRemove: active && !isWeekPlan ? () => _removeDayPlan(weekId, dayKey) : null,
                          );
                        }).toList(),

                        const SizedBox(height: 6),

                        if (!hasAny && hasSavedPlans)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Tip: Pick a saved plan and set it to recur to auto-fill future weeks.',
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.45),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- UI ----------

class _WeekSwitcherHeader extends StatelessWidget {
  final String label;
  final String range;
  final Color brandDark;
  final bool canGoPrev;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _WeekSwitcherHeader({
    required this.label,
    required this.range,
    required this.brandDark,
    required this.canGoPrev,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous week',
            onPressed: canGoPrev ? onPrev : null,
            icon: Icon(
              Icons.chevron_left,
              color: canGoPrev ? brandDark : brandDark.withOpacity(0.25),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: brandDark.withOpacity(0.85),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  range,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: brandDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Next week',
            onPressed: canGoNext ? onNext : null,
            icon: Icon(
              Icons.chevron_right,
              color: canGoNext ? brandDark : brandDark.withOpacity(0.25),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopActionsCard extends StatelessWidget {
  final Color brandDark;
  final Color brandTeal;
  final bool weekHasAnything;

  final VoidCallback? onOpenWeek;
  final VoidCallback onCreateWeekPlan;
  final VoidCallback onSavedPlans;
  final VoidCallback onClearWeek;

  const _TopActionsCard({
    required this.brandDark,
    required this.brandTeal,
    required this.weekHasAnything,
    required this.onOpenWeek,
    required this.onCreateWeekPlan,
    required this.onSavedPlans,
    required this.onClearWeek,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MEAL PLANS',
            style: TextStyle(
              color: brandDark,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            weekHasAnything ? 'Manage your plans for the week.' : 'No plans scheduled yet.',
            style: TextStyle(
              color: Colors.black.withOpacity(0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PillButton(
                  label: 'OPEN WEEK',
                  filled: true,
                  brandTeal: brandTeal,
                  onTap: weekHasAnything ? (onOpenWeek ?? onCreateWeekPlan) : onCreateWeekPlan,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PillButton(
                  label: 'CREATE WEEK PLAN',
                  filled: false,
                  brandTeal: brandTeal,
                  onTap: onCreateWeekPlan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PillButton(
            label: 'SAVED PLANS',
            filled: false,
            brandTeal: brandTeal,
            onTap: onSavedPlans,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onClearWeek,
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              label: const Text(
                'Clear full week',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySlotCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color brandTeal;

  final bool active;
  final bool disabled;
  final bool showAdd;
  final bool isPast;

  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _DaySlotCard({
    required this.title,
    required this.subtitle,
    required this.brandTeal,
    required this.active,
    required this.disabled,
    required this.showAdd,
    required this.isPast,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bool pastStyle = isPast;

    final border = active
        ? (pastStyle ? Colors.grey.shade400 : brandTeal)
        : Colors.grey.shade300;

    final bg = disabled
        ? Colors.white.withOpacity(0.45)
        : (active
            ? (pastStyle ? Colors.white.withOpacity(0.80) : Colors.white)
            : Colors.white.withOpacity(0.70));

    final subtitleColor = active
        ? (pastStyle ? Colors.black.withOpacity(0.45) : brandTeal)
        : Colors.black.withOpacity(0.55);

    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: active && !pastStyle ? 2 : 0,
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: active ? 1.5 : 1),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: active ? FontWeight.w900 : FontWeight.w800,
              color: Colors.black.withOpacity(disabled ? 0.55 : 0.90),
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: subtitleColor,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          trailing: disabled
              ? null
              : (active
                  ? PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'view') onTap();
                        if (v == 'remove') onRemove?.call();
                      },
                      itemBuilder: (_) {
                        final items = <PopupMenuEntry<String>>[
                          const PopupMenuItem(value: 'view', child: Text('View/Edit')),
                        ];

                        if (onRemove != null) {
                          items.add(
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove day plan', style: TextStyle(color: Colors.red)),
                            ),
                          );
                        }

                        return items;
                      },
                      icon: Icon(Icons.more_vert, color: brandTeal),
                    )
                  : (showAdd
                      ? Icon(Icons.add_circle_outline, color: brandTeal)
                      : const SizedBox.shrink())),
          onTap: disabled ? null : onTap,
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  final Color brandTeal;

  const _PillButton({
    required this.label,
    required this.filled,
    required this.onTap,
    required this.brandTeal,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? brandTeal : Colors.transparent;
    final fg = filled ? Colors.white : brandTeal;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: brandTeal, width: 2),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

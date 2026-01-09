// lib/meal_plan/plans_hub_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core/meal_plan_keys.dart';
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

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _programSub;

  String? _activeProgramId;
  Map<String, dynamic>? _program;

  bool _loading = true;

  // ----------------------------
  // Firestore refs (MATCH MealPlanScreen)
  // ----------------------------
  DocumentReference<Map<String, dynamic>> _settingsDoc(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('mealPlan')
        .doc('settings'); // ✅ this is what MealPlanScreen uses
  }

  DocumentReference<Map<String, dynamic>> _programDoc(
    String uid,
    String programId,
  ) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('mealPrograms')
        .doc(programId);
  }

  @override
  void initState() {
    super.initState();
    _listenSettings();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _programSub?.cancel();
    super.dispose();
  }

  void _listenSettings() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    _settingsSub?.cancel();
    _settingsSub = _settingsDoc(uid).snapshots().listen((snap) {
      final data = snap.data() ?? <String, dynamic>{};
      final nextId = (data['activeProgramId'] ?? '').toString().trim();

      if (!mounted) return;

      // No active program
      if (nextId.isEmpty) {
        _programSub?.cancel();
        setState(() {
          _activeProgramId = null;
          _program = null;
          _loading = false;
        });
        return;
      }

      // Active program changed
      if (nextId != _activeProgramId) {
        setState(() {
          _activeProgramId = nextId;
          _program = null;
          _loading = true;
        });
        _listenProgram(uid, nextId);
      }
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  void _listenProgram(String uid, String programId) {
    _programSub?.cancel();
    _programSub = _programDoc(uid, programId).snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _program = snap.data();
        _loading = false;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  // ----------------------------
  // Program fields
  // ----------------------------
  bool get _hasProgram =>
      (_activeProgramId ?? '').trim().isNotEmpty && _program != null;

  String _planTitle() {
    final name = (_program?['name'] ?? '').toString().trim();
    return name.isEmpty ? 'My Meal Plan' : name;
  }

  List<int> _weekdays() {
    // Mon=1..Sun=7
    final raw = _program?['weekdays'];
    if (raw is List) {
      final set = <int>{};
      for (final v in raw) {
        final n = int.tryParse(v.toString()) ?? 0;
        if (n >= 1 && n <= 7) set.add(n);
      }
      final out = set.toList()..sort();
      return out;
    }
    return const <int>[];
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime? _parseKey(String? k) =>
      k == null ? null : MealPlanKeys.parseDayKey(k);

  String _timeLeftLabel() {
    // Optional nicety: only if endDate exists
    final endKey = (_program?['endDate'] ?? '').toString().trim();
    if (endKey.isEmpty) return '';

    final endDt = _parseKey(endKey);
    if (endDt == null) return '';

    final today = _dateOnly(DateTime.now());
    final end = _dateOnly(endDt);

    if (end.isBefore(today)) return 'Finished';
    final daysLeft = end.difference(today).inDays;
    if (daysLeft == 0) return 'Ends today';
    if (daysLeft == 1) return '1 day left';
    if (daysLeft < 7) return '$daysLeft days left';
    final weeksLeft = (daysLeft / 7).ceil();
    return '$weeksLeft week${weeksLeft == 1 ? '' : 's'} left';
  }

  String _statusText() {
    if (!_hasProgram) return 'No plan yet';
    final wds = _weekdays();
    if (wds.isEmpty) return 'Schedule not set';
    final left = _timeLeftLabel();
    return left.isEmpty ? 'Schedule set' : left;
  }

  // ----------------------------
  // Navigation
  // ----------------------------
  void _openMealPlan() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanScreen(
          // ✅ MealPlanScreen is week-only now; focus today so it opens on the right tab
          weekId: MealPlanKeys.currentWeekId(), // kept for backwards compat
          focusDayKey: MealPlanKeys.todayKey(),
        ),
      ),
    );
  }

  void _openPlanSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedMealPlansScreen()),
    );
  }

  void _openBuilder() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanBuilderScreen(
          weekId: MealPlanKeys.currentWeekId(),
          entry: MealPlanBuilderEntry.choose,
          initialSelectedDayKey: MealPlanKeys.todayKey(),
        ),
      ),
    );
  }

  // ----------------------------
  // UI
  // ----------------------------
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in')));
    }

    final selectedDays = _weekdays();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const SizedBox.shrink(), // ✅ no title
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 12,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasProgram
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                  children: [
                    _ProgramStatusCard(
                      brandDark: _brandDark,
                      brandTeal: _brandTeal,
                      hasActiveProgram: true,
                      title: _planTitle(),
                      subtitle: 'Meals will follow this weekly schedule.',
                      statusText: _statusText(),
                      weekdaysSelected: selectedDays,
                      onPrimary: _openMealPlan,
                      primaryLabel: 'VIEW MEAL PLAN',
                      onSecondary: _openPlanSettings,
                      secondaryLabel: 'EDIT PLAN',
                    ),
                  ],
                )
              : _NoProgrammeState(
                  brandDark: _brandDark,
                  brandTeal: _brandTeal,
                  onBuild: _openBuilder,
                ),
    );
  }
}

// -------------------------------------------------------
// ✅ UI: No programme empty state
// -------------------------------------------------------
class _NoProgrammeState extends StatelessWidget {
  final Color brandDark;
  final Color brandTeal;
  final VoidCallback onBuild;

  const _NoProgrammeState({
    required this.brandDark,
    required this.brandTeal,
    required this.onBuild,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: brandTeal.withOpacity(0.14),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                color: brandDark,
                size: 44,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Create your meal programme',
              style: TextStyle(
                fontSize: 24,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: brandDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Choose which days you want to plan for, then start adding meals for each day.',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Colors.black.withOpacity(0.62),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onBuild,
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandTeal,
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'BUILD MY MEAL PROGRAMME',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _WhatYouGetCard(brandDark: brandDark),
          ],
        ),
      ),
    );
  }
}

class _WhatYouGetCard extends StatelessWidget {
  final Color brandDark;
  const _WhatYouGetCard({required this.brandDark});

  Widget _row(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: brandDark.withOpacity(0.9)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: Colors.black.withOpacity(0.70),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, 10),
            blurRadius: 22,
            color: Color.fromRGBO(0, 0, 0, 0.06),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT YOU’LL GET',
            style: TextStyle(
              color: brandDark,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          _row(Icons.view_week_rounded, 'A weekly view of your planned days'),
          const SizedBox(height: 10),
          _row(Icons.restaurant_menu_rounded, 'Add meals and snacks per day'),
          const SizedBox(height: 10),
          _row(Icons.shopping_cart_outlined, 'Generate a shopping list anytime'),
        ],
      ),
    );
  }
}

// -------------------------------------------------------
// UI: Program Status Card (schedule-only)
// -------------------------------------------------------
class _ProgramStatusCard extends StatelessWidget {
  final Color brandDark;
  final Color brandTeal;

  final bool hasActiveProgram;
  final String title;
  final String subtitle;
  final String statusText;

  /// Mon=1..Sun=7 (from program.weekdays)
  final List<int> weekdaysSelected;

  final VoidCallback onPrimary;
  final String primaryLabel;

  final VoidCallback? onSecondary;
  final String? secondaryLabel;

  const _ProgramStatusCard({
    required this.brandDark,
    required this.brandTeal,
    required this.hasActiveProgram,
    required this.title,
    required this.subtitle,
    required this.statusText,
    required this.weekdaysSelected,
    required this.onPrimary,
    required this.primaryLabel,
    required this.onSecondary,
    required this.secondaryLabel,
  });

  String _weekdayShort(int weekday) {
    switch (weekday) {
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

  @override
  Widget build(BuildContext context) {
    final set = weekdaysSelected.toSet();

    final pillBg = hasActiveProgram
        ? (set.isEmpty
            ? Colors.black.withOpacity(0.06)
            : brandTeal.withOpacity(0.14))
        : Colors.black.withOpacity(0.06);

    final pillFg = hasActiveProgram
        ? (set.isEmpty ? Colors.black.withOpacity(0.55) : brandTeal)
        : Colors.black.withOpacity(0.55);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + status pill
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: brandDark,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusText.toUpperCase(),
                  style: TextStyle(
                    color: pillFg,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.black.withOpacity(0.62),
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),

          const SizedBox(height: 14),

          Text(
            'WEEKLY SCHEDULE',
            style: TextStyle(
              color: brandDark,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              for (int w = 1; w <= 7; w++) ...[
                Expanded(
                  child: _WeekdayChip(
                    label: _weekdayShort(w),
                    selected: set.contains(w),
                    brandDark: brandDark,
                  ),
                ),
                if (w != 7) const SizedBox(width: 8),
              ]
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                backgroundColor: brandTeal,
                shape: const StadiumBorder(),
              ),
              child: Text(
                primaryLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),

          if (onSecondary != null &&
              (secondaryLabel ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onSecondary,
                style: OutlinedButton.styleFrom(
                  foregroundColor: brandTeal,
                  side: BorderSide(color: brandTeal, width: 2),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  secondaryLabel!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekdayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color brandDark;

  const _WeekdayChip({
    required this.label,
    required this.selected,
    required this.brandDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? brandDark : Colors.white;
    final fg = selected ? Colors.white : brandDark.withOpacity(0.75);
    final border = selected ? Colors.transparent : brandDark.withOpacity(0.12);

    return Container(
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
    );
  }
}

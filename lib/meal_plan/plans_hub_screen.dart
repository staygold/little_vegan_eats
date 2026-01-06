// lib/meal_plan/plans_hub_screen.dart
import 'dart:async';
import 'dart:ui' show FontVariation;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_repository.dart';
import 'core/meal_plan_keys.dart';
import 'builder/meal_plan_builder_screen.dart';
import 'widgets/today_meal_plan_section.dart';
import 'meal_plan_screen.dart';

import 'saved_meal_plans_screen.dart';
import 'saved_meal_plan_detail_screen.dart';

class PlansHubScreen extends StatefulWidget {
  const PlansHubScreen({super.key});

  @override
  State<PlansHubScreen> createState() => _PlansHubScreenState();
}

class _PlansHubScreenState extends State<PlansHubScreen> {
  static const Color _panelBg = Color(0xFFECF3F4);

  List<Map<String, dynamic>> _recipes = const [];
  bool _recipesLoading = true;

  StreamSubscription<User?>? _authFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  bool _loadingFavs = true;
  final Set<int> _favoriteIds = <int>{};

  // ✅ Active saved plan title listener (for active card title when sourced)
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _activePlanSub;
  String? _activePlanIdListening;
  String? _activeSavedPlanTitle;

  @override
  void initState() {
    super.initState();
    _loadRecipes();
    _listenToFavorites();
  }

  @override
  void dispose() {
    _authFavSub?.cancel();
    _favSub?.cancel();
    _activePlanSub?.cancel();
    super.dispose();
  }

  String? _uid() => FirebaseAuth.instance.currentUser?.uid;

  // ---------- DATE HELPERS ----------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _todayKey() => _dateKey(_dateOnly(DateTime.now()));
  String _weekId() => MealPlanKeys.currentWeekId();

  // ---------- RECIPES ----------

  Future<void> _loadRecipes() async {
    try {
      final list = await RecipeRepository.ensureRecipesLoaded();
      _recipes = list;
    } catch (_) {
      _recipes = const [];
    } finally {
      if (mounted) setState(() => _recipesLoading = false);
    }
  }

  // ---------- RECIPE FAVORITES ----------

  void _listenToFavorites() {
    _authFavSub?.cancel();
    _favSub?.cancel();

    setState(() {
      _loadingFavs = true;
      _favoriteIds.clear();
    });

    _authFavSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _favSub?.cancel();

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _loadingFavs = false;
          _favoriteIds.clear();
        });
        return;
      }

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites');

      _favSub = col.snapshots().listen(
        (snap) {
          final next = <int>{};
          for (final d in snap.docs) {
            final data = d.data();
            final raw = data['recipeId'];
            final id = (raw is int) ? raw : int.tryParse('$raw') ?? -1;
            if (id > 0) next.add(id);
          }

          if (!mounted) return;
          setState(() {
            _favoriteIds
              ..clear()
              ..addAll(next);
            _loadingFavs = false;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _loadingFavs = false;
            _favoriteIds.clear();
          });
        },
      );
    });
  }

  // ---------- FIRESTORE STREAMS ----------

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _weekStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPlansWeeks')
        .doc(_weekId())
        .snapshots();
  }

  Query<Map<String, dynamic>>? _createdPlansQuery() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedMealPlans')
        .orderBy('savedAt', descending: true)
        .limit(20);
  }

  // ---------- ACTIVE SAVED PLAN TITLE (LISTENER) ----------

  void _ensureActiveSavedPlanTitleListener(String? planId) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final id = (planId ?? '').trim();
    if (id.isEmpty) {
      _activePlanSub?.cancel();
      _activePlanSub = null;
      _activePlanIdListening = null;
      _activeSavedPlanTitle = null;
      return;
    }

    if (_activePlanIdListening == id) return;

    _activePlanSub?.cancel();
    _activePlanIdListening = id;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedMealPlans')
        .doc(id);

    _activePlanSub = ref.snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) {
        if (!mounted) return;
        setState(() => _activeSavedPlanTitle = null);
        return;
      }

      final t = (data['title'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() => _activeSavedPlanTitle = t.isNotEmpty ? t : null);
    });
  }

  // ---------- TITLE HELPERS ----------

  String _cleanTitleForCard(String? raw, {required bool isDay}) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty ||
        s.toLowerCase().contains('week_generated') ||
        s.toLowerCase().contains('generated')) {
      return isDay ? 'My Day Plan' : 'My Week Plan';
    }
    return s;
  }

  String _activeSlotTitle(
    Map<String, dynamic> weekData, {
    required bool isDayPlan,
  }) {
    final fromSaved = (_activeSavedPlanTitle ?? '').trim();
    if (fromSaved.isNotEmpty) {
      return _cleanTitleForCard(fromSaved, isDay: isDayPlan);
    }

    final cfg = weekData['config'];
    if (cfg is Map) {
      final s = (cfg['title'] ?? '').toString().trim();
      if (s.isNotEmpty) return _cleanTitleForCard(s, isDay: isDayPlan);
    }

    final t = (weekData['title'] ?? '').toString().trim();
    if (t.isNotEmpty) return _cleanTitleForCard(t, isDay: isDayPlan);

    return isDayPlan ? 'My Day Plan' : 'My Week Plan';
  }

  // ---------- PLAN PRESENCE (ROBUST) ----------

  bool _mapHasAnyEntries(Map<String, dynamic> m) {
    for (final v in m.values) {
      if (v is Map && v.isNotEmpty) return true;
      if (v != null) return true;
    }
    return false;
  }

  bool _hasAnyPlanData({
    required Map<String, dynamic> weekData,
    required bool isDayPlan,
  }) {
    final days = weekData['days'];
    if (days is! Map) return false;

    if (isDayPlan) {
      final tk = _todayKey();
      final today = (days[tk] is Map) ? Map<String, dynamic>.from(days[tk] as Map) : <String, dynamic>{};
      return today.isNotEmpty && _mapHasAnyEntries(today);
    }

    // Week plan: any non-empty day map counts
    for (final entry in days.entries) {
      final v = entry.value;
      if (v is Map && v.isNotEmpty) {
        final m = Map<String, dynamic>.from(v);
        if (_mapHasAnyEntries(m)) return true;
      }
    }
    return false;
  }

  // Robust int parsing for Firestore
  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  // ---------- NAV ----------

  void _openTodayPlan() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MealPlanScreen(
        weekId: _weekId(),
        focusDayKey: _todayKey(),
        initialViewMode: MealPlanViewMode.today,
      ),
    ));
  }

  void _openWeekPlanOnToday() {
    // Week view, focused on today tab
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MealPlanScreen(
        weekId: _weekId(),
        focusDayKey: _todayKey(),
        initialViewMode: MealPlanViewMode.week,
      ),
    ));
  }

  void _openAllCreatedPlans() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedMealPlansScreen()),
    );
  }

  void _openCreatedPlanDetail(String id) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SavedMealPlanDetailScreen(savedPlanId: id),
    ));
  }

  void _openBuilder() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MealPlanBuilderScreen()),
    );
  }

  // ---------- STYLES ----------

  TextStyle _hubTitleStyle(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: const Color(0xFF005A4F),
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 1.0,
      height: 1.0,
    );
  }

  // ---------- YOUR MEAL PLANS SECTION (ACTIVE + 2 INACTIVE + CTA) ----------

  Widget _yourMealPlansSection({
    required BuildContext context,
    required TextStyle titleStyle,
    required ThemeData theme,
    required String? activePlanId,
    required String activeTitle,
    required bool isDayPlan,
    required bool hasActivePlanData,
    required VoidCallback onOpenActiveFullPlan,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> savedDocs,
  }) {
    // Inactive = everything except active saved plan id
    final inactiveDocs = savedDocs.where((d) => d.id != activePlanId).toList();
    final displayInactive = inactiveDocs.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 4, 10),
          child: Row(
            children: [
              Expanded(child: Text('YOUR MEAL PLANS', style: titleStyle)),
              TextButton(
                onPressed: _openAllCreatedPlans,
                child: Text(
                  'VIEW ALL',
                  style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
                    color: const Color(0xFF005A4F),
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ✅ ACTIVE SLOT
        _ActivePlanListCard(
          title: hasActivePlanData ? activeTitle : 'No active plan yet',
          subtitle: hasActivePlanData ? 'Active Plan' : 'Tap to build one',
          isDay: isDayPlan,
          isEmpty: !hasActivePlanData,
          onTap: hasActivePlanData ? onOpenActiveFullPlan : _openBuilder,
        ),

        if (displayInactive.isNotEmpty)
          Column(
            children: [
              for (final doc in displayInactive)
                _PlanListCard(
                  doc: doc,
                  onTap: () => _openCreatedPlanDetail(doc.id),
                ),
            ],
          ),

        // ✅ CREATE NEW PLAN CTA
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _openBuilder,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF32998D),
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                elevation: 2,
              ),
              child: const Text(
                'CREATE NEW PLAN',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final weekStream = _weekStream();
    final savedQuery = _createdPlansQuery();
    final theme = Theme.of(context);
    final titleStyle = _hubTitleStyle(context);

    if (_recipesLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (weekStream == null) {
      return const Scaffold(
        backgroundColor: _panelBg,
        body: Center(child: Text('Log in to see your plans')),
      );
    }

    const topRadius = BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(20),
    );
    final mealPlanPanelBg = const Color(0xFF005A4F);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: weekStream,
      builder: (context, weekSnap) {
        if (weekSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: _panelBg,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final weekData = weekSnap.data?.data() ?? <String, dynamic>{};
        final days = weekData['days'];
        final todayKey = _todayKey();

        final Map<String, dynamic> todayRaw =
            (days is Map && days[todayKey] is Map)
                ? Map<String, dynamic>.from(days[todayKey] as Map)
                : <String, dynamic>{};

        final cfg = weekData['config'];
        final daysToPlan = (cfg is Map) ? _asInt(cfg['daysToPlan']) : null;
        final isDayPlan = (daysToPlan ?? 0) == 1;

        final activePlanId = (cfg is Map) ? cfg['sourcePlanId']?.toString() : null;

        // ✅ Keep active title accurate if sourced from saved plan
        _ensureActiveSavedPlanTitleListener(activePlanId);

        final activeTitle = _activeSlotTitle(weekData, isDayPlan: isDayPlan);

        // ✅ Whether there is ANY plan content (even if not saved)
        final hasActivePlanData = _hasAnyPlanData(
          weekData: weekData,
          isDayPlan: isDayPlan,
        );

        // ✅ Routing
        final VoidCallback onOpenFullPlan =
            isDayPlan ? _openTodayPlan : _openWeekPlanOnToday;

        // ✅ If we can't query saved plans (not logged in), just render top section.
        if (savedQuery == null) {
          return Scaffold(
            backgroundColor: _panelBg,
            body: ListView(
              padding: EdgeInsets.zero,
              children: [
                Container(
                  color: mealPlanPanelBg,
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: _panelBg,
                    shape: const RoundedRectangleBorder(borderRadius: topRadius),
                    clipBehavior: Clip.antiAlias,
                    child: TodayMealPlanSection(
                      todayRaw: todayRaw,
                      recipes: _recipes,
                      favoriteIds: _favoriteIds,
                      heroTopText: "TODAY'S",
                      heroBottomText: "MEAL PLAN",
                      homeAccordion: true,
                      homeAlwaysExpanded: true,
                      onBuildMealPlan: _openBuilder,
                      onOpenMealPlan: onOpenFullPlan,
                      onOpenToday: null,
                      onOpenWeek: null,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: savedQuery.snapshots(),
          builder: (context, savedSnap) {
            final savedDocs = savedSnap.data?.docs ?? const [];

            // ✅ HIDE ENTIRE "YOUR MEAL PLANS" SECTION WHEN NOTHING EXISTS
            final hasAnySavedPlans = savedDocs.isNotEmpty;
            final showYourMealPlans = hasActivePlanData || hasAnySavedPlans;

            return Scaffold(
              backgroundColor: _panelBg,
              body: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Container(
                    color: mealPlanPanelBg,
                    padding: const EdgeInsets.only(top: 12),
                    child: Material(
                      color: _panelBg,
                      shape: const RoundedRectangleBorder(borderRadius: topRadius),
                      clipBehavior: Clip.antiAlias,
                      child: TodayMealPlanSection(
                        todayRaw: todayRaw,
                        recipes: _recipes,
                        favoriteIds: _favoriteIds,
                        heroTopText: "TODAY'S",
                        heroBottomText: "MEAL PLAN",
                        homeAccordion: true,
                        homeAlwaysExpanded: true,
                        onBuildMealPlan: _openBuilder,
                        onOpenMealPlan: onOpenFullPlan,
                        onOpenToday: null,
                        onOpenWeek: null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  if (showYourMealPlans)
                    _yourMealPlansSection(
                      context: context,
                      titleStyle: titleStyle,
                      theme: theme,
                      activePlanId: activePlanId,
                      activeTitle: activeTitle,
                      isDayPlan: isDayPlan,
                      hasActivePlanData: hasActivePlanData,
                      onOpenActiveFullPlan: onOpenFullPlan,
                      savedDocs: savedDocs,
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// ✅ Active row styled like other plan cards, but NO manage/remove menu.
class _ActivePlanListCard extends StatelessWidget {
  const _ActivePlanListCard({
    required this.title,
    required this.subtitle,
    required this.isDay,
    required this.isEmpty,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isDay;
  final bool isEmpty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flagText = isDay ? 'DAY' : 'WEEK';
    final flagColor = isDay ? Colors.blue.shade50 : Colors.teal.shade50;
    final flagTextColor = isDay ? Colors.blue.shade700 : Colors.teal.shade700;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF32998D), width: 2),
      ),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF044246),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isEmpty ? Colors.grey[600] : const Color(0xFF32998D),
              ),
            ),
            const SizedBox(width: 8),
            if (!isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: flagColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  flagText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: flagTextColor,
                  ),
                ),
              ),
          ],
        ),
        trailing: isEmpty
            ? const Icon(Icons.add_circle_outline, color: Color(0xFF32998D))
            : const Icon(Icons.check_circle, color: Color(0xFF32998D)),
        onTap: onTap,
      ),
    );
  }
}

class _PlanListCard extends StatelessWidget {
  const _PlanListCard({
    required this.doc,
    required this.onTap,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onTap;

  String _cleanTitle(String? raw, bool isDay) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty ||
        s.toLowerCase().contains('week_generated') ||
        s.toLowerCase().contains('generated')) {
      return isDay ? 'My Day Plan' : 'My Week Plan';
    }
    return s;
  }

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final typeRaw = (data['type'] ?? 'Custom').toString();
    bool isDay = typeRaw.toLowerCase().contains('day');

    if (!isDay && data['days'] is Map) {
      final map = data['days'] as Map;
      if (map.length == 1) isDay = true;
    }

    final title = _cleanTitle(data['title'], isDay);
    final savedAt = _formatDate(data['savedAt']);

    final flagText = isDay ? 'DAY' : 'WEEK';
    final flagColor = isDay ? Colors.blue.shade50 : Colors.teal.shade50;
    final flagTextColor = isDay ? Colors.blue.shade700 : Colors.teal.shade700;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Row(
          children: [
            Text(
              'Created $savedAt',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: flagColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                flagText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: flagTextColor,
                ),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

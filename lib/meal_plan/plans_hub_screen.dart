// lib/meal_plan/plans_hub_screen.dart
import 'dart:async';
import 'dart:ui' show FontVariation;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_repository.dart';
import '../theme/app_theme.dart';

// ✅ same weekId logic as Home/MealPlan
import 'core/meal_plan_keys.dart';

// ✅ use the centralised meal plan repo + controller to auto-populate
import 'core/meal_plan_repository.dart';
import 'core/meal_plan_controller.dart';

// ✅ shared UI (you already updated this)
import 'widgets/today_meal_plan_section.dart';

// ✅ screens
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

  MealPlanController? _mealCtrl;
  bool _bootstrappedWeek = false;

  // ✅ Favourites (read-only, matches Home)
  StreamSubscription<User?>? _authFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  bool _loadingFavs = true;
  final Set<int> _favoriteIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadRecipesAndBootstrap();
    _listenToFavorites();
  }

  @override
  void dispose() {
    _authFavSub?.cancel();
    _favSub?.cancel();

    _mealCtrl?.stop();
    _mealCtrl = null;

    super.dispose();
  }

  // ---------- DATE HELPERS (CLONE HOME) ----------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _todayKey() => _dateKey(_dateOnly(DateTime.now()));

  String _weekId() => MealPlanKeys.currentWeekId();

  // ---------- RECIPES + BOOTSTRAP (CLONE HOME) ----------

  Future<void> _loadRecipesAndBootstrap() async {
    try {
      final list = await RecipeRepository.ensureRecipesLoaded();
      _recipes = list;
    } catch (_) {
      _recipes = const [];
    } finally {
      if (mounted) setState(() => _recipesLoading = false);
    }

    await _bootstrapMealPlanIfNeeded();
  }

  Future<void> _bootstrapMealPlanIfNeeded() async {
    if (!mounted) return;
    if (_bootstrappedWeek) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_recipes.isEmpty) return;

    _mealCtrl ??= MealPlanController(
      auth: FirebaseAuth.instance,
      repo: MealPlanRepository(FirebaseFirestore.instance),
      initialWeekId: _weekId(),
    );

    _mealCtrl!.start();
    _bootstrappedWeek = true;

    try {
      await _mealCtrl!.ensurePlanPopulated(recipes: _recipes);
    } catch (_) {
      // silent fail
    }
  }

  // ---------- ✅ FAVORITES (read-only) ----------

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

  // ---------- FIRESTORE STREAM (CLONE HOME PATH) ----------

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _weekStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    // ✅ IMPORTANT: this matches Home exactly
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPlansWeeks')
        .doc(_weekId())
        .snapshots();
  }

  // ---------- SAVED PLANS QUERY (CLONE SavedMealPlansScreen) ----------

  Query<Map<String, dynamic>>? _savedPlansQuery() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedMealPlans')
        .orderBy('savedAt', descending: true)
        .limit(3);
  }

  // ---------- NAV ----------

  void _openTodayPlan() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanScreen(
          weekId: _weekId(),
          focusDayKey: _todayKey(),
        ),
      ),
    );
  }

  void _openWeekPlan() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanScreen(
          weekId: _weekId(),
        ),
      ),
    );
  }

  void _openSavedPlans() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedMealPlansScreen()),
    );
  }

  void _openSavedPlanDetail(String savedPlanId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedMealPlanDetailScreen(savedPlanId: savedPlanId),
      ),
    );
  }

  TextStyle _hubTitleStyle(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 1.0,
      height: 1.0,
    );
  }

  Widget _savedPlansPreview(BuildContext context) {
    final q = _savedPlansQuery();
    if (q == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snap.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Could not load saved meal plans'),
          );
        }

        final docs = snap.data?.docs ?? [];

        // ✅ Placeholder when none saved
        if (docs.isEmpty) {
          return Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: const ListTile(
              leading: Icon(Icons.bookmark_outline),
              title: Text(
                'No saved meal plans yet',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Save a day or week plan to see it here.'),
            ),
          );
        }

        return Column(
          children: [
            for (final doc in docs)
              _SavedPlanCard(
                doc: doc,
                onTap: () => _openSavedPlanDetail(doc.id),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekStream = _weekStream();
    final theme = Theme.of(context);
    final titleStyle = _hubTitleStyle(context);

    if (_recipesLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (weekStream == null) {
      return const Scaffold(
        backgroundColor: _panelBg,
        body: Center(child: Text('Log in to see your plans')),
      );
    }

    // ✅ Rounded top corners for the inner panel (same as Home)
    const topRadius = BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(20),
    );

    // ✅ Outer wrapper background (green band like Home)
    final mealPlanPanelBg = AppColors.brandDark;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: weekStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: _panelBg,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data?.data() ?? <String, dynamic>{};
        final days = data['days'];
        final todayKey = _todayKey();

        // ✅ EXACT same extraction as Home
        final Map<String, dynamic> todayRaw =
            (days is Map && days[todayKey] is Map)
                ? Map<String, dynamic>.from(days[todayKey] as Map)
                : <String, dynamic>{};

        return Scaffold(
          backgroundColor: _panelBg,
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              // ✅ 1) TODAY MEAL PLAN (same path + extraction as Home)
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

                    // ✅ same Home accordion styling
                    homeAccordion: true,

                    // ✅ Plans hub: keep all sections expanded
                    homeAlwaysExpanded: true,

                    onOpenToday: _openTodayPlan,
                    onOpenWeek: _openWeekPlan,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // ✅ 2) SAVED MEAL PLANS (use same cards as SavedMealPlansScreen, show 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 4, 10),
                child: Row(
                  children: [
                    Expanded(child: Text('SAVED MEAL PLANS', style: titleStyle)),
                    TextButton(
                      onPressed: _openSavedPlans,
                      child: Text(
                        'VIEW ALL',
                        style:
                            (theme.textTheme.titleMedium ?? const TextStyle())
                                .copyWith(
                          color: AppColors.brandDark,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              _savedPlansPreview(context),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _SavedPlanCard extends StatelessWidget {
  const _SavedPlanCard({
    required this.doc,
    required this.onTap,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();

    final title = (data['title'] ?? '').toString().trim();
    final type = (data['type'] ?? '').toString().trim(); // day|week

    final display = title.isNotEmpty ? title : 'Saved meal plan';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ListTile(
        title: Text(
          display,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: type.isNotEmpty ? Text('Type: $type') : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

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

// ✅ shared UI
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

  // ---------- DATE HELPERS ----------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _todayKey() => _dateKey(_dateOnly(DateTime.now()));

  String _weekId() => MealPlanKeys.currentWeekId();

  // ---------- RECIPES + BOOTSTRAP ----------

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
      // silent
    }
  }

  // ---------- FAVORITES ----------

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

  // ---------- FIRESTORE STREAM ----------

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

  // ---------- FAVOURITE PLANS QUERY ----------

  Query<Map<String, dynamic>>? _favouritePlansQuery() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedMealPlans') // backend unchanged
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
        builder: (_) => MealPlanScreen(weekId: _weekId()),
      ),
    );
  }

  void _openFavouritePlans() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedMealPlansScreen()),
    );
  }

  void _openFavouritePlanDetail(String id) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedMealPlanDetailScreen(savedPlanId: id),
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

  // ---------- FAVOURITE PLANS SECTION ----------

  Widget _favouritePlansSection(
    BuildContext context,
    TextStyle titleStyle,
    ThemeData theme,
  ) {
    final q = _favouritePlansQuery();
    if (q == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final waiting = snap.connectionState == ConnectionState.waiting;
        final hasError = snap.hasError;
        final docs = snap.data?.docs ?? const [];

        final hasAny = docs.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 4, 20),
              child: Row(
                children: [
                  Expanded(
                    child:
                        Text('FAVOURITE MEAL PLANS', style: titleStyle),
                  ),
                  if (hasAny)
                    TextButton(
                      onPressed: _openFavouritePlans,
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
            if (waiting)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (hasError)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Could not load favourite meal plans'),
              )
            else if (!hasAny)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: const ListTile(
                  leading: Icon(Icons.favorite_border),
                  title: Text(
                    'No favourite meal plans yet',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Favourite a day or week plan to see it here.',
                  ),
                ),
              )
            else
              Column(
                children: [
                  for (final doc in docs)
                    _FavouritePlanCard(
                      doc: doc,
                      onTap: () => _openFavouritePlanDetail(doc.id),
                    ),
                ],
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

    const topRadius = BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(20),
    );

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

        final Map<String, dynamic> todayRaw =
            (days is Map && days[todayKey] is Map)
                ? Map<String, dynamic>.from(days[todayKey] as Map)
                : <String, dynamic>{};

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
                  shape: const RoundedRectangleBorder(
                    borderRadius: topRadius,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: TodayMealPlanSection(
                    todayRaw: todayRaw,
                    recipes: _recipes,
                    favoriteIds: _favoriteIds,
                    heroTopText: "TODAY'S",
                    heroBottomText: "MEAL PLAN",
                    homeAccordion: true,
                    homeAlwaysExpanded: true,
                    onOpenToday: _openTodayPlan,
                    onOpenWeek: _openWeekPlan,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              _favouritePlansSection(context, titleStyle, theme),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _FavouritePlanCard extends StatelessWidget {
  const _FavouritePlanCard({
    required this.doc,
    required this.onTap,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();

    final title = (data['title'] ?? '').toString().trim();
    final type = (data['type'] ?? '').toString().trim();

    final display = title.isNotEmpty ? title : 'Favourite meal plan';

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

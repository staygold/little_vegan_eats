// lib/home/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../recipes/recipe_repository.dart';
import '../recipes/recipe_search_screen.dart';

// ✅ SAME weekId logic as meal plan
import '../meal_plan/core/meal_plan_keys.dart';

// ✅ Centralised review prompt
import '../meal_plan/core/meal_plan_review_service.dart';

// ✅ use the centralised meal plan repo + controller to auto-populate
import '../meal_plan/core/meal_plan_repository.dart';
import '../meal_plan/core/meal_plan_controller.dart';

// ✅ home recipe rail for WPRM collections
import '../recipes/home_collection_rail.dart';

// ✅ shared meal plan UI (REUSE)
import '../meal_plan/widgets/today_meal_plan_section.dart';

// ✅ reusable top search section
import '../shared/home_search_section.dart';

import '../theme/app_theme.dart';

// ✅ IMPORTANT: so HomeScreen can push MealPlanScreen without named routes
import '../meal_plan/meal_plan_screen.dart';

// ✅ Latest recipes page
import '../recipes/latest_recipes_page.dart';

// ✅ Popular recipes page
import '../recipes/popular_recipes_page.dart';

// ✅ Course page plumbing (same as RecipeHub)
import '../recipes/recipes_bootstrap_gate.dart';
import '../recipes/course_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = true;

  MealPlanController? _mealCtrl;
  bool _bootstrappedWeek = false;

  // ✅ Favourites (read-only, matches RecipeListScreen)
  StreamSubscription<User?>? _authFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  bool _loadingFavs = true;
  final Set<int> _favoriteIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadRecipesAndBootstrap();
    _listenToFavorites();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await MealPlanReviewService.checkAndPromptIfNeeded(context);
    });
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

  // ---------- RECIPES ----------

  Future<void> _loadRecipesAndBootstrap() async {
    try {
      _recipes = await RecipeRepository.ensureRecipesLoaded();
    } catch (_) {
      _recipes = [];
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
      // Silent fail
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

  // ---------- FIRESTORE STREAMS ----------

  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

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

  /// users/{uid}.adults[0].name → "Cat Dean" → "Cat"
  String? _extractFirstName(Map<String, dynamic> data) {
    final adults = data['adults'];
    if (adults is! List || adults.isEmpty) return null;

    final firstAdult = adults.first;
    if (firstAdult is! Map) return null;

    final name = (firstAdult['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.first : null;
  }

  // ---------- NAV ----------

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeSearchScreen(
          recipes: _recipes,
          favoriteIds: _favoriteIds,
        ),
      ),
    );
  }

  void _openTodayPlan(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanScreen(
          weekId: _weekId(),
          focusDayKey: _todayKey(),
        ),
      ),
    );
  }

  void _openWeekPlan(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanScreen(
          weekId: _weekId(),
        ),
      ),
    );
  }

  void _openLatest(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LatestRecipesPage(
          title: 'Latest recipes',
          recipes: _recipes,
          favoriteIds: _favoriteIds,
          limit: 20,
        ),
      ),
    );
  }

  void _openPopular(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PopularRecipesPage(
          title: 'Popular',
          recipes: _recipes,
          favoriteIds: _favoriteIds,
          limit: 50,
        ),
      ),
    );
  }

  // ✅ same plumbing as RecipeHubScreen
  void _openCourse(BuildContext context, String slug, String title, String subtitle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipesBootstrapGate(
          child: CoursePage(
            courseSlug: slug,
            title: title,
            subtitle: subtitle,
          ),
        ),
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final userDoc = _userDoc();
    final weekStream = _weekStream();

    if (_recipesLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (userDoc == null || weekStream == null) {
      return const Scaffold(
        body: Center(child: Text('Log in to see your home feed')),
      );
    }

    const railBg = Color(0xFFECF3F4);

    const topRadius = BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(20),
    );

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() ?? <String, dynamic>{};
        final firstName = _extractFirstName(userData);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: weekStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
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

            final mealPlanPanelBg = AppColors.brandDark;

            return Scaffold(
              backgroundColor: railBg,
              body: ListView(
                padding: EdgeInsets.zero,
                children: [
                  HomeSearchSection(
                    firstName: firstName,
                    showGreeting: true,
                    onSearchTap: () => _openSearch(context),
                    quickActions: [
                      QuickActionItem(
                        label: 'Latest',
                        asset: 'assets/images/icons/latest.svg',
                        onTap: () => _openLatest(context),
                      ),
                      QuickActionItem(
                        label: 'Popular',
                        asset: 'assets/images/icons/popular.svg',
                        onTap: () => _openPopular(context),
                      ),
                      QuickActionItem(
                        label: 'Mains',
                        asset: 'assets/images/icons/mains.svg',
                        onTap: () => _openCourse(
                          context,
                          'mains',
                          'Mains',
                          'Family meals that actually land',
                        ),
                      ),
                      QuickActionItem(
                        label: 'Snacks',
                        asset: 'assets/images/icons/snacks.svg',
                        onTap: () => _openCourse(
                          context,
                          'snacks',
                          'Snacks',
                          'Lunchbox + between-meal favourites',
                        ),
                      ),
                    ],
                  ),

                  Container(
                    color: mealPlanPanelBg,
                    padding: const EdgeInsets.only(top: 12),
                    child: Material(
                      color: railBg,
                      shape: const RoundedRectangleBorder(
                        borderRadius: topRadius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: TodayMealPlanSection(
                        todayRaw: todayRaw,
                        recipes: _recipes,
                        favoriteIds: _favoriteIds,
                        heroTopText: "HERE'S SOME IDEAS",
                        heroBottomText: "FOR TODAY",
                        homeAccordion: true,
                        onOpenToday: () => _openTodayPlan(context),
                        onOpenWeek: () => _openWeekPlan(context),
                      ),
                    ),
                  ),

                  Container(
                    color: railBg,
                    padding: const EdgeInsets.only(top: 0, bottom: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HomeCollectionRail(
                          title: '15 MINUTE MEALS',
                          collectionSlug: '15-minute-meals',
                          recipes: _recipes,
                          favoriteIds: _favoriteIds,
                        ),
                        const SizedBox(height: 12),
                        HomeCollectionRail(
                          title: 'FIRST FOODS',
                          collectionSlug: 'first-foods',
                          recipes: _recipes,
                          favoriteIds: _favoriteIds,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

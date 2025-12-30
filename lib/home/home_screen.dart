// lib/home/home_screen.dart
import 'dart:async';
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../recipes/recipe_repository.dart';

// ✅ SAME weekId logic as meal plan
import '../meal_plan/core/meal_plan_keys.dart';

// ✅ Centralised review prompt
import '../meal_plan/core/meal_plan_review_service.dart';

// ✅ NEW: use the centralised meal plan repo + controller to auto-populate
import '../meal_plan/core/meal_plan_repository.dart';
import '../meal_plan/core/meal_plan_controller.dart';

// ✅ NEW: home recipe rail for WPRM collections
import '../recipes/home_collection_rail.dart';

// ✅ NEW: shared meal plan UI + parsing
import '../meal_plan/widgets/today_meal_plan_section.dart';

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
    _listenToFavorites(); // ✅

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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final stream = _weekStream();

    if (_recipesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (stream == null) {
      return const Center(child: Text('Log in to see your meal plan'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snap.data?.data() ?? <String, dynamic>{};
        final days = data['days'];
        final todayKey = _todayKey();

        final Map<String, dynamic> todayRaw =
            (days is Map && days[todayKey] is Map)
                ? Map<String, dynamic>.from(days[todayKey] as Map)
                : <String, dynamic>{};

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            // ✅ Shared Today Meal Plan section (hero + bands + cards + button bar)
            TodayMealPlanSection(
              todayRaw: todayRaw,
              recipes: _recipes,
              favoriteIds: _favoriteIds,
              onOpenMealPlan: () => Navigator.of(context).pushNamed('/meal-plan'),
            ),

            // ✅ WPRM Collection rails
            Container(
              color: const Color(0xFFECF3F4),
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: HomeCollectionRail(
                title: '15 Minute Meals',
                collectionSlug: '15-minute-meals',
                recipes: _recipes,
                favoriteIds: _favoriteIds,
              ),
            ),
            Container(
              color: const Color(0xFFECF3F4),
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: HomeCollectionRail(
                title: 'First Foods',
                collectionSlug: 'first-foods',
                recipes: _recipes,
                favoriteIds: _favoriteIds,
              ),
            ),
          ],
        );
      },
    );
  }
}

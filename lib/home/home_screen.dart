// lib/home/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../recipes/recipe_repository.dart';
import '../recipes/recipe_search_screen.dart';

import '../meal_plan/core/meal_plan_keys.dart';
import '../meal_plan/core/meal_plan_review_service.dart';
import '../meal_plan/builder/meal_plan_builder_screen.dart';
import '../recipes/home_collection_rail.dart';
import '../meal_plan/widgets/today_meal_plan_section.dart';
import '../shared/home_search_section.dart';
import '../theme/app_theme.dart';
import '../meal_plan/meal_plan_screen.dart';
import '../recipes/latest_recipes_page.dart';
import '../recipes/popular_recipes_page.dart';
import '../recipes/recipes_bootstrap_gate.dart';

// ✅ CHANGED: Import RecipeListPage instead of CoursePage
import '../recipes/recipe_list_page.dart';

// ✅ family repo source of truth
import '../recipes/family_profile_repository.dart';
import '../recipes/family_profile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = true;

  // Favourites
  StreamSubscription<User?>? _authFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  final Set<int> _favoriteIds = <int>{};

  // ✅ family repo
  final FamilyProfileRepository _familyRepo = FamilyProfileRepository();

  @override
  void initState() {
    super.initState();
    _loadRecipes();
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
    super.dispose();
  }

  // ---------- DATE HELPERS ----------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// ✅ After 8pm, "today" becomes tomorrow (home UX rule).
  String _effectiveHomeDayKey() {
    final now = DateTime.now();
    final base = _dateOnly(now);
    final effective = now.hour >= 20 ? base.add(const Duration(days: 1)) : base;
    return _dateKey(effective);
  }

  // ---------- RECIPES ----------

  Future<void> _loadRecipes() async {
    try {
      _recipes = await RecipeRepository.ensureRecipesLoaded();
    } catch (_) {
      _recipes = [];
    } finally {
      if (mounted) setState(() => _recipesLoading = false);
    }
  }

  // ---------- FAVORITES ----------

  void _listenToFavorites() {
    _authFavSub?.cancel();
    _favSub?.cancel();

    setState(() {
      _favoriteIds.clear();
    });

    _authFavSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _favSub?.cancel();

      if (user == null) {
        if (!mounted) return;
        setState(() {
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
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _favoriteIds.clear();
          });
        },
      );
    });
  }

  // ---------- FIRESTORE STREAMS (Programs + Days) ----------

  /// users/{uid}/mealPlan/settings
  DocumentReference<Map<String, dynamic>>? _programSettingsDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPlan')
        .doc('settings');
  }

  /// users/{uid}/mealPrograms/{programId}/mealProgramDays/{dayKey}
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _programDayStream({
    required String programId,
    required String dayKey,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPrograms')
        .doc(programId)
        .collection('mealProgramDays')
        .doc(dayKey)
        .snapshots();
  }

  /// ✅ users/{uid}/mealAdhocDays/{dayKey}
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _adhocDayStream({
    required String dayKey,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealAdhocDays')
        .doc(dayKey)
        .snapshots();
  }

  Map<String, dynamic> _slotsFromDayDoc(Map<String, dynamic> dayData) {
    final rawSlots = dayData['slots'];
    return (rawSlots is Map)
        ? Map<String, dynamic>.from(rawSlots)
        : <String, dynamic>{};
  }

  // ✅ first name from FamilyProfile
  String? _firstNameFromFamily(FamilyProfile fam) {
    if (fam.adults.isEmpty) return null;
    final name = fam.adults.first.name.trim();
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

  void _openBuilder(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanBuilderScreen(
          weekId: MealPlanKeys.currentWeekId(),
        ),
      ),
    );
  }

  void _openAdhocBuilder(BuildContext context, String dayKey) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanBuilderScreen(
          weekId: MealPlanKeys.weekIdForDate(
            MealPlanKeys.parseDayKey(dayKey) ?? DateTime.now(),
          ),
          entry: MealPlanBuilderEntry.adhocDay,
          initialSelectedDayKey: dayKey,
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

  // ✅ UPDATED: Use RecipeListPage here
  void _openCourse(
    BuildContext context,
    String slug,
    String title,
    String subtitle,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipesBootstrapGate(
          child: RecipeListPage(
            initialCourseSlug: slug,
            lockCourse: true,
            titleOverride: title.toUpperCase(),
          ),
        ),
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_recipesLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ✅ auth guard
    if (FirebaseAuth.instance.currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Log in to see your home feed')),
      );
    }

    final settingsDoc = _programSettingsDoc();
    if (settingsDoc == null) {
      return const Scaffold(
        body: Center(child: Text('Log in to see your home feed')),
      );
    }

    const railBg = Color(0xFFECF3F4);

    const topRadius = BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(20),
    );

    final effectiveDayKey = _effectiveHomeDayKey();

    return StreamBuilder<FamilyProfile>(
      stream: _familyRepo.watchFamilyProfile(),
      builder: (context, famSnap) {
        final family = famSnap.data;
        final firstName = (family != null) ? _firstNameFromFamily(family) : null;

        final childNames = family?.children.map((c) => c.name).toList() ?? [];

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: settingsDoc.snapshots(),
          builder: (context, settingsSnap) {
            final settings = settingsSnap.data?.data() ?? <String, dynamic>{};

            final activeProgramId =
                (settings['activeProgramId'] ?? '').toString().trim();

            // ✅ If no program at all
            if (activeProgramId.isEmpty) {
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
                      color: AppColors.brandDark,
                      padding: const EdgeInsets.only(top: 12),
                      child: Material(
                        color: railBg,
                        shape: const RoundedRectangleBorder(
                          borderRadius: topRadius,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: TodayMealPlanSection(
                          todayRaw: const <String, dynamic>{},
                          recipes: _recipes,
                          favoriteIds: _favoriteIds,
                          childNames: childNames,
                          heroTopText: "HERE'S SOME IDEAS",
                          heroBottomText: "FOR TODAY",
                          homeAccordion: true,
                          onOpenWeek: null,
                          onOpenMealPlan: null,
                          onOpenToday: null,
                          onBuildMealPlan: () => _openBuilder(context),
                          programmeActive: false,
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
            }

            // ✅ Program exists.
            final adhocStream = _adhocDayStream(dayKey: effectiveDayKey);
            final programStream = _programDayStream(
              programId: activeProgramId,
              dayKey: effectiveDayKey,
            );

            if (adhocStream == null || programStream == null) {
              return const Scaffold(
                body: Center(child: Text('Log in to see your home feed')),
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: adhocStream,
              builder: (context, adhocSnap) {
                final adhocData = adhocSnap.data?.data();
                final adhocSlots = adhocData == null
                    ? <String, dynamic>{}
                    : _slotsFromDayDoc(adhocData);

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: programStream,
                  builder: (context, progSnap) {
                    final progData = progSnap.data?.data();
                    final progSlots = progData == null
                        ? <String, dynamic>{}
                        : _slotsFromDayDoc(progData);

                    final bool adhocExists = adhocSnap.data?.exists == true;
                    final bool programDayExists = progSnap.data?.exists == true;

                    final Map<String, dynamic> effectiveSlots = adhocExists
                        ? adhocSlots
                        : (programDayExists ? progSlots : <String, dynamic>{});

                    final bool dayInProgramme = adhocExists || programDayExists;

                    final VoidCallback onOpenFullPlan = () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MealPlanScreen(
                            weekId: MealPlanKeys.weekIdForDate(
                              MealPlanKeys.parseDayKey(effectiveDayKey) ??
                                  DateTime.now(),
                            ),
                            focusDayKey: effectiveDayKey,
                          ),
                        ),
                      );
                    };

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
                            color: AppColors.brandDark,
                            padding: const EdgeInsets.only(top: 12),
                            child: Material(
                              color: railBg,
                              shape: const RoundedRectangleBorder(
                                borderRadius: topRadius,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: TodayMealPlanSection(
                                todayRaw: effectiveSlots,
                                recipes: _recipes,
                                favoriteIds: _favoriteIds,
                                childNames: childNames,
                                heroTopText: "HERE'S SOME IDEAS",
                                heroBottomText: "FOR TODAY",
                                homeAccordion: true,
                                onOpenWeek: onOpenFullPlan,
                                onOpenMealPlan: null,
                                onOpenToday: null,
                                onBuildMealPlan: () => _openBuilder(context),
                                programmeActive: true,
                                dayInProgramme: dayInProgramme,
                                onAddAdhocDay: () =>
                                    _openAdhocBuilder(context, effectiveDayKey),
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
          },
        );
      },
    );
  }
}

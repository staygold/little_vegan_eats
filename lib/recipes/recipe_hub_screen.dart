// lib/recipes/recipe_hub_screen.dart
import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../shared/home_search_section.dart';
import '../theme/app_theme.dart';
import '../utils/images.dart'; // upscaleJetpackImage

import 'recipe_repository.dart';
import 'recipe_search_screen.dart';

import 'recipes_bootstrap_gate.dart';
import 'recipe_list_page.dart';
import 'favorites_screen.dart';
import 'course_page.dart';

import 'recipe_detail_screen.dart';

class RecipeHubScreen extends StatefulWidget {
  const RecipeHubScreen({super.key});

  static const _courses = <_CourseLink>[
    _CourseLink(
      title: 'Breakfasts',
      slug: 'breakfast',
      iconAsset: 'assets/images/icons/courses/breakfasts.svg',
      subtitle: 'Something',
    ),
    _CourseLink(
      title: 'Mains',
      slug: 'mains',
      iconAsset: 'assets/images/icons/courses/mains.svg',
      subtitle: 'Something',
    ),
    _CourseLink(
      title: 'Snacks',
      slug: 'snacks',
      iconAsset: 'assets/images/icons/courses/snacks.svg',
      subtitle: 'Something',
    ),
    _CourseLink(
      title: 'Sweets',
      slug: 'sweets',
      iconAsset: 'assets/images/icons/courses/sweets.svg',
      subtitle: 'Something',
    ),
    _CourseLink(
      title: 'Sauces & Dips',
      slug: 'sauces-and-dips',
      iconAsset: 'assets/images/icons/courses/sauce.svg',
      subtitle: 'Something',
    ),
    _CourseLink(
      title: 'Staples',
      slug: 'staples',
      iconAsset: 'assets/images/icons/courses/staples.svg',
      subtitle: 'Something',
    ),
    _CourseLink(
      title: 'Drinks',
      slug: 'drinks',
      iconAsset: 'assets/images/icons/courses/drinks.svg',
      subtitle: 'Something',
    ),
  ];

  @override
  State<RecipeHubScreen> createState() => _RecipeHubScreenState();
}

class _RecipeHubScreenState extends State<RecipeHubScreen> {
  List<Map<String, dynamic>> _recipes = const [];
  bool _recipesLoading = true;

  StreamSubscription<User?>? _authFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;
  bool _loadingFavs = true;
  final Set<int> _favoriteIds = <int>{};

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
    super.dispose();
  }

  Future<void> _loadRecipes() async {
    setState(() => _recipesLoading = true);
    try {
      final list = await RecipeRepository.ensureRecipesLoaded();
      if (!mounted) return;
      setState(() {
        _recipes = list;
        _recipesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recipes = const [];
        _recipesLoading = false;
      });
    }
  }

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

  // ---------- FIELD HELPERS (match HomeCollectionRail) ----------

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return int.tryParse('${v ?? ''}');
  }

  int? _recipeId(dynamic raw) => _toInt(raw);

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      final s = (t['rendered'] as String).trim();
      if (s.isNotEmpty) {
        return s.replaceAll('&#038;', '&').replaceAll('&amp;', '&');
      }
    }
    final name = r['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return 'Untitled';
  }

  String? _str(dynamic v) =>
      (v is String && v.trim().isNotEmpty) ? v.trim() : null;

  String? _bestImageUrl(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map) {
      final rm = Map<String, dynamic>.from(recipe.cast<String, dynamic>());
      return _str(rm['image_url_full']) ??
          _str(rm['image_url']) ??
          _str(rm['image']) ??
          _str(rm['thumbnail_url']);
    }
    return _str(r['jetpack_featured_media_url']);
  }

  List<Map<String, dynamic>> _favouriteRecipes() {
    if (_recipes.isEmpty || _favoriteIds.isEmpty) return const [];
    final favs = <Map<String, dynamic>>[];
    for (final r in _recipes) {
      final id = _recipeId(r['id']);
      if (id != null && id > 0 && _favoriteIds.contains(id)) favs.add(r);
    }
    favs.sort((a, b) => _titleOf(a).compareTo(_titleOf(b)));
    return favs;
  }

  // ---------- STYLES ----------

  TextStyle _sectionTitleStyle(BuildContext context) {
    // ✅ same title style as favourites & rails
    final theme = Theme.of(context);
    return (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 1.0,
      height: 1.0,
    );
  }

  TextStyle _cardTextStyle(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: AppColors.textPrimary.withOpacity(0.85),
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
  }

  // ---------- NAV ----------

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openRecipe(Map<String, dynamic> recipe) {
    final id = _recipeId(recipe['id']);
    if (id == null || id <= 0) {
      _toast('Couldn’t open recipe (missing id)');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: id)),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeSearchScreen(
          recipes: _recipes,
          favoriteIds: _favoriteIds,
        ),
      ),
    );
  }

  void _openViewAllRecipes() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RecipesBootstrapGate(
          child: RecipeListPage(),
        ),
      ),
    );
  }

  void _openViewAllFavourites() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RecipesBootstrapGate(
          child: FavoritesScreen(),
        ),
      ),
    );
  }

  void _openCourse(String slug, String title, String subtitle) {
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
    const railBg = Color(0xFFECF3F4);
    const iconBoxBg = Color(0xFFD9E6E5);

    if (_recipesLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final favs = _favouriteRecipes();

    final titleStyle = _sectionTitleStyle(context);
    final cardTextStyle = _cardTextStyle(context);

    // favourites card proportions (match HomeCollectionRail)
    final screenW = MediaQuery.of(context).size.width;
    final favCardW = (screenW * 0.42).clamp(150.0, 190.0);
    const favRailH = 190.0;
    const favTitleBlockH = 60.0;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final requestW = (favCardW * dpr * 2.0).round();
    final requestH = ((favRailH - favTitleBlockH) * dpr * 2.0).round();
    final cacheW = requestW;
    final cacheH = requestH;

    return Scaffold(
      backgroundColor: railBg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          HomeSearchSection(
            firstName: null,
            showGreeting: false,
            onSearchTap: _openSearch,
            quickActions: [
              QuickActionItem(
                label: 'Latest',
                asset: 'assets/images/icons/latest.svg',
                onTap: _openViewAllRecipes,
              ),
              QuickActionItem(
                label: 'Popular',
                asset: 'assets/images/icons/popular.svg',
                onTap: _openViewAllRecipes,
              ),
              QuickActionItem(
                label: 'Mains',
                asset: 'assets/images/icons/mains.svg',
                onTap: () => _openCourse(
                  'mains',
                  'Mains',
                  'Family meals that actually land',
                ),
              ),
              QuickActionItem(
                label: 'Snacks',
                asset: 'assets/images/icons/snacks.svg',
                onTap: () => _openCourse(
                  'snacks',
                  'Snacks',
                  'Lunchbox + between-meal favourites',
                ),
              ),
            ],
          ),

          Container(
            color: railBg,
            padding: const EdgeInsets.only(top: 6, bottom: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --------------------
                // YOUR FAVOURITES
                // --------------------
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 4, 10),
                  child: Row(
                    children: [
                      Expanded(child: Text('YOUR FAVOURITES', style: titleStyle)),
                      TextButton(
                        onPressed: _openViewAllFavourites,
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

                if (_loadingFavs)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (favs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _EmptyStateCard(
                      text:
                          'Your favourites will show here.\nTap the ⭐ on any recipe to save it.',
                    ),
                  )
                else
                  SizedBox(
                    height: favRailH,
                    child: ListView.separated(
                      padding: const EdgeInsets.only(left: 16, right: 12),
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: favs.length.clamp(0, 12),
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final r = favs[i];
                        final id = _recipeId(r['id']);
                        final title = _titleOf(r);

                        final baseUrl = _bestImageUrl(r);
                        final imgUrl = baseUrl == null
                            ? null
                            : upscaleJetpackImage(baseUrl,
                                w: requestW, h: requestH);

                        final isFav = id != null && _favoriteIds.contains(id);

                        return SizedBox(
                          width: favCardW,
                          height: favRailH,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: id == null ? null : () => _openRecipe(r),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (imgUrl == null)
                                          const Center(
                                              child:
                                                  Icon(Icons.restaurant_menu))
                                        else
                                          Image.network(
                                            imgUrl,
                                            fit: BoxFit.cover,
                                            filterQuality: FilterQuality.high,
                                            cacheWidth: cacheW,
                                            cacheHeight: cacheH,
                                            gaplessPlayback: true,
                                            errorBuilder: (_, __, ___) =>
                                                const Center(
                                              child: Icon(Icons.restaurant_menu),
                                            ),
                                          ),
                                        if (isFav)
                                          const Positioned(
                                            right: 10,
                                            top: 10,
                                            child: Icon(
                                              Icons.star_rounded,
                                              color: Colors.amber,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: favTitleBlockH,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 12, 12, 12),
                                      child: Align(
                                        alignment: Alignment.topLeft,
                                        child: Text(
                                          title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: cardTextStyle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 18),

                // --------------------
                // BROWSE BY COURSE (new design)
                // --------------------
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Text('BROWSE BY COURSE', style: titleStyle),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      ...RecipeHubScreen._courses.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CourseCard(
                            title: c.title.toUpperCase(),
                            subtitle: c.subtitle,
                            iconAsset: c.iconAsset,
                            iconBoxBg: iconBoxBg,
                            onTap: () => _openCourse(
                              c.slug,
                              c.title,
                              c.subtitle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ✅ VIEW ALL RECIPES button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _openViewAllRecipes,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandDark,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
  'VIEW ALL RECIPES',
  style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
    color: Colors.white, // 👈 THIS is the missing piece
    fontWeight: FontWeight.w800,
    fontSize: 14, // 👈 change this
    letterSpacing: 1.2,
  ),
),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseLink {
  const _CourseLink({
    required this.title,
    required this.slug,
    required this.iconAsset,
    required this.subtitle,
  });

  final String title;
  final String slug;
  final String iconAsset;
  final String subtitle;
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.title,
    required this.subtitle,
    required this.iconAsset,
    required this.iconBoxBg,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String iconAsset;
  final Color iconBoxBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleStyle =
        (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 0,
    );

    final subtitleStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: AppColors.brandDark.withOpacity(0.85),
      fontWeight: FontWeight.w600,
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 74,
          child: Row(
            children: [
              Container(
                width: 74,
                height: double.infinity,
                color: iconBoxBg,
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  iconAsset,
                  width: 30,
                  height: 30,
                  // assumes your svg is already the right stroke colour
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: titleStyle),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: subtitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

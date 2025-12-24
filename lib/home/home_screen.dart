// lib/home/home_screen.dart
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../recipes/recipe_detail_screen.dart';
import '../recipes/recipe_repository.dart';

// ✅ SAME weekId logic as meal plan
import '../meal_plan/core/meal_plan_keys.dart';

// ✅ Centralised review prompt
import '../meal_plan/core/meal_plan_review_service.dart';

// ✅ NEW: use the centralised meal plan repo + controller to auto-populate
import '../meal_plan/core/meal_plan_repository.dart';
import '../meal_plan/core/meal_plan_controller.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRecipesAndBootstrap();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await MealPlanReviewService.checkAndPromptIfNeeded(context);
    });
  }

  @override
  void dispose() {
    _mealCtrl?.stop();
    _mealCtrl = null;
    super.dispose();
  }

  // ---------- VARIABLE FONT HELPERS ----------

  TextStyle _w(TextStyle base, double wght) {
    // Keep BOTH fontWeight and fontVariations so variable Montserrat actually moves on wght axis.
    return base.copyWith(
      fontWeight: _toFontWeight(wght),
      fontVariations: [FontVariation('wght', wght)],
    );
  }

  FontWeight _toFontWeight(double wght) {
    if (wght >= 900) return FontWeight.w900;
    if (wght >= 800) return FontWeight.w800;
    if (wght >= 700) return FontWeight.w700;
    if (wght >= 600) return FontWeight.w600;
    if (wght >= 500) return FontWeight.w500;
    if (wght >= 400) return FontWeight.w400;
    if (wght >= 300) return FontWeight.w300;
    if (wght >= 200) return FontWeight.w200;
    return FontWeight.w100;
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

  int? _recipeIdFromAny(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return int.tryParse('${raw ?? ''}');
  }

  Map<String, dynamic>? _byId(int? id) {
    if (id == null) return null;
    for (final r in _recipes) {
      final rid = _recipeIdFromAny(r['id']);
      if (rid == id) return r;
    }
    return null;
  }

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      final s = (t['rendered'] as String).trim();
      if (s.isNotEmpty) return s;
    }
    return 'Untitled';
  }

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.trim().isNotEmpty) return url.trim();
    }
    return null;
  }

  // ---------- ENTRY PARSING ----------

  Map<String, dynamic>? _parseEntry(dynamic raw) {
    if (raw is int) return {'type': 'recipe', 'recipeId': raw};
    if (raw is num) return {'type': 'recipe', 'recipeId': raw.toInt()};

    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final type = (m['type'] ?? '').toString();

      if (type == 'note') {
        final text = (m['text'] ?? '').toString().trim();
        if (text.isEmpty) return null;
        return {'type': 'note', 'text': text};
      }

      if (type == 'recipe') {
        final rid = _recipeIdFromAny(m['recipeId']);
        if (rid == null) return null;
        return {'type': 'recipe', 'recipeId': rid};
      }
    }

    if (raw is String) {
      final id = int.tryParse(raw.trim());
      if (id != null) return {'type': 'recipe', 'recipeId': id};
    }

    return null;
  }

  int? _entryRecipeId(Map<String, dynamic>? e) {
    if (e == null) return null;
    if (e['type'] != 'recipe') return null;
    return _recipeIdFromAny(e['recipeId']);
  }

  String? _entryNoteText(Map<String, dynamic>? e) {
    if (e == null) return null;
    if (e['type'] != 'note') return null;
    final t = (e['text'] ?? '').toString().trim();
    return t.isNotEmpty ? t : null;
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

  // ---------- UI STYLES ----------
  static const _heroBg = Color(0xFF044246);
  static const _heroAccent = Color(0xFF32998D);

  static const _breakfastBg = Color(0xFFF2C35C);
  static const _lunchBg = Color(0xFFE57A3A);
  static const _dinnerBg = Color(0xFFE98A97);
  static const _snacksBg = Color(0xFF5AA5B6);

  static const _onDark = Colors.white;

  // Your requested primary text colour (#00484B)
  static const _primaryText = Color(0xFF00484B);

  // ---------- UI HELPERS ----------

  Widget _buildBand({
    required BuildContext context,
    required String title,
    required Color bg,
    required Color headingColor,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    // Take theme token, then ONLY adjust color (keep weight axis),
    // BUT also force wght just in case this token is coming through “thin”.
    final baseHeading = theme.textTheme.titleLarge ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.w900);

    final headingStyle = _w(baseHeading, 900).copyWith(
  color: headingColor,
  letterSpacing: 1.2,
);

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: headingStyle),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 2,
                  color: headingColor.withOpacity(0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _mealCard({
    required BuildContext context,
    required String slotLabel,
    required Map<String, dynamic>? entry,
    required Color titleColor,
  }) {
    final theme = Theme.of(context);

    final baseTitle =
        theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16);

    final titleStyle = _w(baseTitle, 800).copyWith(
      fontSize: 18,
      color: titleColor,
    );

    final baseBody = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final subtitleStyle = _w(baseBody, 600).copyWith(color: _primaryText);

    final baseLabel = theme.textTheme.labelLarge ?? const TextStyle(fontSize: 12);
    final slotStyle = _w(baseLabel, 700).copyWith(letterSpacing: 0.8);

    final note = _entryNoteText(entry);
    if (note != null) {
      final noteTitleBase =
          theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16);
      final noteTitleStyle = _w(noteTitleBase, 700).copyWith(color: _primaryText);

      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(Icons.sticky_note_2_outlined, color: _primaryText),
          title: Text(note, style: noteTitleStyle),
          subtitle: Text(
            slotLabel.toUpperCase(),
            style: slotStyle.copyWith(color: _primaryText),
          ),
        ),
      );
    }

    if (entry == null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(Icons.restaurant_menu, color: _primaryText),
          title: Text('Not planned yet', style: subtitleStyle),
          subtitle: Text(
            slotLabel.toUpperCase(),
            style: slotStyle.copyWith(color: _primaryText),
          ),
        ),
      );
    }

    final rid = _entryRecipeId(entry);
    final r = _byId(rid);

    if (r == null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(Icons.restaurant_menu, color: _primaryText),
          title: Text('Recipe not found', style: subtitleStyle),
          subtitle: Text(
            slotLabel.toUpperCase(),
            style: slotStyle.copyWith(color: _primaryText),
          ),
        ),
      );
    }

    final displayTitle =
        _titleOf(r).replaceAll('&#038;', '&').replaceAll('&amp;', '&');
    final thumb = _thumbOf(r);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: rid == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecipeDetailScreen(id: rid),
                  ),
                ),
        child: SizedBox(
          height: 86,
          child: Row(
            children: [
              SizedBox(
                width: 110,
                height: double.infinity,
                child: thumb == null
                    ? Center(
                        child: Icon(Icons.restaurant_menu, color: _primaryText),
                      )
                    : Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(Icons.restaurant_menu, color: _primaryText),
                        ),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 18, color: _primaryText),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Suitable for whole family',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtitleStyle,
                            ),
                          ),
                        ],
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

  Widget _buttonBar(BuildContext context) {
  final theme = Theme.of(context);

  final baseLabel = theme.textTheme.labelLarge ?? const TextStyle(fontSize: 12);
  final btnTextStyle = _w(baseLabel, 800).copyWith(
    letterSpacing: 0.8,
    color: _onDark, // ✅ THIS fixes it
  );

  return Container(
    width: double.infinity,
    color: _heroBg,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    child: Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pushNamed('/meal-plan'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _onDark,
                side: BorderSide(
                  color: _onDark.withOpacity(0.35),
                  width: 2,
                ),
                shape: const StadiumBorder(),
              ),
              child: Text('CUSTOMISE', style: btnTextStyle),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pushNamed('/meal-plan'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _onDark,
                side: BorderSide(
                  color: _onDark.withOpacity(0.35),
                  width: 2,
                ),
                shape: const StadiumBorder(),
              ),
              child: Text('FULL WEEK', style: btnTextStyle),
            ),
          ),
        ),
      ],
    ),
  );
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

        final parsedBySlot = <String, Map<String, dynamic>>{};
        for (final e in todayRaw.entries) {
          final parsed = _parseEntry(e.value);
          if (parsed == null) continue;
          parsedBySlot[e.key.toString()] = parsed;
        }

        final breakfast = parsedBySlot['breakfast'];
        final lunch = parsedBySlot['lunch'];
        final dinner = parsedBySlot['dinner'];
        final snack1 = parsedBySlot['snack1'];
        final snack2 = parsedBySlot['snack2'];

        final theme = Theme.of(context);

        final heroTodayBase =
            theme.textTheme.headlineSmall ?? const TextStyle(fontSize: 38);
        final heroMealBase =
            theme.textTheme.headlineSmall ?? const TextStyle(fontSize: 46);

        final heroTodayStyle = const TextStyle(
  fontFamily: 'Montserrat',
  fontSize: 30,
  color: Colors.white,
  height: 1.0,
  letterSpacing: 0.6,
  fontWeight: FontWeight.w900,
  fontVariations: [FontVariation('wght', 900)],
);

final heroMealPlanStyle = const TextStyle(
  fontFamily: 'Montserrat',
  fontSize: 52,
  color: Color(0xFF32998D),
  height: 1.0,
  letterSpacing: 1.04,
  fontWeight: FontWeight.w900,
  fontVariations: [FontVariation('wght', 900)],
);

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            // HERO
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 16, 18),
              color: _heroBg,
              child: RichText(
  text: TextSpan(
    children: [
      TextSpan(text: "TODAY’S\n", style: heroTodayStyle),
      TextSpan(text: "MEAL PLAN", style: heroMealPlanStyle),
    ],
  ),
),
            ),

            _buildBand(
              context: context,
              title: 'BREAKFAST',
              bg: _breakfastBg,
              headingColor: _onDark,
              children: [
                _mealCard(
                  context: context,
                  slotLabel: 'breakfast',
                  entry: breakfast,
                  titleColor: _breakfastBg,
                ),
              ],
            ),

            _buildBand(
              context: context,
              title: 'LUNCH',
              bg: _lunchBg,
              headingColor: _onDark,
              children: [
                _mealCard(
                  context: context,
                  slotLabel: 'lunch',
                  entry: lunch,
                  titleColor: _lunchBg,
                ),
              ],
            ),

            _buildBand(
              context: context,
              title: 'DINNER',
              bg: _dinnerBg,
              headingColor: _onDark,
              children: [
                _mealCard(
                  context: context,
                  slotLabel: 'dinner',
                  entry: dinner,
                  titleColor: _dinnerBg,
                ),
              ],
            ),

            _buildBand(
              context: context,
              title: 'SNACKS',
              bg: _snacksBg,
              headingColor: _onDark,
              children: [
                _mealCard(
                  context: context,
                  slotLabel: 'snack1',
                  entry: snack1,
                  titleColor: _snacksBg,
                ),
                const SizedBox(height: 4),
                _mealCard(
                  context: context,
                  slotLabel: 'snack2',
                  entry: snack2,
                  titleColor: _snacksBg,
                ),
              ],
            ),

            _buttonBar(context),
          ],
        );
      },
    );
  }
}

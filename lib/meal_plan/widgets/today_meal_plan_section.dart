// lib/meal_plan/widgets/today_meal_plan_section.dart
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';

import '../../recipes/recipe_detail_screen.dart';
import '../../theme/app_theme.dart';
import 'meal_plan_entry_parser.dart';

class TodayMealPlanSection extends StatelessWidget {
  const TodayMealPlanSection({
    super.key,
    required this.todayRaw,
    required this.recipes,
    required this.favoriteIds,
    required this.onOpenMealPlan,
    this.heroTopText = "TODAY’S",
    this.heroBottomText = "MEAL PLAN",

    // ✅ Editable mode (optional)
    this.onInspireSlot,
    this.onChooseSlot,
    this.onNoteSlot,
    this.onClearSlot,

    this.canSave = false,
    this.onSaveChanges,
  });

  /// Map of slots for a day (breakfast/lunch/dinner/snack1/snack2 etc)
  final Map<String, dynamic> todayRaw;

  /// Full recipe list already loaded (WPRM JSON list)
  final List<Map<String, dynamic>> recipes;

  /// Favorite IDs set (read-only)
  final Set<int> favoriteIds;

  /// Called for both buttons (Customise / Full Week)
  final VoidCallback onOpenMealPlan;

  /// Hero text override (so week tabs can show "MONDAY", etc.)
  final String heroTopText;
  final String heroBottomText;

  // ✅ Optional callbacks to enable editing controls
  final Future<void> Function(String slot)? onInspireSlot;
  final Future<void> Function(String slot)? onChooseSlot;
  final Future<void> Function(String slot)? onNoteSlot;
  final Future<void> Function(String slot)? onClearSlot;

  final bool canSave;
  final Future<void> Function()? onSaveChanges;

  bool get _editable =>
      onInspireSlot != null ||
      onChooseSlot != null ||
      onNoteSlot != null ||
      onClearSlot != null ||
      onSaveChanges != null;

  // -----------------------------
  // THEME TOKENS (SSoT)
  // -----------------------------
  Color get _heroBg => AppColors.brandDark;
  Color get _heroAccent => AppColors.brandActive;

  Color get _breakfastBg => AppColors.breakfast;
  Color get _lunchBg => AppColors.lunch;
  Color get _dinnerBg => AppColors.dinner;
  Color get _snacksBg => AppColors.snacks;

  Color get _onDark => AppColors.white;
  Color get _primaryText => AppColors.textPrimary;

  // -----------------------------
  // VARIABLE FONT HELPERS
  // -----------------------------
  TextStyle _w(TextStyle base, double wght) {
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

  // -----------------------------
  // DATA HELPERS
  // -----------------------------
  Map<String, dynamic>? _byId(int? id) {
    if (id == null) return null;
    for (final r in recipes) {
      final rid = MealPlanEntryParser.recipeIdFromAny(r['id']);
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

  bool _isFavorited(int? recipeId) {
    if (recipeId == null) return false;
    return favoriteIds.contains(recipeId);
  }

  /// Normalise slot keys so the widget works across Firestore formats.
  /// snack_1 -> snack1, snack_2 -> snack2
  String _normaliseSlotKey(String key) {
    final k = key.trim().toLowerCase();
    if (k == 'snack_1' || k == 'snacks_1' || k == 'snack 1' || k == 'snacks 1') {
      return 'snack1';
    }
    if (k == 'snack_2' || k == 'snacks_2' || k == 'snack 2' || k == 'snacks 2') {
      return 'snack2';
    }
    return k;
  }

  Map<String, Map<String, dynamic>> _parsedBySlot() {
    final parsedBySlot = <String, Map<String, dynamic>>{};
    for (final e in todayRaw.entries) {
      final slotKey = _normaliseSlotKey(e.key.toString());
      final parsed = MealPlanEntryParser.parse(e.value);
      if (parsed == null) continue;
      parsedBySlot[slotKey] = parsed;
    }
    return parsedBySlot;
  }

  // -----------------------------
  // UI BUILDERS
  // -----------------------------
  Widget _buildBand({
    required BuildContext context,
    required String title,
    required Color bg,
    required Color headingColor,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    // Prefer theme tokens; only override what we need.
    final baseHeading = theme.textTheme.titleLarge ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.w900);

    final headingStyle = _w(baseHeading, 900).copyWith(
      color: headingColor,
      // keep the “band” look but don’t fight theme sizes
      letterSpacing: 1.2,
    );

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 18, AppSpace.s16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: headingStyle),
              const SizedBox(width: AppSpace.s12),
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

  Widget _slotActions({
    required BuildContext context,
    required String slotKey,
    required bool hasEntry,
  }) {
    if (!_editable) return const SizedBox.shrink();

    final buttons = <Widget>[];

    if (onInspireSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Inspire',
          icon: const Icon(Icons.refresh),
          onPressed: () => onInspireSlot!(slotKey),
        ),
      );
    }
    if (onChooseSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Choose',
          icon: const Icon(Icons.search),
          onPressed: () => onChooseSlot!(slotKey),
        ),
      );
    }
    if (onNoteSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Note',
          icon: const Icon(Icons.edit_note),
          onPressed: () => onNoteSlot!(slotKey),
        ),
      );
    }
    if (hasEntry && onClearSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.close),
          onPressed: () => onClearSlot!(slotKey),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: buttons,
    );
  }

  Widget _mealCard({
    required BuildContext context,
    required String slotKey,
    required String slotLabel,
    required Map<String, dynamic>? entry,
    required Color titleColor,
  }) {
    final theme = Theme.of(context);

    final baseTitle = theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16);
    final titleStyle = _w(baseTitle, 800).copyWith(
      fontSize: 18,
      color: titleColor,
    );

    final baseBody = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final subtitleStyle = _w(baseBody, 600).copyWith(color: _primaryText);

    final baseLabel = theme.textTheme.labelLarge ?? const TextStyle(fontSize: 12);
    final slotStyle = _w(baseLabel, 700).copyWith(letterSpacing: 0.8);

    // NOTE entry
    final note = MealPlanEntryParser.entryNoteText(entry);
    if (note != null) {
      final noteTitleBase = theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16);
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
          trailing: _slotActions(context: context, slotKey: slotKey, hasEntry: true),
          onTap: _editable && onNoteSlot != null ? () => onNoteSlot!(slotKey) : null,
        ),
      );
    }

    // EMPTY
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
          trailing: _slotActions(context: context, slotKey: slotKey, hasEntry: false),
        ),
      );
    }

    // RECIPE
    final rid = MealPlanEntryParser.entryRecipeId(entry);
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
          trailing: _slotActions(context: context, slotKey: slotKey, hasEntry: true),
        ),
      );
    }

    final displayTitle = _titleOf(r).replaceAll('&#038;', '&').replaceAll('&amp;', '&');
    final thumb = _thumbOf(r);
    final fav = _isFavorited(rid);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: rid == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
                ),
        child: SizedBox(
          height: 92,
          child: Row(
            children: [
              SizedBox(
                width: 112,
                height: double.infinity,
                child: thumb == null
                    ? Center(child: Icon(Icons.restaurant_menu, color: _primaryText))
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(Icons.restaurant_menu, color: _primaryText),
                            ),
                          ),
                          if (fav)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.star_rounded,
                                  size: 18,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.s16, 14, 10, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      const SizedBox(height: AppSpace.s4),
                      Text(
                        slotLabel.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: slotStyle.copyWith(color: _primaryText),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.s4),
                child: _slotActions(context: context, slotKey: slotKey, hasEntry: true),
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
      color: _onDark,
    );

    // Use Stadium here intentionally to keep the “hero CTA” look
    return Container(
      width: double.infinity,
      color: _heroBg,
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s16, AppSpace.s16, AppSpace.s16),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 54,
              child: OutlinedButton(
                onPressed: onOpenMealPlan,
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
          const SizedBox(width: AppSpace.s12),
          Expanded(
            child: SizedBox(
              height: 54,
              child: OutlinedButton(
                onPressed: onOpenMealPlan,
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

  Widget _saveBar(BuildContext context) {
    if (onSaveChanges == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final baseLabel = theme.textTheme.labelLarge ?? const TextStyle(fontSize: 12);

    final btnTextStyle = _w(baseLabel, 900).copyWith(
      letterSpacing: 0.8,
      color: AppColors.white,
    );

    return Container(
      width: double.infinity,
      color: _heroBg,
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s16),
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: canSave ? () => onSaveChanges!.call() : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _heroAccent,
            shape: const StadiumBorder(),
          ),
          child: Text('SAVE CHANGES', style: btnTextStyle),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsedBySlot();

    final breakfast = parsed['breakfast'];
    final lunch = parsed['lunch'];
    final dinner = parsed['dinner'];
    final snack1 = parsed['snack1'];
    final snack2 = parsed['snack2'];

    // Use theme family, but keep your strong hero sizing
    final heroTopStyle = TextStyle(
      fontFamily: AppText.fontFamily,
      fontSize: 30,
      color: AppColors.white,
      height: 1.0,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
    );

    final heroBottomStyle = TextStyle(
      fontFamily: AppText.fontFamily,
      fontSize: 52,
      color: _heroAccent,
      height: 1.0,
      letterSpacing: 1.04,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ✅ HERO
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 24, 16, 18),
          color: _heroBg,
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(text: '$heroTopText\n', style: heroTopStyle),
                TextSpan(text: heroBottomText, style: heroBottomStyle),
              ],
            ),
          ),
        ),

        // ✅ BANDS (all colours now come from AppColors = SSoT)
        _buildBand(
          context: context,
          title: 'BREAKFAST',
          bg: _breakfastBg,
          headingColor: _onDark,
          children: [
            _mealCard(
              context: context,
              slotKey: 'breakfast',
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
              slotKey: 'lunch',
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
              slotKey: 'dinner',
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
              slotKey: 'snack1',
              slotLabel: 'snack1',
              entry: snack1,
              titleColor: _snacksBg,
            ),
            const SizedBox(height: 6),
            _mealCard(
              context: context,
              slotKey: 'snack2',
              slotLabel: 'snack2',
              entry: snack2,
              titleColor: _snacksBg,
            ),
          ],
        ),

        // ✅ Buttons
        _buttonBar(context),

        // ✅ Save changes (editable mode only)
        _saveBar(context),
      ],
    );
  }
}

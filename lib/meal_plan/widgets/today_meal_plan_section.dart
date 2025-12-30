// lib/meal_plan/widgets/today_meal_plan_section.dart
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

    /// Optional: if null, no footer button bar renders (perfect for MealPlanScreen).
    this.onOpenMealPlan,

    this.heroTopText = "TODAY’S",
    this.heroBottomText = "MEAL PLAN",

    // ✅ Editable mode (optional)
    this.onInspireSlot,
    this.onChooseSlot,
    this.onNoteSlot,
    this.onClearSlot,

    /// Only shows when canSave == true AND onSaveChanges != null
    this.canSave = false,
    this.onSaveChanges,
  });

  /// Map of slots for a day (breakfast/lunch/dinner/snack1/snack2 etc)
  final Map<String, dynamic> todayRaw;

  /// Full recipe list already loaded (WPRM JSON list)
  final List<Map<String, dynamic>> recipes;

  /// Favorite IDs set (read-only)
  final Set<int> favoriteIds;

  /// Called for footer buttons (Customise / Full Week) on Home only.
  final VoidCallback? onOpenMealPlan;

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

  bool get _showFooterButtons => onOpenMealPlan != null;

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
      final s = (t['rendered'] as String)
          .replaceAll('&#038;', '&')
          .replaceAll('&amp;', '&')
          .trim();
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

    final headingStyle = (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
  color: headingColor,
  fontSize: ((theme.textTheme.titleLarge?.fontSize) ?? 30) - 4, // slightly smaller than hero
  fontWeight: FontWeight.w800,
  fontVariations: const [FontVariation('wght', 800)],
  letterSpacing: 1.0,
  height: 1.0,
);

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s12, AppSpace.s16, AppSpace.s12),
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
          const SizedBox(height: AppSpace.s4),
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
    required Map<String, dynamic>? entry,
    required Color titleColor,
  }) {
    final theme = Theme.of(context);

    // Recipe title: titleMedium (16 / w700) from theme
    final titleStyle = (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
  color: titleColor,
  height: 1.3,
  fontWeight: FontWeight.w800,
  fontVariations: const [FontVariation('wght', 800)],
);

    // Supporting copy: bodyMedium (14 / w600) from theme
    final bodyStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: _primaryText,
    );

    // NOTE entry
    final note = MealPlanEntryParser.entryNoteText(entry);
    if (note != null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          leading: Icon(Icons.sticky_note_2_outlined, color: _primaryText),
          title: Text(note, style: (theme.textTheme.titleMedium ?? const TextStyle())),
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
          dense: true,
          leading: Icon(Icons.restaurant_menu, color: _primaryText),
          title: Text('Not planned yet', style: bodyStyle),
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
          dense: true,
          leading: Icon(Icons.restaurant_menu, color: _primaryText),
          title: Text('Recipe not found', style: bodyStyle),
          trailing: _slotActions(context: context, slotKey: slotKey, hasEntry: true),
        ),
      );
    }

    final displayTitle = _titleOf(r);
    final thumb = _thumbOf(r);
    final fav = _isFavorited(rid);

    return Card(
      // Override global r20 for this compact card (you asked for 12)
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.r12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: rid == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
                ),
        child: SizedBox(
          height: 74, // layout value
          child: Row(
            children: [
              SizedBox(
                width: 88, // layout value
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
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.s12, AppSpace.s12, AppSpace.s12, AppSpace.s12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.clip,
                        style: titleStyle,
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
    if (!_showFooterButtons) return const SizedBox.shrink();
    final theme = Theme.of(context);

    // labelLarge is already 12 / w700 / ls 0.8 in your theme
    final btnTextStyle = (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: _onDark,
    );

    return Container(
      width: double.infinity,
      color: _heroBg,
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: OutlinedButton(
                onPressed: onOpenMealPlan,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _onDark,
                  side: BorderSide(color: _onDark.withOpacity(0.35), width: 2),
                  shape: const StadiumBorder(),
                ),
                child: Text('CUSTOMISE', style: btnTextStyle),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.s4),
          Expanded(
            child: SizedBox(
              height: 40,
              child: OutlinedButton(
                onPressed: onOpenMealPlan,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _onDark,
                  side: BorderSide(color: _onDark.withOpacity(0.35), width: 2),
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
    if (!canSave) return const SizedBox.shrink();

    final theme = Theme.of(context);

    final btnTextStyle = (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: AppColors.white,
    );

    return Container(
      width: double.infinity,
      color: _heroBg,
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s16),
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: () => onSaveChanges!.call(),
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
    final theme = Theme.of(context);
    final parsed = _parsedBySlot();

    final breakfast = parsed['breakfast'];
    final lunch = parsed['lunch'];
    final dinner = parsed['dinner'];
    final snack1 = parsed['snack1'];
    final snack2 = parsed['snack2'];

    // ✅ Hero: use existing styles
    final heroTopStyle = (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
  color: AppColors.white,
  fontSize: ((theme.textTheme.titleLarge?.fontSize) ?? 28), // bigger
  fontWeight: FontWeight.w800, // stronger
  fontVariations: const [FontVariation('wght', 800)], // locks bold for Montserrat variable
  letterSpacing: 1.2,
  height: 1.0,
);

    // Bottom line can stay as titleLarge too, just change colour
    final heroBottomStyle = (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: _heroAccent,
      letterSpacing: 1.2,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          color: _heroBg,
          child: heroBottomText.trim().isEmpty
              ? Text(heroTopText, style: heroTopStyle)
              : RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: '$heroTopText\n', style: heroTopStyle),
                      TextSpan(text: heroBottomText, style: heroBottomStyle),
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
              slotKey: 'breakfast',
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
              entry: snack1,
              titleColor: _snacksBg,
            ),
            const SizedBox(height: 0),
            _mealCard(
              context: context,
              slotKey: 'snack2',
              entry: snack2,
              titleColor: _snacksBg,
            ),
          ],
        ),

        _buttonBar(context),
        _saveBar(context),
      ],
    );
  }
}

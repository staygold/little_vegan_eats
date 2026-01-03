// lib/meal_plan/widgets/today_meal_plan_section.dart
import 'dart:async';
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

    /// Back-compat: if provided, will be used for BOTH buttons.
    /// Prefer using [onOpenToday] and [onOpenWeek].
    this.onOpenMealPlan,

    /// ✅ New: separate intents
    this.onOpenToday,
    this.onOpenWeek,

    this.heroTopText = "TODAY’S",
    this.heroBottomText = "MEAL PLAN",

    /// ✅ Home-only UI (accordion style like the mock)
    this.homeAccordion = false,

    /// ✅ NEW: render the Home accordion UI, but keep ALL sections expanded.
    /// (Perfect for PlansHub where you want the Home styling but always open.)
    this.homeAlwaysExpanded = false,

    // ✅ Editable mode (optional)
    this.onInspireSlot,
    this.onChooseSlot,
    this.onNoteSlot,
    this.onClearSlot,

    /// Only shows when canSave == true AND onSaveChanges != null
    this.canSave = false,
    this.onSaveChanges,

    /// ✅ Home accordion section title tuning (BREAKFAST/LUNCH/DINNER/SNACKS)
    /// Example: homeSectionTitleSize: 22, homeSectionTitleWeight: 900
    this.homeSectionTitleSize,
    this.homeSectionTitleWeight,
  });

  /// Map of slots for a day (breakfast/lunch/dinner/snack1/snack2 etc)
  final Map<String, dynamic> todayRaw;

  /// Full recipe list already loaded (WPRM JSON list)
  final List<Map<String, dynamic>> recipes;

  /// Favorite IDs set (read-only)
  final Set<int> favoriteIds;

  /// Back-compat: used for BOTH buttons if [onOpenToday]/[onOpenWeek] not set
  final VoidCallback? onOpenMealPlan;

  /// Customise Plan -> Today's plan screen
  final VoidCallback? onOpenToday;

  /// View Full Week -> Week screen
  final VoidCallback? onOpenWeek;

  /// Hero text override (so week tabs can show "MONDAY", etc.)
  final String heroTopText;
  final String heroBottomText;

  /// Home-only accordion layout
  final bool homeAccordion;

  /// Home accordion but all sections expanded
  final bool homeAlwaysExpanded;

  // ✅ Optional callbacks to enable editing controls
  final Future<void> Function(String slot)? onInspireSlot;
  final Future<void> Function(String slot)? onChooseSlot;
  final Future<void> Function(String slot)? onNoteSlot;
  final Future<void> Function(String slot)? onClearSlot;

  final bool canSave;
  final Future<void> Function()? onSaveChanges;

  /// ✅ Home accordion section title tuning (BREAKFAST/LUNCH/DINNER/SNACKS)
  final double? homeSectionTitleSize;
  final int? homeSectionTitleWeight; // 100..900 (FontVariation + fontWeight)

  bool get _editable =>
      onInspireSlot != null ||
      onChooseSlot != null ||
      onNoteSlot != null ||
      onClearSlot != null ||
      onSaveChanges != null;

  VoidCallback? get _openToday => onOpenToday ?? onOpenMealPlan;
  VoidCallback? get _openWeek => onOpenWeek ?? onOpenMealPlan;

  bool get _showFooterButtons => _openToday != null || _openWeek != null;

  int _clampWght(int v) => v.clamp(100, 900);

  FontWeight _fontWeightFromWght(int w) {
    final step = (w / 100).round().clamp(1, 9);
    switch (step) {
      case 1:
        return FontWeight.w100;
      case 2:
        return FontWeight.w200;
      case 3:
        return FontWeight.w300;
      case 4:
        return FontWeight.w400;
      case 5:
        return FontWeight.w500;
      case 6:
        return FontWeight.w600;
      case 7:
        return FontWeight.w700;
      case 8:
        return FontWeight.w800;
      default:
        return FontWeight.w900;
    }
  }

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

  // Home mock background
  static const Color _homePanelBgConst = Color(0xFFECF3F4);

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

  String _normaliseSlotKey(String key) {
    final k = key.trim().toLowerCase();
    if (k == 'snack_1' ||
        k == 'snacks_1' ||
        k == 'snack 1' ||
        k == 'snacks 1') {
      return 'snack1';
    }
    if (k == 'snack_2' ||
        k == 'snacks_2' ||
        k == 'snack 2' ||
        k == 'snacks 2') {
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
  // EDITING ACTIONS (shared)
  // -----------------------------
  Widget _slotActions({
    required BuildContext context,
    required String slotKey,
    required bool hasEntry,
    Color? iconColor,
  }) {
    if (!_editable) return const SizedBox.shrink();

    final buttons = <Widget>[];

    if (onInspireSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Inspire',
          icon: Icon(Icons.refresh, color: iconColor),
          onPressed: () => onInspireSlot!(slotKey),
        ),
      );
    }
    if (onChooseSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Choose',
          icon: Icon(Icons.search, color: iconColor),
          onPressed: () => onChooseSlot!(slotKey),
        ),
      );
    }
    if (onNoteSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Note',
          icon: Icon(Icons.edit_note, color: iconColor),
          onPressed: () => onNoteSlot!(slotKey),
        ),
      );
    }
    if (hasEntry && onClearSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Clear',
          icon: Icon(Icons.close, color: iconColor),
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

  // -----------------------------
  // HOME ACCORDION UI
  // -----------------------------
  Widget _homeHero(BuildContext context) {
    final theme = Theme.of(context);

    final heroStyle =
        (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontSize: 20,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 0,
      height: 1.2,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 18, AppSpace.s16, 14),
      child: Text(
        '${heroTopText.trim()} ${heroBottomText.trim()}'.trim(),
        style: heroStyle,
      ),
    );
  }

  Widget _homeAccordionItem({
    required BuildContext context,
    required String title,
    required Color bg,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> expandedChildren,
    required bool showChevron,
  }) {
    final theme = Theme.of(context);

    final base = (theme.textTheme.titleLarge ?? const TextStyle());

    final wght = _clampWght(homeSectionTitleWeight ?? 800);

    // ✅ USE the param (you weren’t using it before)
    final fontSize = homeSectionTitleSize ?? 21;

    final titleStyle = base.copyWith(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: _fontWeightFromWght(wght),
      fontVariations: [FontVariation('wght', wght.toDouble())],
      letterSpacing: 1.25,
      height: 1.0,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // ✅ If we’re always expanded, tapping shouldn’t collapse
        onTap: showChevron ? onToggle : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Text(title, style: titleStyle),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: Colors.white.withOpacity(0.25),
                    ),
                  ),
                  if (showChevron) ...[
                    const SizedBox(width: 10),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ],
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 12),
                ...expandedChildren,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeMealCard({
    required BuildContext context,
    required String slotKey,
    required Map<String, dynamic>? entry,
    required Color titleTint,
  }) {
    final theme = Theme.of(context);

    final note = MealPlanEntryParser.entryNoteText(entry);
    if (note != null) {
      return Container(
        height: 86,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.sticky_note_2_outlined, color: _primaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: (theme.textTheme.titleMedium ?? const TextStyle())
                    .copyWith(
                  color: _primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _slotActions(
              context: context,
              slotKey: slotKey,
              hasEntry: true,
              iconColor: _primaryText,
            ),
            const SizedBox(width: 6),
          ],
        ),
      );
    }

    if (entry == null) {
      return Container(
        height: 86,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.restaurant_menu, color: _primaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Not planned yet',
                style: (theme.textTheme.bodyMedium ?? const TextStyle())
                    .copyWith(
                  color: _primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _slotActions(
              context: context,
              slotKey: slotKey,
              hasEntry: false,
              iconColor: _primaryText,
            ),
          ],
        ),
      );
    }

    final rid = MealPlanEntryParser.entryRecipeId(entry);
    final r = _byId(rid);

    if (r == null) {
      return Container(
        height: 86,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.restaurant_menu, color: _primaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Recipe not found',
                style: (theme.textTheme.bodyMedium ?? const TextStyle())
                    .copyWith(
                  color: _primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _slotActions(
              context: context,
              slotKey: slotKey,
              hasEntry: true,
              iconColor: _primaryText,
            ),
          ],
        ),
      );
    }

    final displayTitle = _titleOf(r);
    final thumb = _thumbOf(r);
    final fav = _isFavorited(rid);

    final smallLabelStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: _primaryText.withOpacity(0.85),
      fontWeight: FontWeight.w600,
    );

    final titleStyle =
        (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
      fontSize: 18,
      height: 1.1,
    );

    return InkWell(
      onTap: rid == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
              ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 86,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 110,
              height: double.infinity,
              child: thumb == null
                  ? Center(
                      child: Icon(Icons.restaurant_menu, color: _primaryText),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(
                              Icons.restaurant_menu,
                              color: _primaryText,
                            ),
                          ),
                        ),
                        if (fav)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.92),
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
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Lorem ipsum dolor sit amet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: smallLabelStyle,
                    ),
                  ],
                ),
              ),
            ),
            if (_editable)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _slotActions(
                  context: context,
                  slotKey: slotKey,
                  hasEntry: true,
                  iconColor: _primaryText,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _homeButtons(BuildContext context) {
    if (!_showFooterButtons) return const SizedBox.shrink();

    final theme = Theme.of(context);

    final labelStyle =
        (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w800,
      fontSize: 14,
      fontVariations: const [FontVariation('wght', 800)],
      letterSpacing: 0,
    );

    final btnStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.brandDark,
      side: BorderSide(
        color: AppColors.brandDark.withOpacity(0.35),
        width: 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, AppSpace.s16, 18),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _openToday,
                style: btnStyle,
                child: Text('CUSTOMISE PLAN', style: labelStyle),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _openWeek,
                style: btnStyle,
                child: Text('VIEW FULL WEEK', style: labelStyle),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeSection(BuildContext context) {
    final parsed = _parsedBySlot();

    final breakfast = parsed['breakfast'];
    final lunch = parsed['lunch'];
    final dinner = parsed['dinner'];
    final snack1 = parsed['snack1'];
    final snack2 = parsed['snack2'];

    return _HomeAccordionScaffold(
      panelBg: _homePanelBgConst,
      hero: _homeHero(context),
      breakfastBg: _breakfastBg,
      lunchBg: _lunchBg,
      dinnerBg: _dinnerBg,
      snacksBg: _snacksBg,

      // ✅ New behaviour switch
      alwaysExpanded: homeAlwaysExpanded,

      buildItem: ({
        required String title,
        required Color bg,
        required bool expanded,
        required VoidCallback onToggle,
        required List<Widget> children,
        required bool showChevron,
      }) {
        return _homeAccordionItem(
          context: context,
          title: title,
          bg: bg,
          expanded: expanded,
          onToggle: onToggle,
          expandedChildren: children,
          showChevron: showChevron,
        );
      },
      buildBreakfast: (_) => [
        _homeMealCard(
          context: context,
          slotKey: 'breakfast',
          entry: breakfast,
          titleTint: _breakfastBg,
        ),
      ],
      buildLunch: (_) => [
        _homeMealCard(
          context: context,
          slotKey: 'lunch',
          entry: lunch,
          titleTint: _lunchBg,
        ),
      ],
      buildDinner: (_) => [
        _homeMealCard(
          context: context,
          slotKey: 'dinner',
          entry: dinner,
          titleTint: _dinnerBg,
        ),
      ],
      buildSnacks: (_) => [
        _homeMealCard(
          context: context,
          slotKey: 'snack1',
          entry: snack1,
          titleTint: _snacksBg,
        ),
        const SizedBox(height: 10),
        _homeMealCard(
          context: context,
          slotKey: 'snack2',
          entry: snack2,
          titleTint: _snacksBg,
        ),
      ],
      footer: _homeButtons(context),
    );
  }

  // -----------------------------
  // ORIGINAL (non-home) UI
  // -----------------------------
  // (unchanged below)

  Widget _buildBand({
    required BuildContext context,
    required String title,
    required Color bg,
    required Color headingColor,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    final headingStyle =
        (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: headingColor,
      fontSize: ((theme.textTheme.titleLarge?.fontSize) ?? 30) - 4,
      fontWeight: FontWeight.w800,
      fontVariations: const [FontVariation('wght', 800)],
      letterSpacing: 1.0,
      height: 1.0,
    );

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.s16,
        AppSpace.s12,
        AppSpace.s16,
        AppSpace.s12,
      ),
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

  Widget _mealCard({
    required BuildContext context,
    required String slotKey,
    required Map<String, dynamic>? entry,
    required Color titleColor,
  }) {
    final theme = Theme.of(context);

    final titleStyle =
        (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: titleColor,
      height: 1.3,
      fontWeight: FontWeight.w800,
      fontVariations: const [FontVariation('wght', 800)],
    );

    final bodyStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: _primaryText,
    );

    final note = MealPlanEntryParser.entryNoteText(entry);
    if (note != null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          leading: Icon(Icons.sticky_note_2_outlined, color: _primaryText),
          title: Text(
            note,
            style: (theme.textTheme.titleMedium ?? const TextStyle()),
          ),
          trailing: _slotActions(
            context: context,
            slotKey: slotKey,
            hasEntry: true,
          ),
          onTap:
              _editable && onNoteSlot != null ? () => onNoteSlot!(slotKey) : null,
        ),
      );
    }

    if (entry == null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          leading: Icon(Icons.restaurant_menu, color: _primaryText),
          title: Text('Not planned yet', style: bodyStyle),
          trailing: _slotActions(
            context: context,
            slotKey: slotKey,
            hasEntry: false,
          ),
        ),
      );
    }

    final rid = MealPlanEntryParser.entryRecipeId(entry);
    final r = _byId(rid);

    if (r == null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          leading: Icon(Icons.restaurant_menu, color: _primaryText),
          title: Text('Recipe not found', style: bodyStyle),
          trailing: _slotActions(
            context: context,
            slotKey: slotKey,
            hasEntry: true,
          ),
        ),
      );
    }

    final displayTitle = _titleOf(r);
    final thumb = _thumbOf(r);
    final fav = _isFavorited(rid);

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.r8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: rid == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
                ),
        child: SizedBox(
          height: 74,
          child: Row(
            children: [
              SizedBox(
                width: 88,
                height: double.infinity,
                child: thumb == null
                    ? Center(
                        child: Icon(Icons.restaurant_menu, color: _primaryText),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(
                                Icons.restaurant_menu,
                                color: _primaryText,
                              ),
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.s12,
                    AppSpace.s12,
                    AppSpace.s12,
                    AppSpace.s12,
                  ),
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
                child: _slotActions(
                  context: context,
                  slotKey: slotKey,
                  hasEntry: true,
                ),
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

    final btnTextStyle =
        (theme.textTheme.labelLarge ?? const TextStyle()
    );

    return Container(
      width: double.infinity,
      color: _heroBg,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.s16,
        AppSpace.s8,
        AppSpace.s16,
        AppSpace.s8,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: OutlinedButton(
                onPressed: _openToday,
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
                onPressed: _openWeek,
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

    final btnTextStyle =
        (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: AppColors.white,
    );

    return Container(
      width: double.infinity,
      color: _heroBg,
      padding:
          const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s16),
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

  Widget _classicSection(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = _parsedBySlot();

    final breakfast = parsed['breakfast'];
    final lunch = parsed['lunch'];
    final dinner = parsed['dinner'];
    final snack1 = parsed['snack1'];
    final snack2 = parsed['snack2'];

    final heroTopStyle =
        (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: AppColors.white,
      fontSize: 12,
      fontWeight: FontWeight.w800,
      fontVariations: const [FontVariation('wght', 800)],
      letterSpacing: 1.2,
      height: 1.0,
    );

    final heroBottomStyle =
        (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
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

  @override
  Widget build(BuildContext context) {
    if (homeAccordion) return _homeSection(context);
    return _classicSection(context);
  }
}

/// Home accordion scaffold: stateful ONLY for accordion open state + time-based default.
class _HomeAccordionScaffold extends StatefulWidget {
  const _HomeAccordionScaffold({
    required this.panelBg,
    required this.hero,
    required this.breakfastBg,
    required this.lunchBg,
    required this.dinnerBg,
    required this.snacksBg,
    required this.buildItem,
    required this.buildBreakfast,
    required this.buildLunch,
    required this.buildDinner,
    required this.buildSnacks,
    required this.footer,
    required this.alwaysExpanded,
  });

  final Color panelBg;
  final Widget hero;

  final Color breakfastBg;
  final Color lunchBg;
  final Color dinnerBg;
  final Color snacksBg;

  final bool alwaysExpanded;

  final Widget Function({
    required String title,
    required Color bg,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
    required bool showChevron,
  }) buildItem;

  final List<Widget> Function(bool expanded) buildBreakfast;
  final List<Widget> Function(bool expanded) buildLunch;
  final List<Widget> Function(bool expanded) buildDinner;
  final List<Widget> Function(bool expanded) buildSnacks;

  final Widget footer;

  @override
  State<_HomeAccordionScaffold> createState() => _HomeAccordionScaffoldState();
}

class _HomeAccordionScaffoldState extends State<_HomeAccordionScaffold> {
  String _open = 'lunch';
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    if (!widget.alwaysExpanded) {
      _open = _slotForNow();

      _timer = Timer.periodic(const Duration(minutes: 10), (_) {
        final next = _slotForNow();
        if (!mounted) return;
        if (next != _open) setState(() => _open = next);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _slotForNow() {
    final h = DateTime.now().hour;
    if (h >= 4 && h <= 10) return 'breakfast';
    if (h >= 10 && h <= 14) return 'lunch';
    if (h >= 14 && h <= 20) return 'dinner';
    return 'snacks';
  }

  void _toggle(String slot) {
    if (widget.alwaysExpanded) return;
    setState(() => _open = (_open == slot) ? '' : slot);
  }

  bool _isOpen(String slot) {
    if (widget.alwaysExpanded) return true;
    return _open == slot;
  }

  @override
  Widget build(BuildContext context) {
    final showChevron = !widget.alwaysExpanded;

    return Container(
      color: widget.panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.hero,
          widget.buildItem(
            title: 'BREAKFAST',
            bg: widget.breakfastBg,
            expanded: _isOpen('breakfast'),
            onToggle: () => _toggle('breakfast'),
            children: widget.buildBreakfast(_isOpen('breakfast')),
            showChevron: showChevron,
          ),
          widget.buildItem(
            title: 'LUNCH',
            bg: widget.lunchBg,
            expanded: _isOpen('lunch'),
            onToggle: () => _toggle('lunch'),
            children: widget.buildLunch(_isOpen('lunch')),
            showChevron: showChevron,
          ),
          widget.buildItem(
            title: 'DINNER',
            bg: widget.dinnerBg,
            expanded: _isOpen('dinner'),
            onToggle: () => _toggle('dinner'),
            children: widget.buildDinner(_isOpen('dinner')),
            showChevron: showChevron,
          ),
          widget.buildItem(
            title: 'SNACKS',
            bg: widget.snacksBg,
            expanded: _isOpen('snacks'),
            onToggle: () => _toggle('snacks'),
            children: widget.buildSnacks(_isOpen('snacks')),
            showChevron: showChevron,
          ),
          widget.footer,
        ],
      ),
    );
  }
}

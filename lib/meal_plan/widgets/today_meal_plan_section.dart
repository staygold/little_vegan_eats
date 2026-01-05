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

    this.onOpenMealPlan,
    this.onOpenToday,
    this.onOpenWeek,

    this.heroTopText = "TODAY’S",
    this.heroBottomText = "MEAL PLAN",

    this.homeAccordion = false,
    this.homeAlwaysExpanded = false,

    this.onInspireSlot,
    this.onChooseSlot,

    this.onReuseSlot,

    this.onNoteSlot,
    this.onClearSlot,

    this.canSave = false,
    this.onSaveChanges,

    this.homeSectionTitleSize,
    this.homeSectionTitleWeight,
  });

  final Map<String, dynamic> todayRaw;
  final List<Map<String, dynamic>> recipes;
  final Set<int> favoriteIds;

  final VoidCallback? onOpenMealPlan;
  final VoidCallback? onOpenToday;
  final VoidCallback? onOpenWeek;

  final String heroTopText;
  final String heroBottomText;

  final bool homeAccordion;
  final bool homeAlwaysExpanded;

  final Future<void> Function(String slot)? onInspireSlot;
  final Future<void> Function(String slot)? onChooseSlot;

  final Future<void> Function(String slot)? onReuseSlot;

  final Future<void> Function(String slot)? onNoteSlot;
  final Future<void> Function(String slot)? onClearSlot;

  final bool canSave;
  final Future<void> Function()? onSaveChanges;

  final double? homeSectionTitleSize;
  final int? homeSectionTitleWeight;

  bool get _editable =>
      onInspireSlot != null ||
      onChooseSlot != null ||
      onReuseSlot != null ||
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

    if (onReuseSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Reuse',
          icon: Icon(Icons.content_copy_rounded, color: iconColor),
          onPressed: () => onReuseSlot!(slotKey),
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

  String _slotLabel(String slotKey) {
    switch (slotKey) {
      case 'breakfast':
        return 'Breakfast';
      case 'lunch':
        return 'Lunch';
      case 'dinner':
        return 'Dinner';
      case 'snack1':
        return 'Snack 1';
      case 'snack2':
        return 'Snack 2';
      default:
        return slotKey;
    }
  }

  Widget _homeMealCard({
    required BuildContext context,
    required String slotKey,
    required Map<String, dynamic>? entry,
    required Color titleTint,
  }) {
    final theme = Theme.of(context);

    // 1. NOTES
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
                style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
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

    // 2. EMPTY STATE
    // ✅ FIX: Also treat explicit 'clear' type as empty
    if (entry == null || entry['type'] == 'clear') {
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
                style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
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

    // 3. RECIPE (Standard or Reused)
    final rid = MealPlanEntryParser.entryRecipeId(entry);
    if (rid != null) {
      final r = _byId(rid);
      if (r != null) {
        final displayTitle = _titleOf(r);
        final thumb = _thumbOf(r);
        final fav = _isFavorited(rid);

        final reuseMeta = MealPlanEntryParser.entryReuseFrom(entry);
        String labelText = _slotLabel(slotKey);
        
        if (reuseMeta != null) {
           final dk = reuseMeta['dayKey'] ?? reuseMeta['fromDayKey'];
           if (dk != null) {
             labelText = 'Reused from $dk'; 
           }
        }

        return InkWell(
          onTap: () => Navigator.of(context).push(
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
                      ? Center(child: Icon(Icons.restaurant_menu, color: _primaryText))
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              thumb,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Center(child: Icon(Icons.restaurant_menu, color: _primaryText)),
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
                          style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
                            color: AppColors.brandDark,
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation('wght', 700)],
                            fontSize: 18,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          labelText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
                            color: _primaryText.withOpacity(0.85),
                            fontWeight: FontWeight.w600,
                          ),
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
    }

    // 4. FALLBACK: RAW REUSE LINK
    final reuseMeta = MealPlanEntryParser.entryReuseFrom(entry);
    if (reuseMeta != null) {
      final dk = reuseMeta['dayKey'] ?? reuseMeta['fromDayKey'] ?? '?';
      final sl = reuseMeta['slot'] ?? reuseMeta['fromSlot'] ?? '';
      
      final label = 'Reused from $dk • ${_slotLabel(sl)}';

      return Container(
        height: 86,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Icon(Icons.content_copy_rounded, color: _primaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reuse link',
                    style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
                      color: AppColors.brandDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
                      color: _primaryText.withOpacity(0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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

    // 5. UNKNOWN ITEM
    return Container(
      height: 86,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Unknown item',
              style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
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
        _homeMealCard(context: context, slotKey: 'breakfast', entry: breakfast, titleTint: _breakfastBg),
      ],
      buildLunch: (_) => [
        _homeMealCard(context: context, slotKey: 'lunch', entry: lunch, titleTint: _lunchBg),
      ],
      buildDinner: (_) => [
        _homeMealCard(context: context, slotKey: 'dinner', entry: dinner, titleTint: _dinnerBg),
      ],
      buildSnacks: (_) => [
        _homeMealCard(context: context, slotKey: 'snack1', entry: snack1, titleTint: _snacksBg),
        const SizedBox(height: 10),
        _homeMealCard(context: context, slotKey: 'snack2', entry: snack2, titleTint: _snacksBg),
      ],
      footer: _homeButtons(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _homeSection(context);
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
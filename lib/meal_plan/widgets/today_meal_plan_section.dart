// lib/meal_plan/widgets/today_meal_plan_section.dart
import 'dart:async';
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';

import '../../recipes/recipe_detail_screen.dart';
import '../../recipes/widgets/recipe_card.dart';
import '../../recipes/widgets/smart_recipe_card.dart';
import '../../theme/app_theme.dart';
import '../core/meal_plan_keys.dart';
import 'meal_plan_entry_parser.dart';

class TodayMealPlanSection extends StatelessWidget {
  const TodayMealPlanSection({
    super.key,
    required this.todayRaw,
    this.tomorrowRaw,
    required this.recipes,
    required this.favoriteIds,
    this.childNames = const [],
    this.onOpenMealPlan,
    this.onOpenToday,
    this.onOpenWeek,
    this.onBuildMealPlan,
    this.heroTopText = "TODAY’S",
    this.heroBottomText = "MEAL PLAN",
    this.planTitle,
    this.homeAccordion = false,
    this.homeAlwaysExpanded = false,
    this.onInspireSlot,
    this.onChooseSlot,
    this.onReuseSlot,
    this.onNoteSlot,
    this.onClearSlot,
    this.onAddAnotherSnack,
    this.canSave = false,
    this.onSaveChanges,
    this.homeSectionTitleSize,
    this.homeSectionTitleWeight,
    this.emptyTitle = 'Build your first meal plan',
    this.emptyBody =
        'Choose what you want to include and we’ll generate a plan for you.',
    this.emptyButtonText = 'BUILD MEAL PLAN',
    this.programmeActive = false,
    this.dayInProgramme = true,
    this.onAddAdhocDay,
    this.notScheduledTitle = 'No meal scheduled for this day',
    this.notScheduledBody =
        'Your programme is active, but today isn’t one of your selected days.',
    this.notScheduledButtonText = 'ADD ONE-OFF DAY',
  });

  final Map<String, dynamic> todayRaw;
  final Map<String, dynamic>? tomorrowRaw;
  final List<Map<String, dynamic>> recipes;
  final Set<int> favoriteIds;
  final List<String> childNames;

  final VoidCallback? onOpenMealPlan;
  final VoidCallback? onOpenToday;
  final VoidCallback? onOpenWeek;

  final VoidCallback? onBuildMealPlan;

  final String heroTopText;
  final String heroBottomText;

  final String? planTitle;

  final bool homeAccordion;
  final bool homeAlwaysExpanded;

  final Future<void> Function(String slot)? onInspireSlot;
  final Future<void> Function(String slot)? onChooseSlot;
  final Future<void> Function(String slot)? onReuseSlot;
  final Future<void> Function(String slot)? onNoteSlot;
  final Future<void> Function(String slot)? onClearSlot;

  final Future<void> Function()? onAddAnotherSnack;

  final bool canSave;
  final Future<void> Function()? onSaveChanges;

  final double? homeSectionTitleSize;
  final int? homeSectionTitleWeight;

  final String emptyTitle;
  final String emptyBody;
  final String emptyButtonText;

  final bool programmeActive;
  final bool dayInProgramme;
  final VoidCallback? onAddAdhocDay;

  final String notScheduledTitle;
  final String notScheduledBody;
  final String notScheduledButtonText;

  bool get _editable =>
      onInspireSlot != null ||
      onChooseSlot != null ||
      onReuseSlot != null ||
      onNoteSlot != null ||
      onClearSlot != null ||
      onSaveChanges != null;

  VoidCallback? get _mainAction => onOpenWeek;

  // -----------------------------
  // THEME TOKENS
  // -----------------------------
  Color get _breakfastBg => AppColors.breakfast;
  Color get _lunchBg => AppColors.lunch;
  Color get _dinnerBg => AppColors.dinner;
  Color get _snacksBg => AppColors.snacks;

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

  bool _isLeftoverEntry(Map<String, dynamic>? entry) {
    if (entry == null) return false;
    if (entry['leftover'] == true) return true;
    final src = (entry['source'] ?? '').toString().toLowerCase().trim();
    return src == 'leftover';
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

  Map<String, Map<String, dynamic>> _parseMap(Map<String, dynamic> raw) {
    final parsedBySlot = <String, Map<String, dynamic>>{};
    for (final e in raw.entries) {
      final slotKey = _normaliseSlotKey(e.key.toString());
      final parsed = MealPlanEntryParser.parse(e.value);
      if (parsed == null) continue;
      parsedBySlot[slotKey] = parsed;
    }
    return parsedBySlot;
  }

  Map<String, Map<String, dynamic>> _parsedToday() => _parseMap(todayRaw);

  bool _hasAnyPlannedEntry(Map<String, Map<String, dynamic>> parsedBySlot) {
    if (parsedBySlot.isEmpty) return false;
    for (final e in parsedBySlot.values) {
      final type = (e['type'] ?? '').toString();
      if (type == 'recipe' ||
          type == 'note' ||
          type == 'reuse' ||
          type == 'first_foods') {
        return true;
      }
      if (type == 'clear') {
        final reason = MealPlanEntryParser.clearReason(e);
        if (reason == 'no_suitable_meals_baby') return true;
      }
    }
    return false;
  }

  bool _isPlannedEntry(Map<String, dynamic>? entry) {
    if (entry == null) return false;
    final type = (entry['type'] ?? '').toString();
    if (type == 'recipe' ||
        type == 'note' ||
        type == 'reuse' ||
        type == 'first_foods') {
      return true;
    }
    if (type == 'clear') {
      final reason = MealPlanEntryParser.clearReason(entry);
      return reason == 'no_suitable_meals_baby';
    }
    return false;
  }

  bool _isEmptyOrClear(Map<String, dynamic>? entry) {
    if (entry == null) return true;
    final type = (entry['type'] ?? '').toString().trim();
    if (type.isEmpty) return true;
    if (type != 'clear') return false;

    final reason = MealPlanEntryParser.clearReason(entry);
    return reason != 'no_suitable_meals_baby';
  }

  // -----------------------------
  // EDITING ACTIONS
  // -----------------------------
  List<Widget> _buildActionButtons({
    required String slotKey,
    required bool hasEntry,
  }) {
    if (!_editable) return [];

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

    if (onReuseSlot != null) {
      buttons.add(
        IconButton(
          tooltip: 'Reuse',
          icon: const Icon(Icons.content_copy_rounded),
          onPressed: () => onReuseSlot!(slotKey),
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
    return buttons;
  }

  Widget _slotActions({
    required BuildContext context,
    required String slotKey,
    required bool hasEntry,
  }) {
    final btns = _buildActionButtons(slotKey: slotKey, hasEntry: hasEntry);
    if (btns.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: btns);
  }

  // -----------------------------
  // HERO & HEADER
  // -----------------------------
  Widget _heroHeader(BuildContext context, {String? customTitle}) {
    final showPlanTitle = (planTitle?.trim().isNotEmpty == true);
    final showHeroText =
        heroTopText.trim().isNotEmpty || heroBottomText.trim().isNotEmpty;

    if (!showPlanTitle && !showHeroText && customTitle == null) {
      return const SizedBox.shrink();
    }

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

    final planTitleStyle =
        (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      height: 1.05,
    );

    final displayText = customTitle ??
        '${heroTopText.trim()} ${heroBottomText.trim()}'.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 18, AppSpace.s16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showPlanTitle) ...[
            Text(
              planTitle!.trim(),
              style: planTitleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
          ],
          if (customTitle != null || showHeroText)
            Text(
              displayText,
              style: heroStyle,
            ),
        ],
      ),
    );
  }

  // -----------------------------
  // REUSE & LABELS
  // -----------------------------
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

  String _prettyReuseLabel(Map<String, String> meta) {
    final dk = (meta['dayKey'] ?? '').toString().trim();
    final sl = (meta['slot'] ?? '').toString().trim();
    final prettyDay =
        dk.isNotEmpty ? MealPlanKeys.formatPretty(dk) : 'Unknown day';
    final prettySlot = sl.isNotEmpty ? _slotLabel(sl) : 'Meal';
    return 'Reused from $prettyDay • $prettySlot';
  }

  Widget _favBadge() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
    );
  }

  // -----------------------------
  // CARD BUILDER
  // -----------------------------
  Widget _mealCard({
    required BuildContext context,
    required String slotKey,
    required Map<String, dynamic>? entry,
    String? displaySlotLabel,
  }) {
    if (MealPlanEntryParser.isFirstFoods(entry)) {
      final childName = MealPlanEntryParser.childName(entry);
      final nameText =
          (childName != null && childName.isNotEmpty) ? childName : 'your baby';
      return RecipeCard(
        title: 'First foods for $nameText',
        subtitle: 'Baby snack ideas',
        imageUrl: null,
        trailing:
            _slotActions(context: context, slotKey: slotKey, hasEntry: true),
        onTap: null,
      );
    }

    if ((entry?['type'] ?? '').toString() == 'clear' &&
        MealPlanEntryParser.clearReason(entry) == 'no_suitable_meals_baby') {
      final childName = MealPlanEntryParser.childName(entry);
      final nameText =
          (childName != null && childName.isNotEmpty) ? childName : 'your baby';
      return RecipeCard(
        title: 'No suitable meals for $nameText yet',
        subtitle: 'Try a different slot or add first foods',
        imageUrl: null,
        trailing:
            _slotActions(context: context, slotKey: slotKey, hasEntry: true),
        onTap: null,
      );
    }

    final note = MealPlanEntryParser.entryNoteText(entry);
    if (note != null) {
      return RecipeCard(
        title: note,
        subtitle: 'Note',
        imageUrl: null,
        trailing:
            _slotActions(context: context, slotKey: slotKey, hasEntry: true),
        onTap: () => onNoteSlot?.call(slotKey),
      );
    }

    if (_isEmptyOrClear(entry)) {
      return RecipeCard(
        title: 'Not planned yet',
        subtitle: null,
        imageUrl: null,
        trailing:
            _slotActions(context: context, slotKey: slotKey, hasEntry: false),
        onTap: null,
      );
    }

    final rid = MealPlanEntryParser.entryRecipeId(entry);
    if (rid != null) {
      final r = _byId(rid);
      if (r != null) {
        final displayTitle = _titleOf(r);
        final thumb = _thumbOf(r);
        final fav = _isFavorited(rid);

        if (_isLeftoverEntry(entry)) {
          return RecipeCard(
            title: displayTitle,
            subtitle: 'Leftover',
            imageUrl: thumb,
            badge: fav ? _favBadge() : null,
            trailing: _slotActions(
              context: context,
              slotKey: slotKey,
              hasEntry: true,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
            ),
          );
        }

        final reuseMeta = MealPlanEntryParser.entryReuseFrom(entry);
        if (reuseMeta != null) {
          final subtitleText = _prettyReuseLabel(reuseMeta);
          return RecipeCard(
            title: displayTitle,
            subtitle: subtitleText,
            imageUrl: thumb,
            badge: fav ? _favBadge() : null,
            trailing: _slotActions(
              context: context,
              slotKey: slotKey,
              hasEntry: true,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
            ),
          );
        }

        final rawWarnings = entry?['warnings'];
        final List<dynamic> warnings = (rawWarnings is List) ? rawWarnings : [];

        String? allergyStatus;
        final swapWarning = warnings.firstWhere(
          (w) =>
              (w is Map) &&
              (w['type'] == 'allergy_swap' ||
                  (w['message']?.toString().toLowerCase().contains('swap') ??
                      false)),
          orElse: () => null,
        );

        if (swapWarning != null) {
          allergyStatus = swapWarning['message'] ?? 'Needs swap';
        } else {
          allergyStatus = "Safe for whole family";
        }

        String? ageWarning;
        final ageW = warnings.firstWhere(
          (w) => (w is Map) && w != swapWarning,
          orElse: () => null,
        );
        if (ageW != null) {
          ageWarning = ageW['message'];
        }

        final actions = _buildActionButtons(slotKey: slotKey, hasEntry: true);

        return SmartRecipeCard(
          title: displayTitle,
          imageUrl: thumb,
          isFavorite: fav,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
          ),
          tags: const [],
          allergyStatus: allergyStatus,
          ageWarning: ageWarning,
          childNames: childNames,
          actions: actions,
        );
      }
    }

    final reuseMeta = MealPlanEntryParser.entryReuseFrom(entry);
    if (reuseMeta != null) {
      return RecipeCard(
        title: 'Reuse link',
        subtitle: _prettyReuseLabel(reuseMeta),
        imageUrl: null,
        trailing:
            _slotActions(context: context, slotKey: slotKey, hasEntry: true),
        onTap: () => onReuseSlot?.call(slotKey),
      );
    }

    return RecipeCard(
      title: 'Unknown item',
      subtitle: null,
      imageUrl: null,
      trailing: _slotActions(context: context, slotKey: slotKey, hasEntry: true),
      onTap: null,
    );
  }

  Widget _addAnotherSnackButton(BuildContext context) {
    if (!_editable) return const SizedBox.shrink();
    if (onAddAnotherSnack == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final labelStyle =
        (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 0.2,
    );

    return SizedBox(
      height: 44,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => onAddAnotherSnack!.call(),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.white,
          side: BorderSide(
            color: AppColors.white.withOpacity(0.35),
            width: 2,
          ),
          shape: const StadiumBorder(),
        ),
        child: Text('ADD ANOTHER SNACK', style: labelStyle),
      ),
    );
  }

  Widget _homeButtons(BuildContext context) {
    if (_mainAction == null) return const SizedBox.shrink();

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
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _mainAction,
          style: btnStyle,
          child: Text('VIEW FULL MEAL PLAN', style: labelStyle),
        ),
      ),
    );
  }

  List<MapEntry<String, Map<String, dynamic>>> _plannedSnacks(
    Map<String, Map<String, dynamic>> parsed,
  ) {
    final s1 = parsed['snack1'];
    final s2 = parsed['snack2'];

    final out = <MapEntry<String, Map<String, dynamic>>>[];
    if (_isPlannedEntry(s1)) out.add(MapEntry('snack1', s1!));
    if (_isPlannedEntry(s2)) out.add(MapEntry('snack2', s2!));
    return out;
  }

  Widget _emptyProgrammeNotScheduled(BuildContext context) {
    return Container(
      color: _homePanelBgConst,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroHeader(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, 18),
            child: _EmptyCtaCard(
              title: notScheduledTitle,
              body: notScheduledBody,
              buttonText: notScheduledButtonText,
              onPressed: onAddAdhocDay,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyNoProgrammeYet(BuildContext context) {
    return Container(
      color: _homePanelBgConst,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroHeader(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, 18),
            child: _EmptyCtaCard(
              title: emptyTitle,
              body: emptyBody,
              buttonText: emptyButtonText,
              onPressed: onBuildMealPlan,
            ),
          ),
        ],
      ),
    );
  }

  // Non-home
  Widget _nonHomeSection(BuildContext context) {
    final parsed = _parsedToday();
    final hasPlanned = _hasAnyPlannedEntry(parsed);

    if (!hasPlanned &&
        programmeActive &&
        !dayInProgramme &&
        onAddAdhocDay != null) {
      return _emptyProgrammeNotScheduled(context);
    }

    if (!hasPlanned && onBuildMealPlan != null && !programmeActive) {
      return _emptyNoProgrammeYet(context);
    }

    final breakfast = parsed['breakfast'];
    final lunch = parsed['lunch'];
    final dinner = parsed['dinner'];

    final planned = _plannedSnacks(parsed);
    final hasTwoSnacks = planned.length >= 2;

    final primarySnackKey = planned.isNotEmpty ? planned[0].key : 'snack1';
    final primarySnackEntry =
        planned.isNotEmpty ? planned[0].value : parsed['snack1'];

    final secondarySnackKey = hasTwoSnacks ? planned[1].key : null;
    final secondarySnackEntry = hasTwoSnacks ? planned[1].value : null;

    return Container(
      color: _homePanelBgConst,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroHeader(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, 12),
            child: Column(
              children: [
                _mealCard(context: context, slotKey: 'breakfast', entry: breakfast),
                const SizedBox(height: 10),
                _mealCard(context: context, slotKey: 'lunch', entry: lunch),
                const SizedBox(height: 10),
                _mealCard(context: context, slotKey: 'dinner', entry: dinner),
                const SizedBox(height: 10),
                _mealCard(
                  context: context,
                  slotKey: primarySnackKey,
                  entry: primarySnackEntry,
                  displaySlotLabel: 'Snack 1',
                ),
                if (onAddAnotherSnack != null && planned.length == 1) ...[
                  const SizedBox(height: 10),
                  _addAnotherSnackButton(context),
                ],
                if (secondarySnackKey != null && secondarySnackEntry != null) ...[
                  const SizedBox(height: 10),
                  _mealCard(
                    context: context,
                    slotKey: secondarySnackKey,
                    entry: secondarySnackEntry,
                    displaySlotLabel: 'Snack 2',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------
  // HOME SECTION (Accordion)
  // -----------------------------
  Widget _homeSection(BuildContext context) {
    final parsedToday = _parsedToday();
    final hasPlanned = _hasAnyPlannedEntry(parsedToday);

    if (!hasPlanned &&
        programmeActive &&
        !dayInProgramme &&
        onAddAdhocDay != null) {
      return _emptyProgrammeNotScheduled(context);
    }

    if (!hasPlanned && onBuildMealPlan != null && !programmeActive) {
      return _emptyNoProgrammeYet(context);
    }

    final parsedTomorrow =
        (tomorrowRaw != null) ? _parseMap(tomorrowRaw!) : null;

    final tomorrowHasPlan =
        (parsedTomorrow != null) && _hasAnyPlannedEntry(parsedTomorrow);

    return _HomeDynamicScaffold(
      panelBg: _homePanelBgConst,

      todayParsed: parsedToday,
      tomorrowParsed: parsedTomorrow,
      tomorrowHasPlan: tomorrowHasPlan,
      onAddAdhocDay: onAddAdhocDay,

      heroBuilder: (BuildContext ctx, String dynamicText) {
        return _heroHeader(ctx, customTitle: dynamicText);
      },

      breakfastBg: _breakfastBg,
      lunchBg: _lunchBg,
      dinnerBg: _dinnerBg,
      snacksBg: _snacksBg,
      alwaysExpanded: homeAlwaysExpanded,
      homeSectionTitleSize: homeSectionTitleSize,
      homeSectionTitleWeight: homeSectionTitleWeight,

      buildCard: (entry, slotKey, displayLabel) => _mealCard(
        context: context,
        slotKey: slotKey,
        entry: entry,
        displaySlotLabel: displayLabel,
      ),

      footer: _homeButtons(context),

      onAddAnotherSnack: onAddAnotherSnack,
      addSnackButton: (ctx) => _addAnotherSnackButton(ctx),
      getTitle: (entry) {
        if (entry == null) return 'Nothing planned';
        if (_isLeftoverEntry(entry)) return 'Leftovers';
        if (MealPlanEntryParser.isFirstFoods(entry)) return 'First Foods';
        if (MealPlanEntryParser.entryNoteText(entry) != null) return 'Note';

        final rid = MealPlanEntryParser.entryRecipeId(entry);
        if (rid != null) {
          final r = _byId(rid);
          return r != null ? _titleOf(r) : 'Recipe';
        }
        return 'Nothing planned';
      },
      isPlanned: _isPlannedEntry,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (homeAccordion) return _homeSection(context);
    return _nonHomeSection(context);
  }
}

class _EmptyCtaCard extends StatelessWidget {
  const _EmptyCtaCard({
    required this.title,
    required this.body,
    required this.buttonText,
    required this.onPressed,
  });

  final String title;
  final String body;
  final String buttonText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleStyle =
        (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontSize: 18,
      fontVariations: const [FontVariation('wght', 900)],
      height: 1.15,
    );

    final bodyStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: AppColors.textPrimary.withOpacity(0.80),
      fontWeight: FontWeight.w600,
      height: 1.25,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, 10),
            blurRadius: 24,
            color: Color.fromRGBO(0, 0, 0, 0.08),
          )
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: 8),
          Text(body, style: bodyStyle),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandActive,
                shape: const StadiumBorder(),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dynamic Scaffold:
/// 1. Highlights current time slot
/// 2. Switches to TOMORROW data if > 8pm
/// 3. Shows "Empty Tomorrow" CTA if > 8pm and tomorrow has no plan
/// 4. ✅ Never auto-opens snacks (snacks only open via user tap)
class _HomeDynamicScaffold extends StatefulWidget {
  const _HomeDynamicScaffold({
    required this.panelBg,
    required this.heroBuilder,
    required this.todayParsed,
    required this.tomorrowParsed,
    required this.tomorrowHasPlan,
    required this.onAddAdhocDay,
    required this.breakfastBg,
    required this.lunchBg,
    required this.dinnerBg,
    required this.snacksBg,
    required this.buildCard,
    required this.footer,
    required this.alwaysExpanded,
    this.homeSectionTitleSize,
    this.homeSectionTitleWeight,
    required this.onAddAnotherSnack,
    required this.addSnackButton,
    required this.getTitle,
    required this.isPlanned,
  });

  final Color panelBg;
  final Widget Function(BuildContext context, String dynamicText) heroBuilder;

  final Map<String, Map<String, dynamic>> todayParsed;
  final Map<String, Map<String, dynamic>>? tomorrowParsed;
  final bool tomorrowHasPlan;

  final VoidCallback? onAddAdhocDay;

  final Color breakfastBg;
  final Color lunchBg;
  final Color dinnerBg;
  final Color snacksBg;

  final bool alwaysExpanded;
  final double? homeSectionTitleSize;
  final int? homeSectionTitleWeight;

  final Widget Function(Map<String, dynamic>? entry, String slotKey, String? label)
      buildCard;
  final Widget footer;
  final VoidCallback? onAddAnotherSnack;
  final Widget Function(BuildContext) addSnackButton;
  final String Function(Map<String, dynamic>? entry) getTitle;
  final bool Function(Map<String, dynamic>? entry) isPlanned;

  @override
  State<_HomeDynamicScaffold> createState() => _HomeDynamicScaffoldState();
}

class _HomeDynamicScaffoldState extends State<_HomeDynamicScaffold> {
  String _activeSlot = ''; // neutral; auto-select will set this
  bool _showingTomorrow = false;
  bool _showingTomorrowEmptyState = false;

  // ✅ Snacks can only be opened by user tap
  bool _snacksOpenedByUser = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();

    if (!widget.alwaysExpanded) {
      _applyAutoState(force: true);

      _timer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (!mounted) return;
        _applyAutoState();
      });
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    if (!widget.alwaysExpanded) {
      _applyAutoState(force: true);
    }
  }

  @override
  void didUpdateWidget(_HomeDynamicScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alwaysExpanded) return;

    final tomorrowJustArrived =
        oldWidget.tomorrowParsed == null && widget.tomorrowParsed != null;

    if (tomorrowJustArrived) {
      _applyAutoState(force: true);
      return;
    }

    // If tomorrow plan presence changes, re-evaluate.
    final tomorrowPlanChanged = oldWidget.tomorrowHasPlan != widget.tomorrowHasPlan;
    if (tomorrowPlanChanged) {
      _applyAutoState(force: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _applyAutoState({bool force = false}) {
    final h = DateTime.now().hour;

    bool nextTomorrow = false;
    bool nextTomorrowEmpty = false;

    // ✅ IMPORTANT: never auto-select snacks
    String nextSlot = 'breakfast';

    if (h >= 4 && h < 11) {
      nextSlot = 'breakfast';
    } else if (h >= 11 && h < 15) {
      nextSlot = 'lunch';
    } else if (h >= 15 && h < 20) {
      nextSlot = 'dinner';
    } else {
      // After 8pm
      if (widget.tomorrowParsed != null) {
        nextTomorrow = true;

        // If tomorrow has no plan and you want empty CTA
        if (!widget.tomorrowHasPlan && widget.onAddAdhocDay != null) {
          nextTomorrowEmpty = true;
          nextSlot = '';
        } else {
          // ✅ Tomorrow default: breakfast (never snacks)
          nextSlot = 'breakfast';
        }
      } else {
        // No tomorrow data yet: still open breakfast
        nextSlot = 'breakfast';
      }
    }

    // If somehow snacks is active but user didn't open it, force a reset.
    if (_activeSlot == 'snacks' && !_snacksOpenedByUser) {
      force = true;
      nextSlot = nextSlot.isEmpty ? '' : 'breakfast';
    }

    if (force ||
        _activeSlot != nextSlot ||
        _showingTomorrow != nextTomorrow ||
        _showingTomorrowEmptyState != nextTomorrowEmpty) {
      setState(() {
        _activeSlot = nextSlot;
        _showingTomorrow = nextTomorrow;
        _showingTomorrowEmptyState = nextTomorrowEmpty;

        // Reset the snacks user-open flag whenever auto state runs.
        _snacksOpenedByUser = false;
      });
    }
  }

  String _getDynamicHeaderText() {
    if (widget.alwaysExpanded) return "HERE’S SOME IDEAS FOR TODAY";
    if (_showingTomorrowEmptyState) return "HERE’S HOW TOMORROW LOOKS";

    if (_showingTomorrow) {
      switch (_activeSlot) {
        case 'breakfast':
          return "HERE’S TOMORROW’S BREAKFAST";
        case 'lunch':
          return "HERE’S TOMORROW’S LUNCH";
        case 'dinner':
          return "HERE’S TOMORROW’S DINNER";
        case 'snacks':
          return "HERE’S TOMORROW’S SNACKS";
        default:
          return "HERE’S TOMORROW’S PLAN";
      }
    }

    switch (_activeSlot) {
      case 'breakfast':
        return "YOUR PLAN FOR BREAKFAST";
      case 'lunch':
        return "YOUR PLAN FOR LUNCH";
      case 'dinner':
        return "YOUR PLAN FOR DINNER";
      case 'snacks':
        return "YOUR HEALTHY SNACKS";
      default:
        return "YOUR DAILY MEAL PLAN";
    }
  }

  void _toggle(String slot) {
    if (widget.alwaysExpanded) return;

    setState(() {
      if (_activeSlot == slot) {
        _activeSlot = '';
        if (slot == 'snacks') _snacksOpenedByUser = false;
      } else {
        _activeSlot = slot;
        _snacksOpenedByUser = (slot == 'snacks');
      }
    });
  }

  bool _isActive(String slot) {
    if (widget.alwaysExpanded) return true;

    // ✅ Snacks can only be expanded if user explicitly opened it
    if (slot == 'snacks' && !_snacksOpenedByUser) return false;

    // If snacks somehow became active without user action, don't expand it.
    if (_activeSlot == 'snacks' && !_snacksOpenedByUser) return false;

    return _activeSlot == slot;
  }

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

  Map<String, dynamic>? _getEntry(String slotKey) {
    if (_showingTomorrow && widget.tomorrowParsed != null) {
      return widget.tomorrowParsed![slotKey];
    }
    return widget.todayParsed[slotKey];
  }

  List<Widget> _buildSnacks() {
    final data = (_showingTomorrow && widget.tomorrowParsed != null)
        ? widget.tomorrowParsed!
        : widget.todayParsed;

    final s1 = data['snack1'];
    final s2 = data['snack2'];

    final planned = <MapEntry<String, Map<String, dynamic>>>[];
    if (widget.isPlanned(s1)) planned.add(MapEntry('snack1', s1!));
    if (widget.isPlanned(s2)) planned.add(MapEntry('snack2', s2!));

    final hasOne = planned.length == 1;
    final hasTwo = planned.length >= 2;

    final showAddBtn = widget.onAddAnotherSnack != null && hasOne && !_showingTomorrow;

    final pKey = (hasOne || hasTwo) ? planned[0].key : 'snack1';
    final pEntry = (hasOne || hasTwo) ? planned[0].value : data['snack1'];

    final sKey = hasTwo ? planned[1].key : null;
    final sEntry = hasTwo ? planned[1].value : null;

    return [
      widget.buildCard(pEntry, pKey, 'Snack 1'),
      if (showAddBtn) ...[
        const SizedBox(height: 10),
        widget.addSnackButton(context),
      ],
      if (sKey != null && sEntry != null) ...[
        const SizedBox(height: 10),
        widget.buildCard(sEntry, sKey, 'Snack 2'),
      ]
    ];
  }

  String _getSnacksPeekTitle() {
  final data = (_showingTomorrow && widget.tomorrowParsed != null)
      ? widget.tomorrowParsed!
      : widget.todayParsed;

  final s1 = data['snack1'];
  final s2 = data['snack2'];

  // Prefer Snack 1 if planned, otherwise Snack 2.
  if (widget.isPlanned(s1)) {
    return widget.getTitle(s1);
  }
  if (widget.isPlanned(s2)) {
    return widget.getTitle(s2);
  }

  return "Nothing planned";
}
  @override
  Widget build(BuildContext context) {
    if (_showingTomorrowEmptyState) {
      return Container(
        color: widget.panelBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.heroBuilder(context, _getDynamicHeaderText()),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, 18),
              child: _EmptyCtaCard(
                title: 'Nothing planned yet!',
                body: 'Get a head start on tomorrow by creating your plan now.',
                buttonText: 'CREATE PLAN',
                onPressed: widget.onAddAdhocDay,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: widget.panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.heroBuilder(context, _getDynamicHeaderText()),
          _buildItem(
            slotKey: 'breakfast',
            title: 'BREAKFAST',
            peekTitle: widget.getTitle(_getEntry('breakfast')),
            bg: widget.breakfastBg,
            children: [widget.buildCard(_getEntry('breakfast'), 'breakfast', null)],
          ),
          _buildItem(
            slotKey: 'lunch',
            title: 'LUNCH',
            peekTitle: widget.getTitle(_getEntry('lunch')),
            bg: widget.lunchBg,
            children: [widget.buildCard(_getEntry('lunch'), 'lunch', null)],
          ),
          _buildItem(
            slotKey: 'dinner',
            title: 'DINNER',
            peekTitle: widget.getTitle(_getEntry('dinner')),
            bg: widget.dinnerBg,
            children: [widget.buildCard(_getEntry('dinner'), 'dinner', null)],
          ),
          _buildItem(
            slotKey: 'snacks',
            title: 'HEALTHY SNACKS',
            peekTitle: _getSnacksPeekTitle(),
            bg: widget.snacksBg,
            children: _buildSnacks(),
          ),
          widget.footer,
        ],
      ),
    );
  }

  Widget _buildItem({
    required String slotKey,
    required String title,
    required String peekTitle,
    required Color bg,
    required List<Widget> children,
  }) {
    final expanded = _isActive(slotKey);
    final theme = Theme.of(context);
    final base = (theme.textTheme.titleLarge ?? const TextStyle());

    final wght = _clampWght(widget.homeSectionTitleWeight ?? 800);
    final fontSize = widget.homeSectionTitleSize ?? 21;

    final titleStyle = base.copyWith(
      color: Colors.white,
      fontSize: expanded ? fontSize : fontSize * 0.85,
      fontWeight: _fontWeightFromWght(wght),
      fontVariations: [FontVariation('wght', wght.toDouble())],
      letterSpacing: expanded ? 1.25 : 1.0,
      height: 1.0,
    );

    final peekStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Colors.white.withOpacity(0.85),
      height: 1.2,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.fastOutSlowIn,
      margin: EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, expanded ? 12 : 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: expanded
            ? [
                BoxShadow(
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                  color: bg.withOpacity(0.25),
                )
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggle(slotKey),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(expanded ? 16 : 14),
              child: Row(
                children: [
                  Text(title, style: titleStyle),
                  const SizedBox(width: 12),
                  if (expanded)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: Colors.white.withOpacity(0.25),
                      ),
                    )
                  else
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 1.5,
                            height: 14,
                            color: Colors.white.withOpacity(0.4),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              peekTitle,
                              style: peekStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 10),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(children: children),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

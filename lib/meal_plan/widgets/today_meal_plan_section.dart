// lib/meal_plan/widgets/today_meal_plan_section.dart
import 'dart:async';
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';

import '../../recipes/recipe_detail_screen.dart';
import '../../recipes/widgets/recipe_card.dart'; // Still used for non-smart variants (empty/notes)
import '../../recipes/widgets/smart_recipe_card.dart'; // ✅ The Smart Component
import '../../theme/app_theme.dart';
import '../core/meal_plan_keys.dart';
import 'meal_plan_entry_parser.dart';

class TodayMealPlanSection extends StatelessWidget {
  const TodayMealPlanSection({
    super.key,
    required this.todayRaw,
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
  // EDITING ACTIONS (Used by non-smart cards & Smart wrapper)
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

  // Fallback for legacy calls (notes, empty slots)
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
  // HEADER (shared)
  // -----------------------------
  Widget _heroHeader(BuildContext context) {
    final showPlanTitle = (planTitle?.trim().isNotEmpty == true);
    final showHeroText =
        heroTopText.trim().isNotEmpty || heroBottomText.trim().isNotEmpty;

    if (!showPlanTitle && !showHeroText) {
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
          if (showHeroText)
            Text(
              '${heroTopText.trim()} ${heroBottomText.trim()}'.trim(),
              style: heroStyle,
            ),
        ],
      ),
    );
  }

  // -----------------------------
  // LABELS + REUSE
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
  // ✅ UNIFIED CARD BUILDER
  // -----------------------------
  Widget _mealCard({
    required BuildContext context,
    required String slotKey,
    required Map<String, dynamic>? entry,
    String? displaySlotLabel,
  }) {
    // 0. FIRST FOODS
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

    // 0.5 NO SUITABLE MEALS
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

    // 1. NOTES
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

    // 2. EMPTY SLOT
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

    // 3. RECIPE
    final rid = MealPlanEntryParser.entryRecipeId(entry);
    if (rid != null) {
      final r = _byId(rid);
      if (r != null) {
        final displayTitle = _titleOf(r);
        final thumb = _thumbOf(r);
        final fav = _isFavorited(rid);

        // Handle Leftover logic at card level if needed, or inside SmartCard
        if (_isLeftoverEntry(entry)) {
           // Leftovers act like reused items usually
           return RecipeCard(
            title: displayTitle,
            subtitle: 'Leftover',
            imageUrl: thumb,
            badge: fav ? _favBadge() : null,
            trailing: _slotActions(context: context, slotKey: slotKey, hasEntry: true),
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
            trailing: _slotActions(context: context, slotKey: slotKey, hasEntry: true),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
            ),
          );
        } else {
          // ✅ NORMAL RECIPE: USE SMART COMPONENT
          
          // A. Extract Warnings
          final rawWarnings = entry?['warnings'];
          final List<dynamic> warnings = (rawWarnings is List) ? rawWarnings : [];

          // B. Extract Allergy Status
          String? allergyStatus; 
          // If the entry parser set a warning for allergy, use it.
          // Otherwise, we assume safe if this card was allowed in the plan.
          // Or we can default to "Safe for whole family".
          
          final swapWarning = warnings.firstWhere(
            (w) => (w is Map) && (w['type'] == 'allergy_swap' || (w['message']?.toString().toLowerCase().contains('swap') ?? false)),
            orElse: () => null,
          );

          if (swapWarning != null) {
            allergyStatus = swapWarning['message'] ?? 'Needs swap';
          } else {
            allergyStatus = "Safe for whole family"; // Default positive
          }

          // C. Extract Age Warning
          String? ageWarning;
          final ageW = warnings.firstWhere(
            (w) => (w is Map) && w != swapWarning, 
            orElse: () => null
          );
          if (ageW != null) {
            ageWarning = ageW['message'];
          }

          // D. Generate Buttons for SmartCard
          final actions = _buildActionButtons(slotKey: slotKey, hasEntry: true);

          return SmartRecipeCard(
            title: displayTitle,
            imageUrl: thumb,
            isFavorite: fav,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
            ),
            
            // Pass Data
            tags: const [], // Meal plan hides tags for cleaner look
            allergyStatus: allergyStatus,
            ageWarning: ageWarning,
            childNames: childNames,
            
            // Pass Buttons
            actions: actions,
          );
        }
      }
    }

    // 4. FALLBACK
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

    // 5. UNKNOWN
    return RecipeCard(
      title: 'Unknown item',
      subtitle: null,
      imageUrl: null,
      trailing:
          _slotActions(context: context, slotKey: slotKey, hasEntry: true),
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

  // ... (Rest of file: _plannedSnacks, _emptyProgrammeNotScheduled, _emptyNoProgrammeYet, _nonHomeSection, _homeSection, _homeAccordionItem, _EmptyCtaCard, _HomeAccordionScaffold) ...
  // (These sections remain unchanged from your base code, just ensure they are included in the file)
  
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
            padding:
                const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, 18),
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
            padding:
                const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, 18),
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

  Widget _nonHomeSection(BuildContext context) {
    final parsed = _parsedBySlot();
    final hasPlanned = _hasAnyPlannedEntry(parsed);

    if (!hasPlanned && programmeActive && !dayInProgramme && onAddAdhocDay != null) {
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

  Widget _homeSection(BuildContext context) {
    final parsed = _parsedBySlot();
    final hasPlanned = _hasAnyPlannedEntry(parsed);

    if (!hasPlanned && programmeActive && !dayInProgramme && onAddAdhocDay != null) {
      return _emptyProgrammeNotScheduled(context);
    }

    if (!hasPlanned && onBuildMealPlan != null && !programmeActive) {
      return _emptyNoProgrammeYet(context);
    }

    final breakfast = parsed['breakfast'];
    final lunch = parsed['lunch'];
    final dinner = parsed['dinner'];

    final planned = _plannedSnacks(parsed);

    final hasOneSnack = planned.length == 1;
    final hasTwoSnacks = planned.length >= 2;

    final showAddAnotherSnack = onAddAnotherSnack != null && hasOneSnack;

    final primarySnackKey =
        (hasOneSnack || hasTwoSnacks) ? planned[0].key : 'snack1';
    final primarySnackEntry =
        (hasOneSnack || hasTwoSnacks) ? planned[0].value : parsed['snack1'];

    final secondarySnackKey = hasTwoSnacks ? planned[1].key : null;
    final secondarySnackEntry = hasTwoSnacks ? planned[1].value : null;

    return _HomeAccordionScaffold(
      panelBg: _homePanelBgConst,
      hero: _heroHeader(context),
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
        _mealCard(context: context, slotKey: 'breakfast', entry: breakfast),
      ],
      buildLunch: (_) => [
        _mealCard(context: context, slotKey: 'lunch', entry: lunch),
      ],
      buildDinner: (_) => [
        _mealCard(context: context, slotKey: 'dinner', entry: dinner),
      ],
      buildSnacks: (_) => [
        _mealCard(
          context: context,
          slotKey: primarySnackKey,
          entry: primarySnackEntry,
          displaySlotLabel: 'Snack 1',
        ),
        if (showAddAnotherSnack) ...[
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
      footer: _homeButtons(context),
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
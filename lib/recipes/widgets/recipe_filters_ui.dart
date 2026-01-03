// lib/recipes/widgets/recipe_filters_ui.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

// ✅ UPDATED: Supports "specificPeople" (plural)
enum SuitabilityMode { wholeFamily, allChildren, specificPeople }
enum PersonType { adult, child }

class ProfilePerson {
  final String id;
  final PersonType type;
  final String name;
  final bool hasAllergies;
  final List<String> allergies;

  const ProfilePerson({
    required this.id,
    required this.type,
    required this.name,
    required this.hasAllergies,
    required this.allergies,
  });
}

class RecipeFilterSelection {
  final String course;
  final String cuisine;
  final String suitableFor; // age
  final String nutritionTag;
  final String collection;

  const RecipeFilterSelection({
    this.course = 'All',
    this.cuisine = 'All',
    this.suitableFor = 'All',
    this.nutritionTag = 'All',
    this.collection = 'All',
  });

  int get activeCount {
    int n = 0;
    if (course != 'All') n++;
    if (cuisine != 'All') n++;
    if (suitableFor != 'All') n++;
    if (nutritionTag != 'All') n++;
    if (collection != 'All') n++;
    return n;
  }

  RecipeFilterSelection copyWith({
    String? course,
    String? cuisine,
    String? suitableFor,
    String? nutritionTag,
    String? collection,
  }) {
    return RecipeFilterSelection(
      course: course ?? this.course,
      cuisine: cuisine ?? this.cuisine,
      suitableFor: suitableFor ?? this.suitableFor,
      nutritionTag: nutritionTag ?? this.nutritionTag,
      collection: collection ?? this.collection,
    );
  }
}

class AllergiesSelection {
  final bool enabled;
  final SuitabilityMode mode;

  /// ✅ multi-select people (only when mode == specificPeople)
  final Set<String> personIds;

  final bool includeSwaps;

  const AllergiesSelection({
    this.enabled = true,
    this.mode = SuitabilityMode.wholeFamily,
    this.personIds = const {},
    this.includeSwaps = false,
  });

  int get activeCount {
    if (!enabled) return 0;
    int n = 1;
    if (includeSwaps) n += 1;
    return n;
  }

  AllergiesSelection copyWith({
    bool? enabled,
    SuitabilityMode? mode,
    Set<String>? personIds,
    bool? includeSwaps,
  }) {
    return AllergiesSelection(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      personIds: personIds ?? this.personIds,
      includeSwaps: includeSwaps ?? this.includeSwaps,
    );
  }
}

///
/// ✅ Single place to customise Filters UI styling.
///
class _FStyle {
  static const String font = 'Montserrat';

  // Core colours
  static const Color brand = AppColors.brandDark;
  static const Color sheetBg = Colors.white;
  static const Color pillBg = Colors.white;
  static const Color border = Color(0x14000000);
  static const Color muted = Color(0x8C000000);
  static const Color chipBg = AppColors.brandDark;
  static const Color chipText = Colors.white;

  // Radii
  static const double pillRadius = 8;
  static const double chipRadius = 999;
  static const double sheetRadius = 20;
  static const double fieldRadius = 12;
  static const double ctaRadius = 12;

  // Sizes
  static const double pillHeight = 44;
  static const double chipHeight = 34;
  static const double ctaHeight = 48;

  // Spacing
  static const EdgeInsets pillPadding = EdgeInsets.symmetric(horizontal: 14);
  static const EdgeInsets sheetPadding = EdgeInsets.fromLTRB(16, 0, 16, 16);
  static const EdgeInsets chipPadding = EdgeInsets.symmetric(horizontal: 12);

  // Typography
  static const TextStyle pillLabel = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.0,
    color: AppColors.brandDark,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: font,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.0,
    color: Colors.white,
  );

  static const TextStyle chip = TextStyle(
    fontFamily: font,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.0,
    color: chipText,
  );

  static const TextStyle sheetTitle = TextStyle(
    fontFamily: font,
    fontSize: 18,
    fontWeight: FontWeight.w900,
    fontVariations: [FontVariation('wght', 900)],
    letterSpacing: 0.6,
    height: 1.0,
    color: AppColors.brandDark,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontFamily: font,
    fontSize: 11,
    fontWeight: FontWeight.w900,
    fontVariations: [FontVariation('wght', 900)],
    letterSpacing: 0.8,
    height: 1.0,
    color: Color(0x8C000000),
  );

  static const TextStyle rowTitle = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    height: 1.0,
    color: AppColors.brandDark,
  );

  static const TextStyle rowValue = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.0,
    color: Colors.black87,
  );

  static const TextStyle helper = TextStyle(
    fontFamily: font,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 1.2,
    color: Color(0xA0000000),
  );

  static const TextStyle cta = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w900,
    fontVariations: [FontVariation('wght', 900)],
    letterSpacing: 0.6,
    height: 1.0,
    color: Colors.white,
  );

  static const TextStyle personName = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    color: Colors.black,
  );

  static ButtonStyle ctaButtonStyle() => ElevatedButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ctaRadius),
        ),
        elevation: 0,
      );
}

enum _DrawerRoute {
  filters,
  allergies,

  // selector sub-pages (inside same drawer)
  selectCourse,
  selectCuisine,
  selectAge,
  selectNutrition,
  selectCollection,
}

class RecipeFilterBar extends StatelessWidget {
  const RecipeFilterBar({
    super.key,
    required this.filters,
    required this.allergies,
    required this.courseOptions,
    required this.cuisineOptions,
    required this.suitableForOptions,
    required this.nutritionOptions,
    required this.collectionOptions,
    required this.onFiltersApplied,
    required this.onAllergiesApplied,
    required this.adults,
    required this.children,
    this.lockCourse = false,
    this.lockCollection = false,
    this.lockCuisine = false,
    this.lockSuitableFor = false,
    this.lockNutrition = false,
    this.householdLoading = false,
    this.householdError,
    this.onRetryHousehold,

    // ✅ NEW: pass ID -> label maps so IDs show as words
    this.courseLabelsById = const {},
    this.cuisineLabelsById = const {},
    this.ageLabelsById = const {},
    this.nutritionLabelsById = const {},
    this.collectionLabelsById = const {},
  });

  final RecipeFilterSelection filters;
  final AllergiesSelection allergies;

  final List<String> courseOptions;
  final List<String> cuisineOptions;
  final List<String> suitableForOptions;
  final List<String> nutritionOptions;
  final List<String> collectionOptions;

  final ValueChanged<RecipeFilterSelection> onFiltersApplied;
  final ValueChanged<AllergiesSelection> onAllergiesApplied;

  final List<ProfilePerson> adults;
  final List<ProfilePerson> children;

  final bool lockCourse;
  final bool lockCollection;
  final bool lockCuisine;
  final bool lockSuitableFor;
  final bool lockNutrition;

  final bool householdLoading;
  final String? householdError;
  final VoidCallback? onRetryHousehold;

  // ✅ label maps
  final Map<String, String> courseLabelsById;
  final Map<String, String> cuisineLabelsById;
  final Map<String, String> ageLabelsById;
  final Map<String, String> nutritionLabelsById;
  final Map<String, String> collectionLabelsById;

  List<ProfilePerson> get _allPeople => [...adults, ...children];

  String _allergiesChipLabel(AllergiesSelection a) {
    if (!a.enabled) return 'Allergies off';
    if (a.mode == SuitabilityMode.wholeFamily) return 'Whole family';
    if (a.mode == SuitabilityMode.allChildren) return 'All children';

    if (a.personIds.isNotEmpty) {
      final names = _allPeople.where((p) => a.personIds.contains(p.id)).map((p) => p.name).toList();
      if (names.isNotEmpty) {
        if (names.length == 1) return names.first;
        if (names.length == 2) return '${names[0]} & ${names[1]}';
        return '${names.length} people';
      }
    }
    return 'Whole family';
  }

  String _labelFor(String raw, Map<String, String> map) {
    if (raw == 'All') return 'Any';
    return map[raw] ?? raw;
  }

  Future<void> _openDrawer(BuildContext context, _DrawerRoute initial) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _FStyle.sheetBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(_FStyle.sheetRadius)),
      ),
      builder: (sheetCtx) {
        return _SheetScrollShell(
          child: _DrawerNavigator(
            initialRoute: initial,
            initialFilters: filters,
            initialAllergies: allergies,
            courseOptions: courseOptions,
            cuisineOptions: cuisineOptions,
            suitableForOptions: suitableForOptions,
            nutritionOptions: nutritionOptions,
            collectionOptions: collectionOptions,
            lockCourse: lockCourse,
            lockCuisine: lockCuisine,
            lockSuitableFor: lockSuitableFor,
            lockNutrition: lockNutrition,
            lockCollection: lockCollection,
            adults: adults,
            children: children,
            householdLoading: householdLoading,
            householdError: householdError,
            onRetryHousehold: onRetryHousehold,
            onCloseSheet: () => Navigator.of(sheetCtx).pop(),
            onApplyFilters: (next) {
              onFiltersApplied(next);
              Navigator.of(sheetCtx).pop();
            },
            onApplyAllergies: (next) {
              onAllergiesApplied(next);
              Navigator.of(sheetCtx).pop();
            },

            // ✅ pass maps down
            courseLabelsById: courseLabelsById,
            cuisineLabelsById: cuisineLabelsById,
            ageLabelsById: ageLabelsById,
            nutritionLabelsById: nutritionLabelsById,
            collectionLabelsById: collectionLabelsById,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filterCount = filters.activeCount;
    final allergyCount = allergies.activeCount;

    final chips = <_ChipSpec>[];

    if (filters.course != 'All') {
      chips.add(_ChipSpec(
        label: _labelFor(filters.course, courseLabelsById),
        onClear: () => onFiltersApplied(filters.copyWith(course: 'All')),
      ));
    }
    if (filters.cuisine != 'All') {
      chips.add(_ChipSpec(
        label: _labelFor(filters.cuisine, cuisineLabelsById),
        onClear: () => onFiltersApplied(filters.copyWith(cuisine: 'All')),
      ));
    }
    if (filters.suitableFor != 'All') {
      chips.add(_ChipSpec(
        label: _labelFor(filters.suitableFor, ageLabelsById),
        onClear: () => onFiltersApplied(filters.copyWith(suitableFor: 'All')),
      ));
    }
    if (filters.nutritionTag != 'All') {
      chips.add(_ChipSpec(
        label: _labelFor(filters.nutritionTag, nutritionLabelsById),
        onClear: () => onFiltersApplied(filters.copyWith(nutritionTag: 'All')),
      ));
    }
    if (filters.collection != 'All') {
      chips.add(_ChipSpec(
        label: _labelFor(filters.collection, collectionLabelsById),
        onClear: () => onFiltersApplied(filters.copyWith(collection: 'All')),
      ));
    }

    if (allergies.enabled) {
      chips.add(_ChipSpec(
        label: _allergiesChipLabel(allergies),
        onClear: () => onAllergiesApplied(
          allergies.copyWith(
            enabled: false,
            mode: SuitabilityMode.wholeFamily,
            personIds: const {},
            includeSwaps: false,
          ),
        ),
      ));

      if (allergies.includeSwaps) {
        chips.add(_ChipSpec(
          label: 'Swaps on',
          onClear: () => onAllergiesApplied(allergies.copyWith(includeSwaps: false)),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _PillButton(
                label: 'Filters',
                count: filterCount,
                onTap: () => _openDrawer(context, _DrawerRoute.filters),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PillButton(
                label: 'Allergies',
                count: allergyCount,
                onTap: () => _openDrawer(context, _DrawerRoute.allergies),
              ),
            ),
          ],
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                const SizedBox(width: 2),
                for (final c in chips) ...[
                  _FilterChip(label: c.label, onClear: c.onClear),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ChipSpec {
  const _ChipSpec({required this.label, required this.onClear});
  final String label;
  final VoidCallback onClear;
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showCount = count > 0;

    return Material(
      color: _FStyle.pillBg,
      borderRadius: BorderRadius.circular(_FStyle.pillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_FStyle.pillRadius),
        onTap: onTap,
        child: Container(
          height: _FStyle.pillHeight,
          padding: _FStyle.pillPadding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_FStyle.pillRadius),
            border: Border.all(color: _FStyle.border),
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: _FStyle.pillLabel)),
              if (showCount) ...[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _FStyle.brand,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$count', style: _FStyle.badge),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, size: 20, color: _FStyle.brand.withOpacity(0.90)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onClear});
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _FStyle.chipHeight,
      padding: _FStyle.chipPadding,
      decoration: BoxDecoration(
        color: _FStyle.chipBg,
        borderRadius: BorderRadius.circular(_FStyle.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: _FStyle.chip),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClear,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetScrollShell extends StatelessWidget {
  const _SheetScrollShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Keep it simple: let the sheet size naturally, still safe for keyboard insets.
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: child,
      ),
    );
  }
}

/// --------------------
/// Drawer Navigator Model
/// --------------------
class _DrawerModel extends ChangeNotifier {
  RecipeFilterSelection filters;
  AllergiesSelection allergies;

  _DrawerModel({
    required this.filters,
    required this.allergies,
  });

  void setFilters(RecipeFilterSelection next) {
    filters = next;
    notifyListeners();
  }

  void setAllergies(AllergiesSelection next) {
    allergies = next;
    notifyListeners();
  }
}

class _DrawerScope extends InheritedNotifier<_DrawerModel> {
  const _DrawerScope({
    required _DrawerModel model,
    required super.child,
  }) : super(notifier: model);

  static _DrawerModel modelOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DrawerScope>();
    assert(scope != null, '_DrawerScope not found');
    return scope!.notifier!;
  }
}

/// ✅ No-animation route (removes the janky page transitions)
class _NoAnimRoute<T> extends PageRouteBuilder<T> {
  _NoAnimRoute({required Widget page, RouteSettings? settings})
      : super(
          settings: settings,
          pageBuilder: (_, __, ___) => page,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, __, ___, child) => child,
        );
}

/// --------------------
/// Drawer Navigator (single sheet, stepped navigation, NO animations)
/// --------------------
class _DrawerNavigator extends StatefulWidget {
  const _DrawerNavigator({
    required this.initialRoute,
    required this.initialFilters,
    required this.initialAllergies,
    required this.courseOptions,
    required this.cuisineOptions,
    required this.suitableForOptions,
    required this.nutritionOptions,
    required this.collectionOptions,
    required this.lockCourse,
    required this.lockCuisine,
    required this.lockSuitableFor,
    required this.lockNutrition,
    required this.lockCollection,
    required this.adults,
    required this.children,
    required this.householdLoading,
    required this.householdError,
    required this.onRetryHousehold,
    required this.onCloseSheet,
    required this.onApplyFilters,
    required this.onApplyAllergies,

    // label maps
    required this.courseLabelsById,
    required this.cuisineLabelsById,
    required this.ageLabelsById,
    required this.nutritionLabelsById,
    required this.collectionLabelsById,
  });

  final _DrawerRoute initialRoute;

  final RecipeFilterSelection initialFilters;
  final AllergiesSelection initialAllergies;

  final List<String> courseOptions;
  final List<String> cuisineOptions;
  final List<String> suitableForOptions;
  final List<String> nutritionOptions;
  final List<String> collectionOptions;

  final bool lockCourse;
  final bool lockCuisine;
  final bool lockSuitableFor;
  final bool lockNutrition;
  final bool lockCollection;

  final List<ProfilePerson> adults;
  final List<ProfilePerson> children;

  final bool householdLoading;
  final String? householdError;
  final VoidCallback? onRetryHousehold;

  final VoidCallback onCloseSheet;
  final ValueChanged<RecipeFilterSelection> onApplyFilters;
  final ValueChanged<AllergiesSelection> onApplyAllergies;

  final Map<String, String> courseLabelsById;
  final Map<String, String> cuisineLabelsById;
  final Map<String, String> ageLabelsById;
  final Map<String, String> nutritionLabelsById;
  final Map<String, String> collectionLabelsById;

  @override
  State<_DrawerNavigator> createState() => _DrawerNavigatorState();
}

class _DrawerNavigatorState extends State<_DrawerNavigator> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  late final _DrawerModel _model;

  @override
  void initState() {
    super.initState();
    _model = _DrawerModel(filters: widget.initialFilters, allergies: widget.initialAllergies);
  }

  void pop() => _navKey.currentState?.maybePop();
  void push(_DrawerRoute r) => _navKey.currentState?.pushNamed(r.name);

  String _labelFor(String raw, Map<String, String> map) {
    if (raw == 'All') return 'Any';
    return map[raw] ?? raw;
  }

  Route<dynamic> _routeFor(RouteSettings settings) {
    final name = settings.name ?? widget.initialRoute.name;

    Widget page;

    switch (name) {
      case 'filters':
        page = _FiltersPage(
          courseOptions: widget.courseOptions,
          cuisineOptions: widget.cuisineOptions,
          suitableForOptions: widget.suitableForOptions,
          nutritionOptions: widget.nutritionOptions,
          collectionOptions: widget.collectionOptions,
          lockCourse: widget.lockCourse,
          lockCuisine: widget.lockCuisine,
          lockSuitableFor: widget.lockSuitableFor,
          lockNutrition: widget.lockNutrition,
          lockCollection: widget.lockCollection,
          onClose: widget.onCloseSheet,
          onGoSelect: push,
          onApply: () => widget.onApplyFilters(_model.filters),
          courseLabelsById: widget.courseLabelsById,
          cuisineLabelsById: widget.cuisineLabelsById,
          ageLabelsById: widget.ageLabelsById,
          nutritionLabelsById: widget.nutritionLabelsById,
          collectionLabelsById: widget.collectionLabelsById,
        );
        break;

      case 'allergies':
        page = _AllergiesPage(
          adults: widget.adults,
          children: widget.children,
          householdLoading: widget.householdLoading,
          householdError: widget.householdError,
          onRetryHousehold: widget.onRetryHousehold,
          onClose: widget.onCloseSheet,
          onApply: () => widget.onApplyAllergies(_model.allergies),
        );
        break;

      case 'selectCourse':
        page = _SelectorPage(
          title: 'Course',
          options: widget.courseOptions.isEmpty ? const ['All'] : widget.courseOptions,
          current: _model.filters.course,
          onClose: widget.onCloseSheet,
          onBack: pop,
          display: (v) => _labelFor(v, widget.courseLabelsById),
          onSelected: (v) {
            _model.setFilters(_model.filters.copyWith(course: v));
            pop();
          },
        );
        break;

      case 'selectCuisine':
        page = _SelectorPage(
          title: 'Cuisine',
          options: widget.cuisineOptions.isEmpty ? const ['All'] : widget.cuisineOptions,
          current: _model.filters.cuisine,
          onClose: widget.onCloseSheet,
          onBack: pop,
          display: (v) => _labelFor(v, widget.cuisineLabelsById),
          onSelected: (v) {
            _model.setFilters(_model.filters.copyWith(cuisine: v));
            pop();
          },
        );
        break;

      case 'selectAge':
        page = _SelectorPage(
          title: 'Age range',
          options: widget.suitableForOptions.isEmpty ? const ['All'] : widget.suitableForOptions,
          current: _model.filters.suitableFor,
          onClose: widget.onCloseSheet,
          onBack: pop,
          display: (v) => _labelFor(v, widget.ageLabelsById),
          onSelected: (v) {
            _model.setFilters(_model.filters.copyWith(suitableFor: v));
            pop();
          },
        );
        break;

      case 'selectNutrition':
        page = _SelectorPage(
          title: 'Nutrition',
          options: widget.nutritionOptions.isEmpty ? const ['All'] : widget.nutritionOptions,
          current: _model.filters.nutritionTag,
          onClose: widget.onCloseSheet,
          onBack: pop,
          display: (v) => _labelFor(v, widget.nutritionLabelsById),
          onSelected: (v) {
            _model.setFilters(_model.filters.copyWith(nutritionTag: v));
            pop();
          },
        );
        break;

      case 'selectCollection':
        page = _SelectorPage(
          title: 'Collection',
          options: widget.collectionOptions.isEmpty ? const ['All'] : widget.collectionOptions,
          current: _model.filters.collection,
          onClose: widget.onCloseSheet,
          onBack: pop,
          display: (v) => _labelFor(v, widget.collectionLabelsById),
          onSelected: (v) {
            _model.setFilters(_model.filters.copyWith(collection: v));
            pop();
          },
        );
        break;

      default:
        page = const SizedBox.shrink();
    }

    return _NoAnimRoute(
      settings: settings,
      page: _DrawerScope(model: _model, child: page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navKey,
      initialRoute: widget.initialRoute.name,
      onGenerateRoute: _routeFor,
    );
  }
}

/// --------------------
/// Header
/// - Root screens (Filters / Allergies): close only
/// - Sub pages (selectors): back + close
/// --------------------
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.title,
    required this.onClose,
    this.onBack,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final hasBack = onBack != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
      child: Row(
        children: [
          if (hasBack)
            IconButton(
              onPressed: onBack,
              icon: Icon(Icons.arrow_back, color: _FStyle.brand),
            )
          else
            const SizedBox(width: 8),
          Expanded(child: Text(title.toUpperCase(), style: _FStyle.sheetTitle)),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: _FStyle.brand),
          ),
        ],
      ),
    );
  }
}

/// --------------------
/// Filters (root) page
/// --------------------
class _FiltersPage extends StatelessWidget {
  const _FiltersPage({
    required this.courseOptions,
    required this.cuisineOptions,
    required this.suitableForOptions,
    required this.nutritionOptions,
    required this.collectionOptions,
    required this.lockCourse,
    required this.lockCuisine,
    required this.lockSuitableFor,
    required this.lockNutrition,
    required this.lockCollection,
    required this.onClose,
    required this.onGoSelect,
    required this.onApply,
    required this.courseLabelsById,
    required this.cuisineLabelsById,
    required this.ageLabelsById,
    required this.nutritionLabelsById,
    required this.collectionLabelsById,
  });

  final List<String> courseOptions;
  final List<String> cuisineOptions;
  final List<String> suitableForOptions;
  final List<String> nutritionOptions;
  final List<String> collectionOptions;

  final bool lockCourse;
  final bool lockCuisine;
  final bool lockSuitableFor;
  final bool lockNutrition;
  final bool lockCollection;

  final VoidCallback onClose;
  final void Function(_DrawerRoute route) onGoSelect;
  final VoidCallback onApply;

  final Map<String, String> courseLabelsById;
  final Map<String, String> cuisineLabelsById;
  final Map<String, String> ageLabelsById;
  final Map<String, String> nutritionLabelsById;
  final Map<String, String> collectionLabelsById;

  String _labelFor(String raw, Map<String, String> map) {
    if (raw == 'All') return 'Any';
    return map[raw] ?? raw;
  }

  @override
  Widget build(BuildContext context) {
    final model = _DrawerScope.modelOf(context);
    final f = model.filters;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DrawerHeader(title: 'Filters', onClose: onClose), // ✅ no back here
        Padding(
          padding: _FStyle.sheetPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('FILTERS', style: _FStyle.sectionLabel),
              const SizedBox(height: 10),

              if (!lockCourse)
                _SelectorRow(
                  title: 'Course',
                  value: _labelFor(f.course, courseLabelsById),
                  onTap: () => onGoSelect(_DrawerRoute.selectCourse),
                ),
              if (!lockCuisine) ...[
                const SizedBox(height: 10),
                _SelectorRow(
                  title: 'Cuisine',
                  value: _labelFor(f.cuisine, cuisineLabelsById),
                  onTap: () => onGoSelect(_DrawerRoute.selectCuisine),
                ),
              ],
              if (!lockSuitableFor) ...[
                const SizedBox(height: 10),
                _SelectorRow(
                  title: 'Age range',
                  value: _labelFor(f.suitableFor, ageLabelsById),
                  onTap: () => onGoSelect(_DrawerRoute.selectAge),
                ),
              ],
              if (!lockNutrition) ...[
                const SizedBox(height: 10),
                _SelectorRow(
                  title: 'Nutrition',
                  value: _labelFor(f.nutritionTag, nutritionLabelsById),
                  onTap: () => onGoSelect(_DrawerRoute.selectNutrition),
                ),
              ],
              if (!lockCollection) ...[
                const SizedBox(height: 10),
                _SelectorRow(
                  title: 'Collection',
                  value: _labelFor(f.collection, collectionLabelsById),
                  onTap: () => onGoSelect(_DrawerRoute.selectCollection),
                ),
              ],

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: _FStyle.ctaHeight,
                child: ElevatedButton(
                  style: _FStyle.ctaButtonStyle(),
                  onPressed: onApply,
                  child: Text('APPLY FILTERS', style: _FStyle.cta),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectorRow extends StatelessWidget {
  const _SelectorRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
            border: Border.all(color: _FStyle.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _FStyle.rowTitle),
                    const SizedBox(height: 6),
                    Text(value, style: _FStyle.rowValue, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _FStyle.brand.withOpacity(0.90)),
            ],
          ),
        ),
      ),
    );
  }
}

/// --------------------
/// Selector sub-page (inside same drawer)
/// --------------------
class _SelectorPage extends StatelessWidget {
  const _SelectorPage({
    required this.title,
    required this.options,
    required this.current,
    required this.onClose,
    required this.onBack,
    required this.onSelected,
    required this.display,
  });

  final String title;
  final List<String> options;
  final String current;
  final VoidCallback onClose;
  final VoidCallback onBack;
  final ValueChanged<String> onSelected;

  /// ✅ display mapper (id -> label)
  final String Function(String raw) display;

  @override
  Widget build(BuildContext context) {
    final safeOptions = options.isEmpty ? const ['All'] : options;
    final effectiveCurrent = safeOptions.contains(current) ? current : (safeOptions.contains('All') ? 'All' : safeOptions.first);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DrawerHeader(title: title, onClose: onClose, onBack: onBack),
        Padding(
          padding: _FStyle.sheetPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('SELECT', style: _FStyle.sectionLabel),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
                  border: Border.all(color: _FStyle.border),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: safeOptions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final v = safeOptions[i];
                    final selected = v == effectiveCurrent;
                    return ListTile(
                      dense: true,
                      title: Text(display(v), style: _FStyle.rowValue),
                      trailing: selected ? Icon(Icons.check, color: _FStyle.brand) : null,
                      onTap: () => onSelected(v),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text('Tip: choose "Any" to clear this filter.', style: _FStyle.helper),
            ],
          ),
        ),
      ],
    );
  }
}

/// --------------------
/// Allergies (root) page
/// --------------------
class _AllergiesPage extends StatefulWidget {
  const _AllergiesPage({
    required this.adults,
    required this.children,
    required this.householdLoading,
    required this.householdError,
    required this.onRetryHousehold,
    required this.onClose,
    required this.onApply,
  });

  final List<ProfilePerson> adults;
  final List<ProfilePerson> children;

  final bool householdLoading;
  final String? householdError;
  final VoidCallback? onRetryHousehold;

  final VoidCallback onClose;
  final VoidCallback onApply;

  @override
  State<_AllergiesPage> createState() => _AllergiesPageState();
}

class _AllergiesPageState extends State<_AllergiesPage> {
  List<ProfilePerson> get _allPeople => [...widget.adults, ...widget.children];

  void _setMode(_DrawerModel model, SuitabilityMode mode) {
    var next = model.allergies.copyWith(mode: mode);
    if (mode != SuitabilityMode.specificPeople) {
      next = next.copyWith(personIds: const {});
    }
    model.setAllergies(next);
  }

  void _togglePerson(_DrawerModel model, String id) {
    final current = Set<String>.from(model.allergies.personIds);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }

    if (current.isEmpty) {
      model.setAllergies(model.allergies.copyWith(mode: SuitabilityMode.wholeFamily, personIds: const {}));
    } else {
      model.setAllergies(model.allergies.copyWith(mode: SuitabilityMode.specificPeople, personIds: current));
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = _DrawerScope.modelOf(context);
    final a = model.allergies;
    final enabled = a.enabled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DrawerHeader(title: 'Allergies', onClose: widget.onClose),
        Padding(
          padding: _FStyle.sheetPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'FILTER BY ALLERGIES',
                      style: _FStyle.pillLabel.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        fontVariations: const [FontVariation('wght', 900)],
                      ),
                    ),
                  ),
                  Switch(
                    value: enabled,
                    activeColor: _FStyle.brand,
                    onChanged: (v) {
                      if (!v) {
                        model.setAllergies(
                          model.allergies.copyWith(
                            enabled: false,
                            mode: SuitabilityMode.wholeFamily,
                            personIds: const {},
                            includeSwaps: false,
                          ),
                        );
                      } else {
                        model.setAllergies(model.allergies.copyWith(enabled: true));
                      }
                    },
                  ),
                ],
              ),
              if (widget.householdLoading) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(height: 20),
              ] else if (widget.householdError != null) ...[
                const SizedBox(height: 10),
                Text(widget.householdError!, style: _FStyle.helper.copyWith(color: Colors.red)),
                TextButton(onPressed: widget.onRetryHousehold, child: const Text('Retry')),
              ] else if (enabled) ...[
                const SizedBox(height: 12),
                Text('SUITABLE FOR', style: _FStyle.sectionLabel),
                const SizedBox(height: 8),
                _PersonSelector(
                  label: 'Whole family',
                  isSelected: a.mode == SuitabilityMode.wholeFamily,
                  onTap: () => _setMode(model, SuitabilityMode.wholeFamily),
                ),
                const SizedBox(height: 8),
                _PersonSelector(
                  label: 'All children',
                  isSelected: a.mode == SuitabilityMode.allChildren,
                  onTap: () => _setMode(model, SuitabilityMode.allChildren),
                ),
                if (_allPeople.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('INDIVIDUALS', style: _FStyle.sectionLabel),
                  const SizedBox(height: 8),
                  ..._allPeople.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PersonSelector(
                        label: p.name,
                        isSelected: a.mode == SuitabilityMode.specificPeople && a.personIds.contains(p.id),
                        onTap: () => _togglePerson(model, p.id),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: _AllergySwapCopy()),
                    Switch(
                      value: a.includeSwaps,
                      activeColor: _FStyle.brand,
                      onChanged: (v) => model.setAllergies(model.allergies.copyWith(includeSwaps: v)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: _FStyle.ctaHeight,
                child: ElevatedButton(
                  style: _FStyle.ctaButtonStyle(),
                  onPressed: widget.onApply,
                  child: Text('APPLY ALLERGIES', style: _FStyle.cta),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonSelector extends StatelessWidget {
  const _PersonSelector({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? _FStyle.brand.withOpacity(0.08) : Colors.transparent;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
            border: Border.all(
              color: isSelected ? _FStyle.brand : Colors.black.withOpacity(0.1),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: _FStyle.personName.copyWith(
                    color: isSelected ? _FStyle.brand : Colors.black,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: _FStyle.brand, size: 20)
              else
                const Icon(Icons.circle_outlined, color: Colors.black26, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllergySwapCopy extends StatelessWidget {
  const _AllergySwapCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('INCLUDE RECIPES THAT NEED SWAPS', style: _FStyle.pillLabel.copyWith(fontSize: 13)),
        const SizedBox(height: 2),
        Text('Shows recipes with a safe ingredient replacement', style: _FStyle.helper),
      ],
    );
  }
}

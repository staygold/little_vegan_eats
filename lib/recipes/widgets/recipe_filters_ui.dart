// lib/recipes/widgets/recipe_filters_ui.dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum SuitabilityMode { wholeFamily, allChildren, singlePerson }
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
  final String? personId;
  final bool includeSwaps;

  const AllergiesSelection({
    this.enabled = true,
    this.mode = SuitabilityMode.wholeFamily,
    this.personId,
    this.includeSwaps = false,
  });

  /// Badge count reflects only what's applied:
  /// 0 if disabled
  /// 1 if enabled
  /// +1 if swaps enabled
  int get activeCount {
    if (!enabled) return 0;
    int n = 1;
    if (includeSwaps) n += 1;
    return n;
  }

  AllergiesSelection copyWith({
    bool? enabled,
    SuitabilityMode? mode,
    String? personId,
    bool? includeSwaps,
  }) {
    return AllergiesSelection(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      personId: personId ?? this.personId,
      includeSwaps: includeSwaps ?? this.includeSwaps,
    );
  }
}

///
/// ✅ Single place to customise Filters UI styling.
/// Edit these constants and your whole filters experience updates.
///
class _FStyle {
  static const String font = 'Montserrat';

  // Core colours (change these first)
  static const Color brand = AppColors.brandDark; // main accent
  static const Color sheetBg = Colors.white;
  static const Color pillBg = Colors.white;
  static const Color border = Color(0x14000000); // subtle border
  static const Color muted = Color(0x8C000000); // 55% black-ish
  static const Color chipBg = AppColors.brandDark;
  static const Color chipText = Colors.white;

  // Radii
  static const double pillRadius = 14;
  static const double chipRadius = 999;
  static const double sheetRadius = 20;
  static const double fieldRadius = 14;
  static const double ctaRadius = 14;

  // Sizes
  static const double pillHeight = 44;
  static const double chipHeight = 34;
  static const double ctaHeight = 48;

  // Spacing
  static const EdgeInsets pillPadding = EdgeInsets.symmetric(horizontal: 14);
  static const EdgeInsets sheetPadding = EdgeInsets.fromLTRB(16, 0, 16, 16);
  static const EdgeInsets fieldPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 4);
  static const EdgeInsets chipPadding = EdgeInsets.symmetric(horizontal: 12);

  // Typography
  static const TextStyle pillLabel = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    height: 1.0,
    color: AppColors.brandDark,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: font,
    fontSize: 12,
    fontWeight: FontWeight.w900,
    fontVariations: [FontVariation('wght', 900)],
    height: 1.0,
    color: Colors.white,
  );

  static const TextStyle chip = TextStyle(
    fontFamily: font,
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    height: 1.0,
    color: chipText,
  );

  static const TextStyle sheetTitle = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w900,
    fontVariations: [FontVariation('wght', 900)],
    letterSpacing: 0.6,
    height: 1.0,
    color: AppColors.brandDark,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontFamily: font,
    fontSize: 12,
    fontWeight: FontWeight.w900,
    fontVariations: [FontVariation('wght', 900)],
    letterSpacing: 0.4,
    height: 1.0,
    color: AppColors.brandDark,
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

  static const TextStyle emptyState = TextStyle(
    fontFamily: font,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.2,
    color: muted,
  );

  static const TextStyle personName = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    color: Colors.black,
  );

  // Reusable decorations
  static BoxDecoration pillDecoration() => BoxDecoration(
    borderRadius: BorderRadius.circular(pillRadius),
    border: Border.all(color: border),
    color: pillBg,
  );

  static BoxDecoration chipDecoration() => BoxDecoration(
    color: chipBg,
    borderRadius: BorderRadius.circular(chipRadius),
  );

  static BoxDecoration fieldDecoration() => BoxDecoration(
    borderRadius: BorderRadius.circular(fieldRadius),
    border: Border.all(color: Colors.black.withOpacity(0.10)),
    color: Colors.transparent,
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

  List<ProfilePerson> get _allPeople => [...adults, ...children];

  String _allergiesChipLabel(AllergiesSelection a) {
    if (!a.enabled) return 'Allergies off';
    if (a.mode == SuitabilityMode.wholeFamily) return 'Whole family';
    if (a.mode == SuitabilityMode.allChildren) return 'All children';

    final p = _allPeople.where((x) => x.id == a.personId).toList();
    if (p.isNotEmpty) return p.first.name;
    return 'Whole family';
  }

  @override
  Widget build(BuildContext context) {
    final filterCount = filters.activeCount;
    final allergyCount = allergies.activeCount;

    final chips = <_ChipSpec>[];

    if (filters.course != 'All') {
      chips.add(_ChipSpec(
        label: filters.course,
        onClear: () => onFiltersApplied(filters.copyWith(course: 'All')),
      ));
    }
    if (filters.cuisine != 'All') {
      chips.add(_ChipSpec(
        label: filters.cuisine,
        onClear: () => onFiltersApplied(filters.copyWith(cuisine: 'All')),
      ));
    }
    if (filters.suitableFor != 'All') {
      chips.add(_ChipSpec(
        label: filters.suitableFor,
        onClear: () => onFiltersApplied(filters.copyWith(suitableFor: 'All')),
      ));
    }
    if (filters.nutritionTag != 'All') {
      chips.add(_ChipSpec(
        label: filters.nutritionTag,
        onClear: () => onFiltersApplied(filters.copyWith(nutritionTag: 'All')),
      ));
    }
    if (filters.collection != 'All') {
      chips.add(_ChipSpec(
        label: filters.collection,
        onClear: () => onFiltersApplied(filters.copyWith(collection: 'All')),
      ));
    }

    // Allergies chips (only when enabled)
    if (allergies.enabled) {
      chips.add(_ChipSpec(
        label: _allergiesChipLabel(allergies),
        onClear: () => onAllergiesApplied(
          allergies.copyWith(
            enabled: false,
            mode: SuitabilityMode.wholeFamily,
            personId: null,
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
                onTap: () async {
                  final next = await showModalBottomSheet<RecipeFilterSelection>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: _FStyle.sheetBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(_FStyle.sheetRadius),
                      ),
                    ),
                    builder: (_) => _SheetScrollShell(
                      child: _FiltersSheet(
                        initial: filters,
                        courseOptions: courseOptions,
                        cuisineOptions: cuisineOptions,
                        suitableForOptions: suitableForOptions,
                        nutritionOptions: nutritionOptions,
                        collectionOptions: collectionOptions,
                        lockCourse: lockCourse,
                        lockCollection: lockCollection,
                        lockCuisine: lockCuisine,
                        lockSuitableFor: lockSuitableFor,
                        lockNutrition: lockNutrition,
                      ),
                    ),
                  );
                  if (next != null) onFiltersApplied(next);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PillButton(
                label: 'Allergies',
                count: allergyCount,
                onTap: () async {
                  final next = await showModalBottomSheet<AllergiesSelection>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: _FStyle.sheetBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(_FStyle.sheetRadius),
                      ),
                    ),
                    builder: (_) => _SheetScrollShell(
                      child: _AllergiesSheet(
                        initial: allergies,
                        adults: adults,
                        children: children,
                        householdLoading: householdLoading,
                        householdError: householdError,
                        onRetryHousehold: onRetryHousehold,
                      ),
                    ),
                  );
                  if (next != null) onAllergiesApplied(next);
                },
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
         ] else ...[
          // ✅ nothing when no chips
          const SizedBox(height: 0),
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
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(_FStyle.pillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_FStyle.pillRadius),
        onTap: onTap,
        child: Container(
          height: _FStyle.pillHeight,
          padding: _FStyle.pillPadding,
          decoration: _FStyle.pillDecoration(),
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
      decoration: _FStyle.chipDecoration(),
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

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
      child: Row(
        children: [
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

class _SheetScrollShell extends StatelessWidget {
  const _SheetScrollShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottom),
        child: child,
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({
    required this.initial,
    required this.courseOptions,
    required this.cuisineOptions,
    required this.suitableForOptions,
    required this.nutritionOptions,
    required this.collectionOptions,
    required this.lockCourse,
    required this.lockCollection,
    required this.lockCuisine,
    required this.lockSuitableFor,
    required this.lockNutrition,
  });

  final RecipeFilterSelection initial;
  final List<String> courseOptions;
  final List<String> cuisineOptions;
  final List<String> suitableForOptions;
  final List<String> nutritionOptions;
  final List<String> collectionOptions;

  final bool lockCourse;
  final bool lockCollection;
  final bool lockCuisine;
  final bool lockSuitableFor;
  final bool lockNutrition;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late RecipeFilterSelection _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  String _safeValue(String current, List<String> options) {
    if (options.isEmpty) return 'All';
    if (options.contains(current)) return current;
    return options.contains('All') ? 'All' : options.first;
  }

  @override
  Widget build(BuildContext context) {
    final course = _safeValue(_draft.course, widget.courseOptions);
    final cuisine = _safeValue(_draft.cuisine, widget.cuisineOptions);
    final suitableFor = _safeValue(_draft.suitableFor, widget.suitableForOptions);
    final nutrition = _safeValue(_draft.nutritionTag, widget.nutritionOptions);
    final collection = _safeValue(_draft.collection, widget.collectionOptions);

    if (course != _draft.course ||
        cuisine != _draft.cuisine ||
        suitableFor != _draft.suitableFor ||
        nutrition != _draft.nutritionTag ||
        collection != _draft.collection) {
      _draft = _draft.copyWith(
        course: course,
        cuisine: cuisine,
        suitableFor: suitableFor,
        nutritionTag: nutrition,
        collection: collection,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeader(
          title: 'Filters',
          onClose: () => Navigator.of(context).pop(),
        ),
        Padding(
          padding: _FStyle.sheetPadding,
          child: Column(
            children: [
              if (!widget.lockCourse)
                _SelectField(
                  label: 'Course',
                  value: _draft.course,
                  options: widget.courseOptions,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(course: v)),
                ),
              if (!widget.lockCuisine) ...[
                const SizedBox(height: 10),
                _SelectField(
                  label: 'Cuisine',
                  value: _draft.cuisine,
                  options: widget.cuisineOptions,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(cuisine: v)),
                ),
              ],
              if (!widget.lockSuitableFor) ...[
                const SizedBox(height: 10),
                _SelectField(
                  label: 'Age range',
                  value: _draft.suitableFor,
                  options: widget.suitableForOptions,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(suitableFor: v)),
                ),
              ],
              if (!widget.lockNutrition) ...[
                const SizedBox(height: 10),
                _SelectField(
                  label: 'Nutrition',
                  value: _draft.nutritionTag,
                  options: widget.nutritionOptions,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(nutritionTag: v)),
                ),
              ],
              if (!widget.lockCollection) ...[
                const SizedBox(height: 10),
                _SelectField(
                  label: 'Collection',
                  value: _draft.collection,
                  options: widget.collectionOptions,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(collection: v)),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: _FStyle.ctaHeight,
                child: ElevatedButton(
                  style: _FStyle.ctaButtonStyle(),
                  onPressed: () => Navigator.of(context).pop(_draft),
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

class _AllergiesSheet extends StatefulWidget {
  const _AllergiesSheet({
    required this.initial,
    required this.adults,
    required this.children,
    required this.householdLoading,
    required this.householdError,
    required this.onRetryHousehold,
  });

  final AllergiesSelection initial;
  final List<ProfilePerson> adults;
  final List<ProfilePerson> children;

  final bool householdLoading;
  final String? householdError;
  final VoidCallback? onRetryHousehold;

  @override
  State<_AllergiesSheet> createState() => _AllergiesSheetState();
}

class _AllergiesSheetState extends State<_AllergiesSheet> {
  late AllergiesSelection _draft;

  List<ProfilePerson> get _allPeople => [...widget.adults, ...widget.children];

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;

    if (_draft.mode == SuitabilityMode.singlePerson) {
      final exists = _allPeople.any((p) => p.id == _draft.personId);
      if (!exists) {
        _draft = _draft.copyWith(
          mode: SuitabilityMode.wholeFamily,
          personId: null,
          includeSwaps: false,
        );
      }
    }
  }

  // Helper to set new mode
  void _setMode(SuitabilityMode mode, [String? personId]) {
    setState(() {
      _draft = _draft.copyWith(mode: mode, personId: personId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _draft.enabled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader(
          title: 'Allergies',
          onClose: () => Navigator.of(context).pop(),
        ),
        Padding(
          padding: _FStyle.sheetPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main Toggle
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
                      setState(() {
                        _draft = _draft.copyWith(enabled: v);
                        // Reset selection when disabled
                        if (!v) {
                          _draft = _draft.copyWith(
                            mode: SuitabilityMode.wholeFamily,
                            personId: null,
                            includeSwaps: false,
                          );
                        }
                      });
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
                // THE SELECTOR LIST
                const SizedBox(height: 12),
                Text(
                  'SUITABLE FOR',
                  style: _FStyle.sectionLabel.copyWith(color: _FStyle.muted, fontSize: 11),
                ),
                const SizedBox(height: 8),

                _PersonSelector(
                  label: 'Whole family',
                  isSelected: _draft.mode == SuitabilityMode.wholeFamily,
                  onTap: () => _setMode(SuitabilityMode.wholeFamily),
                ),
                const SizedBox(height: 8),
                _PersonSelector(
                  label: 'All children',
                  isSelected: _draft.mode == SuitabilityMode.allChildren,
                  onTap: () => _setMode(SuitabilityMode.allChildren),
                ),
                if (_allPeople.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'INDIVIDUALS',
                    style: _FStyle.sectionLabel.copyWith(color: _FStyle.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  ..._allPeople.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PersonSelector(
                      label: p.name,
                      isSelected: _draft.mode == SuitabilityMode.singlePerson && _draft.personId == p.id,
                      onTap: () => _setMode(SuitabilityMode.singlePerson, p.id),
                    ),
                  )),
                ],

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Swaps Toggle
                Row(
                  children: [
                    const Expanded(child: _AllergySwapCopy()),
                    Switch(
                      value: _draft.includeSwaps,
                      activeColor: _FStyle.brand,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(includeSwaps: v)),
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
                  onPressed: () => Navigator.of(context).pop(_draft),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? _FStyle.brand.withOpacity(0.08) : Colors.transparent,
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

class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.dropdownItemsOverride,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  final List<DropdownMenuItem<String>>? dropdownItemsOverride;

  @override
  Widget build(BuildContext context) {
    final items = dropdownItemsOverride ??
        options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList();

    final matches = items.where((i) => i.value == value).length;
    final safeValue = (matches == 1) ? value : null;

    return Container(
      padding: _FStyle.fieldPadding,
      decoration: _FStyle.fieldDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(), style: _FStyle.sectionLabel),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: safeValue,
                items: items,
                onChanged: (v) {
                  if (v == null) return;
                  onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
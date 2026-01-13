// lib/recipes/widgets/recipe_filters_ui.dart
import 'dart:ui';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// ✅ Ensure these imports point to your actual file locations
import '../allergy_engine.dart'; 
import '../profile_person.dart'; 

// -----------------------------------------------------------------------------
// MODELS
// -----------------------------------------------------------------------------

class RecipeFilterSelection {
  final String course;
  final String cuisine;
  final String suitableFor;
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

// -----------------------------------------------------------------------------
// STYLING
// -----------------------------------------------------------------------------

class _FStyle {
  static const String font = 'Montserrat';
  static const Color brand = AppColors.brandDark;
  static const double fieldRadius = 14;
}

// -----------------------------------------------------------------------------
// MAIN BAR WIDGET
// -----------------------------------------------------------------------------

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

  final Map<String, String> courseLabelsById;
  final Map<String, String> cuisineLabelsById;
  final Map<String, String> ageLabelsById;
  final Map<String, String> nutritionLabelsById;
  final Map<String, String> collectionLabelsById;

  List<ProfilePerson> get _allPeople => [...adults, ...children];

  void _openSheet(BuildContext context, bool startOnAllergies) {
    RecipeFiltersSheet.show(
      context,
      startOnAllergies: startOnAllergies,
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
      courseLabelsById: courseLabelsById,
      cuisineLabelsById: cuisineLabelsById,
      ageLabelsById: ageLabelsById,
      nutritionLabelsById: nutritionLabelsById,
      collectionLabelsById: collectionLabelsById,
      onApplyFilters: onFiltersApplied,
      onApplyAllergies: onAllergiesApplied,
    );
  }

  String _labelFor(String raw, Map<String, String> map) {
    if (raw == 'All') return 'Any';
    return map[raw] ?? raw;
  }

  String _allergiesChipLabel(AllergiesSelection a) {
    if (!a.enabled) return 'Suitability off';
    if (a.mode == SuitabilityMode.wholeFamily) return 'Suitable for whole family';
    if (a.mode == SuitabilityMode.allChildren) return 'Suitable for all children';
    
    if (a.personIds.isNotEmpty) {
      final names = _allPeople
          .where((p) => a.personIds.contains(p.id))
          .map((p) => p.name)
          .toList();
      if (names.isNotEmpty) {
        if (names.length == 1) return 'Suitable for ${names.first}';
        if (names.length == 2) return 'Suitable for ${names[0]} & ${names[1]}';
        return 'Suitable for ${names.length} people';
      }
    }
    return 'Suitable for whole family';
  }

  @override
  Widget build(BuildContext context) {
    int activeCount = 0;
    if (!lockCourse && filters.course != 'All') activeCount++;
    if (!lockCuisine && filters.cuisine != 'All') activeCount++;
    if (!lockSuitableFor && filters.suitableFor != 'All') activeCount++;
    if (!lockNutrition && filters.nutritionTag != 'All') activeCount++;
    if (!lockCollection && filters.collection != 'All') activeCount++;

    final allergyCount = allergies.activeCount;

    final chips = <Widget>[];

    void addChip(String label, VoidCallback onClear) {
      chips.add(_FilterChip(label: label, onClear: onClear));
      chips.add(const SizedBox(width: 8));
    }

    if (!lockCourse && filters.course != 'All') {
      addChip(
        _labelFor(filters.course, courseLabelsById),
        () => onFiltersApplied(filters.copyWith(course: 'All')),
      );
    }
    if (!lockCuisine && filters.cuisine != 'All') {
      addChip(
        _labelFor(filters.cuisine, cuisineLabelsById),
        () => onFiltersApplied(filters.copyWith(cuisine: 'All')),
      );
    }
    if (!lockSuitableFor && filters.suitableFor != 'All') {
      addChip(
        _labelFor(filters.suitableFor, ageLabelsById),
        () => onFiltersApplied(filters.copyWith(suitableFor: 'All')),
      );
    }
    if (!lockNutrition && filters.nutritionTag != 'All') {
      addChip(
        _labelFor(filters.nutritionTag, nutritionLabelsById),
        () => onFiltersApplied(filters.copyWith(nutritionTag: 'All')),
      );
    }
    if (!lockCollection && filters.collection != 'All') {
      addChip(
        _labelFor(filters.collection, collectionLabelsById),
        () => onFiltersApplied(filters.copyWith(collection: 'All')),
      );
    }

    if (allergies.enabled) {
      addChip(
        _allergiesChipLabel(allergies),
        () => onAllergiesApplied(
          allergies.copyWith(
            enabled: false,
            mode: SuitabilityMode.wholeFamily,
            personIds: const <String>{},
            includeSwaps: false,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _PillButton(
                label: 'Filters',
                count: activeCount,
                onTap: () => _openSheet(context, false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PillButton(
                label: 'Suitability',
                count: allergyCount,
                onTap: () => _openSheet(context, true),
              ),
            ),
          ],
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: chips),
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// FILTER SHEET
// -----------------------------------------------------------------------------

class RecipeFiltersSheet extends StatefulWidget {
  final bool startOnAllergies;
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

  final Map<String, String> courseLabelsById;
  final Map<String, String> cuisineLabelsById;
  final Map<String, String> ageLabelsById;
  final Map<String, String> nutritionLabelsById;
  final Map<String, String> collectionLabelsById;

  final ValueChanged<RecipeFilterSelection> onApplyFilters;
  final ValueChanged<AllergiesSelection> onApplyAllergies;

  const RecipeFiltersSheet({
    super.key,
    required this.startOnAllergies,
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
    required this.courseLabelsById,
    required this.cuisineLabelsById,
    required this.ageLabelsById,
    required this.nutritionLabelsById,
    required this.collectionLabelsById,
    required this.onApplyFilters,
    required this.onApplyAllergies,
  });

  static Future<void> show(
    BuildContext context, {
    required bool startOnAllergies,
    required RecipeFilterSelection initialFilters,
    required AllergiesSelection initialAllergies,
    required List<String> courseOptions,
    required List<String> cuisineOptions,
    required List<String> suitableForOptions,
    required List<String> nutritionOptions,
    required List<String> collectionOptions,
    required bool lockCourse,
    required bool lockCuisine,
    required bool lockSuitableFor,
    required bool lockNutrition,
    required bool lockCollection,
    required List<ProfilePerson> adults,
    required List<ProfilePerson> children,
    required Map<String, String> courseLabelsById,
    required Map<String, String> cuisineLabelsById,
    required Map<String, String> ageLabelsById,
    required Map<String, String> nutritionLabelsById,
    required Map<String, String> collectionLabelsById,
    required ValueChanged<RecipeFilterSelection> onApplyFilters,
    required ValueChanged<AllergiesSelection> onApplyAllergies,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => RecipeFiltersSheet(
        startOnAllergies: startOnAllergies,
        initialFilters: initialFilters,
        initialAllergies: initialAllergies,
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
        courseLabelsById: courseLabelsById,
        cuisineLabelsById: cuisineLabelsById,
        ageLabelsById: ageLabelsById,
        nutritionLabelsById: nutritionLabelsById,
        collectionLabelsById: collectionLabelsById,
        onApplyFilters: onApplyFilters,
        onApplyAllergies: onApplyAllergies,
      ),
    );
  }

  @override
  State<RecipeFiltersSheet> createState() => _RecipeFiltersSheetState();
}

enum _SubPageType { none, course, cuisine, age, nutrition, collection }

class _RecipeFiltersSheetState extends State<RecipeFiltersSheet> {
  late RecipeFilterSelection _tempFilters;
  late AllergiesSelection _tempAllergies;

  final PageController _pageCtrl = PageController();

  int _pageIndex = 0;
  _SubPageType _activeSubPage = _SubPageType.none;

  @override
  void initState() {
    super.initState();
    _tempFilters = widget.initialFilters;
    _tempAllergies = widget.initialAllergies;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goToSubPage(_SubPageType type) {
    setState(() {
      _activeSubPage = type;
      _pageIndex = 1;
    });
    _pageCtrl.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goBack() {
    setState(() => _pageIndex = 0);
    _pageCtrl.animateToPage(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _applyAndClose() {
    widget.onApplyFilters(_tempFilters);
    widget.onApplyAllergies(_tempAllergies);
    Navigator.pop(context);
  }

  String _labelFor(String raw, Map<String, String> map) {
    if (raw == 'All') return 'Any';
    return map[raw] ?? raw;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final isAllergiesMode = widget.startOnAllergies;
    final title = _pageIndex == 1
        ? _subPageTitle(_activeSubPage)
        : (isAllergiesMode ? 'Suitability' : 'Filters');

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (_pageIndex == 1)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _goBack,
                  )
                else
                  const SizedBox(width: 0),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Colors.black.withOpacity(0.85),
                    ),
                  ),
                ),

                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.black.withOpacity(0.65),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                isAllergiesMode
                    ? _buildAllergiesRoot(bottomPad)
                    : _buildFiltersRoot(bottomPad),
                _buildSubPage(bottomPad),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PAGE 0: FILTERS ROOT
  // ---------------------------------------------------------------------------
  Widget _buildFiltersRoot(double bottomPad) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'REFINE RESULTS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Colors.black.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 12),

              if (!widget.lockCourse) ...[
                _MenuButton(
                  label: 'Course',
                  value: _labelFor(_tempFilters.course, widget.courseLabelsById),
                  onTap: () => _goToSubPage(_SubPageType.course),
                ),
                const SizedBox(height: 10),
              ],

              if (!widget.lockCuisine) ...[
                _MenuButton(
                  label: 'Cuisine',
                  value: _labelFor(_tempFilters.cuisine, widget.cuisineLabelsById),
                  onTap: () => _goToSubPage(_SubPageType.cuisine),
                ),
                const SizedBox(height: 10),
              ],

              if (!widget.lockSuitableFor) ...[
                _MenuButton(
                  label: 'Age Range',
                  value: _labelFor(_tempFilters.suitableFor, widget.ageLabelsById),
                  onTap: () => _goToSubPage(_SubPageType.age),
                ),
                const SizedBox(height: 10),
              ],

              if (!widget.lockNutrition) ...[
                _MenuButton(
                  label: 'Nutrition',
                  value:
                      _labelFor(_tempFilters.nutritionTag, widget.nutritionLabelsById),
                  onTap: () => _goToSubPage(_SubPageType.nutrition),
                ),
                const SizedBox(height: 10),
              ],

              if (!widget.lockCollection) ...[
                _MenuButton(
                  label: 'Collection',
                  value:
                      _labelFor(_tempFilters.collection, widget.collectionLabelsById),
                  onTap: () => _goToSubPage(_SubPageType.collection),
                ),
              ],
            ],
          ),
        ),
        _buildFooterButton(bottomPad, 'APPLY FILTERS'),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PAGE 0: ALLERGIES ROOT
  // ---------------------------------------------------------------------------
  Widget _buildAllergiesRoot(double bottomPad) {
    final a = _tempAllergies;
    
    // Logic helpers
    final children = widget.children;
    final adults = widget.adults;
    final singleChild = children.length == 1 ? children.first : null;
    final hasMultipleChildren = children.length > 1;

    // Safety Scale Logic helpers for the Radio Buttons
    // 1. Strict: Hide Unsafe AND Hide Swaps
    final isStrictSafety = a.hideUnsafe && !a.includeSwaps;
    
    // 2. Swap Friendly: Hide Unsafe BUT Show Swaps
    final isSwapSafety = a.hideUnsafe && a.includeSwaps;
    
    // 3. Show All: Hide Unsafe is FALSE
    final isShowAllSafety = !a.hideUnsafe;

    void togglePerson(String id) {
      final current = Set<String>.from(a.personIds);
      if (current.contains(id)) {
        current.remove(id);
      } else {
        current.add(id);
      }
      setState(() {
        _tempAllergies = a.copyWith(personIds: current);
      });
    }

    String getNamesList(List<ProfilePerson> people) {
      if (people.isEmpty) return "";
      final names = people.map((e) => e.name).join(", ");
      return "Includes $names";
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // -------------------------------------------------------
              // MASTER TOGGLE
              // -------------------------------------------------------
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'FILTER BY SUITABILITY',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: AppColors.brandDark,
                        ),
                      ),
                    ),
                    Switch(
                      value: a.enabled,
                      activeColor: AppColors.brandDark,
                      onChanged: (v) {
                        setState(() {
                          if (!v) {
                            // Turn Off
                            _tempAllergies = a.copyWith(
                              enabled: false,
                              mode: SuitabilityMode.wholeFamily,
                              personIds: const <String>{},
                            );
                          } else {
                            // Turn On -> Default to Strict Safety
                            _tempAllergies = a.copyWith(
                              enabled: true,
                              hideUnsafe: true,     
                              includeSwaps: false,  
                              strictAge: false,     
                            );
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),

              if (a.enabled) ...[
                const SizedBox(height: 24),
                
                // ---------------------------------------------------------
                // 1. WHO ARE YOU FEEDING?
                // ---------------------------------------------------------
                Text(
                  'WHO ARE YOU FEEDING?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.black.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 12),

                // OPTION 1: WHOLE FAMILY
                _RadioTile(
                  label: 'Whole family',
                  subtitle: a.mode == SuitabilityMode.wholeFamily 
                    ? getNamesList([...children, ...adults]) 
                    : null,
                  selected: a.mode == SuitabilityMode.wholeFamily,
                  onTap: () => setState(() => _tempAllergies = a.copyWith(
                    mode: SuitabilityMode.wholeFamily,
                    personIds: const <String>{}, 
                  )),
                ),
                const SizedBox(height: 8),

                // --- SCENARIO A: SINGLE CHILD ---
                if (singleChild != null) ...[
                  _RadioTile(
                    label: singleChild.name,
                    selected: a.mode == SuitabilityMode.specificPeople && 
                              a.personIds.contains(singleChild.id),
                    onTap: () => setState(() => _tempAllergies = a.copyWith(
                      mode: SuitabilityMode.specificPeople,
                      personIds: {singleChild.id},
                    )),
                  ),
                ]

                // --- SCENARIO B: MULTIPLE CHILDREN ---
                else if (hasMultipleChildren) ...[
                  _RadioTile(
                    label: 'All children',
                    subtitle: a.mode == SuitabilityMode.allChildren 
                      ? getNamesList(children) 
                      : null,
                    selected: a.mode == SuitabilityMode.allChildren,
                    onTap: () => setState(() => _tempAllergies = a.copyWith(
                      mode: SuitabilityMode.allChildren,
                      // Forces all IDs to be sent to engine
                      personIds: children.map((c) => c.id).toSet(),
                    )),
                  ),
                  const SizedBox(height: 8),

                  _RadioTile(
                    label: 'Select individuals',
                    selected: a.mode == SuitabilityMode.specificPeople,
                    onTap: () => setState(() => _tempAllergies = a.copyWith(
                      mode: SuitabilityMode.specificPeople,
                      // Keep existing IDs
                    )),
                  ),

                  if (a.mode == SuitabilityMode.specificPeople) ...[
                    const SizedBox(height: 12),
                    Container(
                      margin: const EdgeInsets.only(left: 12),
                      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: Colors.black.withOpacity(0.1),
                            width: 2,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           ...children.map((p) => _CheckboxRow(
                             label: p.name,
                             checked: a.personIds.contains(p.id),
                             onTap: () => togglePerson(p.id),
                           )),
                           
                           if (adults.isNotEmpty) ...[
                             const SizedBox(height: 8),
                             Padding(
                               padding: const EdgeInsets.only(left: 4, bottom: 4),
                               child: Text(
                                 "Adults", 
                                 style: TextStyle(
                                   fontSize: 11, 
                                   fontWeight: FontWeight.bold,
                                   color: Colors.grey[500]
                                 )
                               ),
                             ),
                             ...adults.map((p) => _CheckboxRow(
                               label: p.name,
                               checked: a.personIds.contains(p.id),
                               onTap: () => togglePerson(p.id),
                             )),
                           ]
                        ],
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 12),
                Divider(height: 1, color: Colors.black.withOpacity(0.1)),
                const SizedBox(height: 24),

                // ---------------------------------------------------------
                // 2. ALLERGY SAFETY
                // ---------------------------------------------------------
                Text(
                  'ALLERGY SAFETY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.black.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 12),

                // Option 1: STRICT
                _RadioTile(
                  label: 'Block all unsafe recipes',
                  subtitle: 'Hide anything that matches an allergen.',
                  selected: isStrictSafety,
                  onTap: () => setState(() {
                    _tempAllergies = a.copyWith(
                      hideUnsafe: true,
                      includeSwaps: false,
                      strictAge: false, 
                    );
                  }),
                ),
                const SizedBox(height: 8),

                // Option 2: ALLOW SWAPS (Logic Fix Target)
                _RadioTile(
                  label: 'Allow recipes that require swaps',
                  subtitle: 'Shows recipes with a swap available (Amber).',
                  selected: isSwapSafety,
                  onTap: () => setState(() {
                    _tempAllergies = a.copyWith(
                      hideUnsafe: true, // Keep UNSAFE hidden...
                      includeSwaps: true, // ...Unless it has a SWAP
                      strictAge: false, 
                    );
                  }),
                ),
                const SizedBox(height: 8),

                // Option 3: SHOW ALL
                _RadioTile(
                  label: 'Show all recipes even if not suitable',
                  selected: isShowAllSafety,
                  onTap: () => setState(() {
                    _tempAllergies = a.copyWith(
                      hideUnsafe: false,
                      strictAge: false, 
                    );
                  }),
                ),
              ],
            ],
          ),
        ),
        _buildFooterButton(bottomPad, 'APPLY SETTINGS'),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PAGE 1: SELECTOR SUB PAGE
  // ---------------------------------------------------------------------------
  Widget _buildSubPage(double bottomPad) {
    final options = _getOptions(_activeSubPage);
    final current = _getValue(_activeSubPage);

    final safeOptions = options.isEmpty ? const <String>['All'] : options;
    final effectiveCurrent = safeOptions.contains(current)
        ? current
        : (safeOptions.contains('All') ? 'All' : safeOptions.first);

    return Column(
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'SELECT OPTION',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: Colors.black.withOpacity(0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.only(bottom: 20 + bottomPad),
            itemCount: safeOptions.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.black.withOpacity(0.06)),
            itemBuilder: (ctx, i) {
              final val = safeOptions[i];
              final label = _getLabelFor(val, _activeSubPage);
              final isSelected = val == effectiveCurrent;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: AppColors.brandDark)
                    : null,
                onTap: () {
                  _setValue(_activeSubPage, val);
                  _goBack();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  Widget _buildFooterButton(double bottomPad, String label) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _applyAndClose,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ),
      ),
    );
  }

  String _subPageTitle(_SubPageType type) {
    switch (type) {
      case _SubPageType.course:
        return 'Course';
      case _SubPageType.cuisine:
        return 'Cuisine';
      case _SubPageType.age:
        return 'Age Range';
      case _SubPageType.nutrition:
        return 'Nutrition';
      case _SubPageType.collection:
        return 'Collection';
      default:
        return '';
    }
  }

  List<String> _getOptions(_SubPageType type) {
    switch (type) {
      case _SubPageType.course:
        return widget.courseOptions;
      case _SubPageType.cuisine:
        return widget.cuisineOptions;
      case _SubPageType.age:
        return widget.suitableForOptions;
      case _SubPageType.nutrition:
        return widget.nutritionOptions;
      case _SubPageType.collection:
        return widget.collectionOptions;
      default:
        return const <String>[];
    }
  }

  String _getValue(_SubPageType type) {
    switch (type) {
      case _SubPageType.course:
        return _tempFilters.course;
      case _SubPageType.cuisine:
        return _tempFilters.cuisine;
      case _SubPageType.age:
        return _tempFilters.suitableFor;
      case _SubPageType.nutrition:
        return _tempFilters.nutritionTag;
      case _SubPageType.collection:
        return _tempFilters.collection;
      default:
        return 'All';
    }
  }

  void _setValue(_SubPageType type, String val) {
    setState(() {
      switch (type) {
        case _SubPageType.course:
          _tempFilters = _tempFilters.copyWith(course: val);
          break;
        case _SubPageType.cuisine:
          _tempFilters = _tempFilters.copyWith(cuisine: val);
          break;
        case _SubPageType.age:
          _tempFilters = _tempFilters.copyWith(suitableFor: val);
          break;
        case _SubPageType.nutrition:
          _tempFilters = _tempFilters.copyWith(nutritionTag: val);
          break;
        case _SubPageType.collection:
          _tempFilters = _tempFilters.copyWith(collection: val);
          break;
        default:
          break;
      }
    });
  }

  String _getLabelFor(String val, _SubPageType type) {
    if (val == 'All') return 'Any';
    switch (type) {
      case _SubPageType.course:
        return widget.courseLabelsById[val] ?? val;
      case _SubPageType.cuisine:
        return widget.cuisineLabelsById[val] ?? val;
      case _SubPageType.age:
        return widget.ageLabelsById[val] ?? val;
      case _SubPageType.nutrition:
        return widget.nutritionLabelsById[val] ?? val;
      case _SubPageType.collection:
        return widget.collectionLabelsById[val] ?? val;
      default:
        return val;
    }
  }
}

// -----------------------------------------------------------------------------
// SMALLER WIDGETS
// -----------------------------------------------------------------------------

class _MenuButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _MenuButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.brandDark.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RadioTile({
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandDark.withOpacity(0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_FStyle.fieldRadius),
            border: Border.all(
              color: selected ? AppColors.brandDark : Colors.black.withOpacity(0.1),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.brandDark : Colors.black26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? AppColors.brandDark : Colors.black,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: selected ? AppColors.brandDark.withOpacity(0.8) : Colors.black54,
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;

  const _CheckboxRow({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Row(
          children: [
            Icon(
              checked
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: checked
                  ? AppColors.brandDark
                  : Colors.black38,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontWeight: checked
                    ? FontWeight.w700
                    : FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandDark,
                  ),
                ),
              ),
              if (count > 0) ...[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.brandDark,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onClear;

  const _FilterChip({
    required this.label,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.brandDark,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, color: Colors.white, size: 16),
          ),
        ],
      ),
    );
  }
}
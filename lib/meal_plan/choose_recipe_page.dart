// lib/meal_plan/choose_recipe_page.dart
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';


// ✅ Reuse shared UI (same as CoursePage)
import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';
import '../theme/app_theme.dart';


// ✅ Reuse RecipeCard (same as CoursePage)
import '../recipes/widgets/recipe_card.dart';

class _MPChooseStyle {
  static const Color bg = Color(0xFFECF3F4);
static const Color brandDark = AppColors.brandDark;

  static const EdgeInsets sectionPad = EdgeInsets.fromLTRB(16, 0, 16, 16);
  static const EdgeInsets metaPad = EdgeInsets.fromLTRB(16, 0, 16, 10);

  static TextStyle meta(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
        height: 1.2,
        fontSize: 14,
        fontVariations: const [FontVariation('wght', 600)],
      );

  static TextStyle h2(BuildContext context) =>
      (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
        fontVariations: const [FontVariation('wght', 800)],
      );

  static TextStyle recTitle(BuildContext context) =>
      (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
        color: Colors.white,
        fontVariations: const [FontVariation('wght', 800)],
      );

  static TextStyle recMeta(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
        color: Colors.white,
        height: 1.2,
        fontSize: 14,
        fontVariations: const [FontVariation('wght', 600)],
      );
}

class ChooseRecipePage extends StatefulWidget {
  final List<Map<String, dynamic>> recipes;
  final String Function(Map<String, dynamic>) titleOf;
  final String? Function(Map<String, dynamic>) thumbOf;
  final int? Function(Map<String, dynamic>) idOf;
  final String Function(Map<String, dynamic> recipe)? statusTextOf;

  final String? headerLabel; // e.g. "DINNER • Monday, 5 Jan"
  final int? currentId;

  // ✅ Old Inspire parity inputs
  final List<int> availableIds; // slot/course filtered by controller
  final String recentKey; // "$dayKey|$slot"
  final List<int> initialRecent; // last N picks for this slot
  final int recentWindow; // N

  const ChooseRecipePage({
    super.key,
    required this.recipes,
    required this.titleOf,
    required this.thumbOf,
    required this.idOf,
    this.statusTextOf,
    this.headerLabel,
    this.currentId,
    required this.availableIds,
    required this.recentKey,
    required this.initialRecent,
    required this.recentWindow,
  });

  @override
  State<ChooseRecipePage> createState() => _ChooseRecipePageState();
}

class _ChooseRecipePageState extends State<ChooseRecipePage> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  String _q = '';
  final Random _rng = Random();

  late List<int> _recent;
  int? _recommendedId;

  @override
  void initState() {
    super.initState();
    _recent = List<int>.from(widget.initialRecent);
    _recommendedId = _pickRecommendedId();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _status(Map<String, dynamic> r) =>
      (widget.statusTextOf?.call(r) ?? 'safe').toLowerCase();

  bool _isAllowedId(int id) => widget.availableIds.contains(id);

  Map<String, dynamic>? _recipeById(int id) {
    for (final r in widget.recipes) {
      final rid = widget.idOf(r);
      if (rid == id) return r;
    }
    return null;
  }

  List<Map<String, dynamic>> get _safePool {
    // ✅ slot-filtered + not blocked
    return widget.recipes.where((r) {
      final st = _status(r);
      if (st == 'blocked') return false;

      final id = widget.idOf(r);
      if (id == null) return false;
      if (!_isAllowedId(id)) return false;

      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredAll {
    final pool = _safePool;
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return pool;
    return pool.where((r) => widget.titleOf(r).toLowerCase().contains(q)).toList();
  }

  int? _pickRecommendedId() {
    // ✅ candidates = allowed ids (slot/course filtered), excluding current
    final ids = widget.availableIds.where((id) => id != widget.currentId).toList();
    if (ids.isEmpty) return null;

    // ✅ avoid recent window first (old Inspire behaviour)
    final fresh = ids.where((id) => !_recent.contains(id)).toList();
    final pool = fresh.isNotEmpty ? fresh : ids;

    if (pool.isEmpty) return null;
    return pool[_rng.nextInt(pool.length)];
  }

  void _shuffle() {
    setState(() => _recommendedId = _pickRecommendedId());
  }

  void _commitRecent(int pickedId) {
    _recent.add(pickedId);
    if (_recent.length > widget.recentWindow) {
      _recent = _recent.sublist(_recent.length - widget.recentWindow);
    }
  }

  void _returnPicked(int pickedId) {
    _commitRecent(pickedId);
    Navigator.of(context).pop(<String, dynamic>{
      'pickedId': pickedId,
      'recentKey': widget.recentKey,
      'recent': _recent,
    });
  }

  Widget _selectButton({required VoidCallback onPressed}) {
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text('Select'),
      ),
    );
  }

  Widget _selectButtonOnDark({required VoidCallback onPressed}) {
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white, width: 1),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text('Select'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recId = _recommendedId;
    final recRecipe = (recId != null) ? _recipeById(recId) : null;
    final visible = _filteredAll;

    return Scaffold(
      backgroundColor: _MPChooseStyle.bg,
      body: Column(
        children: [
          SubHeaderBar(title: 'Choose recipe'),

          if (widget.headerLabel != null && widget.headerLabel!.trim().isNotEmpty)
            Padding(
              padding: _MPChooseStyle.metaPad,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.headerLabel!, style: _MPChooseStyle.meta(context)),
              ),
            ),

          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // ==========================================================
                // ✅ Recommended (brand dark, full width, white text)
                // ==========================================================
                Container(
                  color: _MPChooseStyle.brandDark,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Recommended', style: _MPChooseStyle.recTitle(context)),
                          ),
                          TextButton.icon(
                            onPressed: _shuffle,
                            icon: const Icon(Icons.shuffle_rounded, size: 18, color: Colors.white),
                            label: const Text('Shuffle'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (recId == null || recRecipe == null)
                        Text('No recommendation available.', style: _MPChooseStyle.recMeta(context))
                      else
                        // ✅ Keep RecipeCard for consistency, but remove chevron + add Select button
                        RecipeCard(
                          title: widget.titleOf(recRecipe),
                          subtitle: (_status(recRecipe) == 'swap') ? '⚠️ Swap required' : null,
                          imageUrl: widget.thumbOf(recRecipe),
                          compact: false,
                          onTap: null, // 👈 force explicit CTA
                          trailing: _selectButton(
  onPressed: () => _returnPicked(recId),
),
                        ),
                    ],
                  ),
                ),

                // ==========================================================
                // ✅ Search (separated visually)
                // ==========================================================
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: SearchPill(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    hintText: 'Search recipes',
                    onChanged: (v) => setState(() => _q = v),
                    onSubmitted: (v) => setState(() => _q = v),
                    onClear: () {
                      _searchCtrl.clear();
                      setState(() => _q = '');
                    },
                  ),
                ),

                // ==========================================================
                // ✅ List (no All recipes / no Showing X)
                // ==========================================================
                Padding(
                  padding: _MPChooseStyle.sectionPad,
                  child: Column(
                    children: [
                      if (visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Center(
                            child: Text(
                              'No suitable recipes found.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        ...visible.map((r) {
                          final id = widget.idOf(r);
                          final swap = _status(r) == 'swap';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: RecipeCard(
                              title: widget.titleOf(r),
                              subtitle: swap ? '⚠️ Swap required' : null,
                              imageUrl: widget.thumbOf(r),
                              compact: false,
                              onTap: null, // 👈 force explicit CTA
                              trailing: (id == null)
                                  ? null
                                  : _selectButton(
                                      onPressed: () => _returnPicked(id),
                                    ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

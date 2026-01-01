// lib/recipes/recipe_search_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../app/sub_header_bar.dart';
import '../shared/search_pill.dart';

import 'recipe_detail_screen.dart';
import 'widgets/recipe_card.dart';

class RecipeSearchScreen extends StatefulWidget {
  const RecipeSearchScreen({
    super.key,
    required this.recipes,
    required this.favoriteIds,
    this.hintText = 'Search recipes or by ingredients',
  });

  final List<Map<String, dynamic>> recipes;
  final Set<int> favoriteIds;
  final String hintText;

  @override
  State<RecipeSearchScreen> createState() => _RecipeSearchScreenState();
}

class _RecipeSearchScreenState extends State<RecipeSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  String _query = '';
  List<Map<String, dynamic>> _results = const [];
  bool _hasSearched = false;

  // In-memory only
  final List<String> _recentSearches = <String>[];

  @override
  void initState() {
    super.initState();

    _results = const [];
    _hasSearched = false;

    // ensure clear icon updates as you type (SearchPill relies on controller.text)
    _controller.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ----------------------------
  // DATA HELPERS
  // ----------------------------

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
      return (t['rendered'] as String)
          .replaceAll('&#038;', '&')
          .replaceAll('&amp;', '&')
          .trim();
    }
    final s = (r['title'] ?? '').toString().trim();
    return s.isEmpty ? 'Untitled' : s;
  }

  int? _idOf(Map<String, dynamic> r) {
    final raw = r['id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.trim().isNotEmpty) return url.trim();
    }
    return null;
  }

  String? _subtitleOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map) {
      final courses = recipe['courses'];
      if (courses is List && courses.isNotEmpty) {
        final first = courses.first;
        if (first is String && first.trim().isNotEmpty) return first.trim();
        if (first is Map && first['name'] is String) {
          return (first['name'] as String).trim();
        }
      }
    }
    return null;
  }

  // ----------------------------
  // SEARCH
  // ----------------------------

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final q = v.trim();
      setState(() {
        _query = q;
        if (q.isEmpty) {
          _results = const [];
          _hasSearched = false;
        } else {
          _results = _filter(widget.recipes, q);
          _hasSearched = true;
        }
      });
    });
  }

  void _submitSearch(String q) {
    final query = q.trim();
    if (query.isEmpty) return;

    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );

    setState(() {
      _query = query;
      _results = _filter(widget.recipes, query);
      _hasSearched = true;
      _addRecent(query);
    });

    _focus.unfocus();
  }

  void _addRecent(String q) {
    final s = q.trim();
    if (s.isEmpty) return;

    _recentSearches.removeWhere((x) => x.toLowerCase() == s.toLowerCase());
    _recentSearches.insert(0, s);

    if (_recentSearches.length > 10) {
      _recentSearches.removeRange(10, _recentSearches.length);
    }
  }

  List<Map<String, dynamic>> _filter(
    List<Map<String, dynamic>> recipes,
    String query,
  ) {
    if (query.isEmpty) return const [];
    final q = query.toLowerCase();

    return recipes.where((r) {
      final title = _titleOf(r).toLowerCase();
      if (title.contains(q)) return true;

      final recipe = r['recipe'];
      if (recipe is Map) {
        final keywords = <String>[];

        for (final k in ['courses', 'tags', 'categories', 'keywords']) {
          final v = recipe[k];
          if (v is List) {
            for (final item in v) {
              if (item is String) keywords.add(item);
              if (item is Map && item['name'] is String) {
                keywords.add(item['name'] as String);
              }
            }
          }
        }

        if (keywords.join(' ').toLowerCase().contains(q)) return true;
      }

      return false;
    }).toList();
  }

  void _openRecipe(Map<String, dynamic> r) {
    final id = _idOf(r);
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: id)),
    );
  }

  void _clearQuery() {
    _controller.clear();
    setState(() {
      _query = '';
      _results = const [];
      _hasSearched = false;
    });
    _focus.requestFocus();
  }

  // ----------------------------
  // UI: EMPTY STATE (recent only)
  // ----------------------------

  Widget _buildEmptySuggestions(BuildContext context) {
    if (_recentSearches.isEmpty) {
      return const SizedBox(height: 24);
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent searches',
            style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              for (final q in _recentSearches)
                _RecentRow(
                  text: q,
                  onTap: () => _submitSearch(q),
                  onRemove: () => setState(() => _recentSearches.remove(q)),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ----------------------------
  // BUILD
  // ----------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final showEmptyState = _query.isEmpty && !_hasSearched;
    final showNoResults = _query.isNotEmpty && _hasSearched && _results.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: SafeArea(
        child: Column(
          children: [
            const SubHeaderBar(title: 'SEARCH RECIPES'),

            // ✅ Use the shared SearchPill (SSoT)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: SearchPill(
                controller: _controller,
                focusNode: _focus,
                hintText: widget.hintText,
                autofocus: true,
                onChanged: _onQueryChanged,
                onSubmitted: _submitSearch,
                onClear: _clearQuery,
              ),
            ),

            Expanded(
              child: showEmptyState
                  ? SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: _buildEmptySuggestions(context),
                    )
                  : showNoResults
                      ? Center(
                          child: Text(
                            'No results',
                            style:
                                (theme.textTheme.titleMedium ?? const TextStyle())
                                    .copyWith(
                              color: Colors.black.withOpacity(0.55),
                            ),
                          ),
                        )
                      : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final r = _results[i];
                            final id = _idOf(r);

                            return RecipeCard(
                              title: _titleOf(r),
                              subtitle: _subtitleOf(r),
                              imageUrl: _thumbOf(r),
                              onTap: () => _openRecipe(r),
                              badge: (id != null &&
                                      widget.favoriteIds.contains(id))
                                  ? Container(
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
                                    )
                                  : null,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.text,
    required this.onTap,
    required this.onRemove,
  });

  final String text;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Text(
          text,
          style: (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
              .copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        onTap: onTap,
        trailing: GestureDetector(
          onTap: onRemove,
          child: Icon(
            Icons.close,
            color: Colors.black.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}

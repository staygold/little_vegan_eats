import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/text.dart';
import '../utils/images.dart';
import 'recipe_detail_screen.dart';

class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({super.key});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'LittleVeganEatsApp/1.0',
      },
    ),
  );

  final ScrollController _scroll = ScrollController();

  final TextEditingController _searchCtrl = TextEditingController();
String _query = '';

  static const int _perPage = 50; // WP usually allows up to 100
  int _page = 1;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  String? _error;
  List<Map<String, dynamic>> _items = [];

  String _selectedCategory = 'All';

  List<String> _coursesOf(Map<String, dynamic> r) {
  final v = r['wprm_course'];

  if (v is List) {
    return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }

  if (v is String && v.trim().isNotEmpty) {
    return [v.trim()];
  }

  return const [];
}



List<String> get _courseOptions {
  final set = <String>{};

  for (final r in _items) {
    set.addAll(_coursesOf(r));
  }

  final list = set.toList()..sort();
  return ['All', ...list];
}


  @override
  void initState() {
    super.initState();
    _loadFirstPage();

    _scroll.addListener(() {
      final nearBottom =
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 300;

      if (nearBottom && !_loading && !_loadingMore && _hasMore) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
  _searchCtrl.dispose();
  _scroll.dispose();
  super.dispose();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = true;
      _items = [];
    });

    try {
      final newItems = await _fetchPage(_page);
      setState(() {
        _items = newItems;
        _hasMore = newItems.length == _perPage;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);

    try {
      final nextPage = _page + 1;
      final newItems = await _fetchPage(nextPage);

      setState(() {
        _page = nextPage;
        _items = [..._items, ...newItems];
        _hasMore = newItems.length == _perPage;
        _loadingMore = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingMore = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPage(int page) async {
    final res = await _dio.get(
      'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe',
      queryParameters: {'per_page': _perPage, 'page': page},
    );

    final data = res.data;
    if (data is! List) {
      throw Exception('Unexpected response shape (expected list).');
    }

    return data.cast<Map<String, dynamic>>();
  }

  String _titleOf(Map<String, dynamic> r) =>
      (r['title']?['rendered'] as String?)?.trim().isNotEmpty == true
      ? (r['title']['rendered'] as String)
      : 'Untitled';

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
  }

 
@override
Widget build(BuildContext context) {
  final q = _query.trim().toLowerCase();

  final visible = _items.where((r) {
    // 1) Course filter (uses wprm_course via your helper)
    final courses = _coursesOf(r);
    final matchesCourse =
        _selectedCategory == 'All' ? true : courses.contains(_selectedCategory);

    // 2) Search (title + ingredients)
    final titleMatch = q.isEmpty ? true : _titleOf(r).toLowerCase().contains(q);

    final ingredients = r['recipe']?['ingredients_flat'];
    final ingredientMatch = q.isEmpty
        ? true
        : (ingredients is List
            ? ingredients.any((row) {
                if (row is! Map) return false;
                final name = (row['name'] ?? '').toString().toLowerCase();
                final notes =
                    stripHtml((row['notes'] ?? '').toString()).toLowerCase();
                return name.contains(q) || notes.contains(q);
              })
            : false);

    return matchesCourse && (titleMatch || ingredientMatch);
  }).toList();

  return Scaffold(
    appBar: AppBar(
  title: TextField(
    controller: _searchCtrl,
    decoration: InputDecoration(
      hintText: 'Search recipes...',
      border: InputBorder.none,
      suffixIcon: _query.isEmpty
          ? const Icon(Icons.search)
          : IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _query = '');
              },
            ),
    ),
    onChanged: (v) => setState(() => _query = v),
  ),
  actions: [
    IconButton(
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout),
      onPressed: () async {
        await FirebaseAuth.instance.signOut();
      },
    ),
  ],
),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadFirstPage,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  // FILTER DROPDOWN
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        const Text('Course:'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedCategory,
                            items: _courseOptions
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedCategory = v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // LIST
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadFirstPage,
                      child: ListView.separated(
                        controller: _scroll,
                        itemCount: visible.length + (_loadingMore ? 1 : 0),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (_loadingMore && index == visible.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final r = visible[index];
                          final id = r['id'] as int?;
                          final title = _titleOf(r);
                          final thumb = _thumbOf(r);

                          debugPrint('TITLE: ${_titleOf(r)}  wprm_course: ${r['wprm_course']}');


                          // show first course (if any) just for display
                          final courses = _coursesOf(r);
                          final courseLabel =
                              courses.isEmpty ? 'No course' : courses.first;

                          return ListTile(
                            leading: SizedBox(
                              width: 56,
                              height: 56,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: thumb == null
                                    ? Container(
                                        color: const Color(0xFFEFEFEF),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.image_not_supported,
                                          color: Colors.grey,
                                        ),
                                      )
                                    : Image.network(
                                        thumb,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          final fallbackUrl =
                                              fallbackFromJetpack(thumb);

                                          if (fallbackUrl == thumb) {
                                            return Container(
                                              color: const Color(0xFFEFEFEF),
                                              alignment: Alignment.center,
                                              child: const Icon(
                                                Icons.restaurant_menu,
                                                size: 22,
                                                color: Colors.grey,
                                              ),
                                            );
                                          }

                                          return Image.network(
                                            fallbackUrl,
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                            errorBuilder: (context, error,
                                                stackTrace) {
                                              return Container(
                                                color:
                                                    const Color(0xFFEFEFEF),
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                  Icons.restaurant_menu,
                                                  size: 22,
                                                  color: Colors.grey,
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      ),
                              ),
                            ),
                            title: Text('$title  •  $courseLabel'),
                            subtitle:
                                id == null ? null : Text('Recipe ID: $id'),
                            onTap: id == null
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            RecipeDetailScreen(id: id),
                                      ),
                                    ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                         ),
  );
} // <-- closes build()

} // <-- closes _RecipeListScreenState
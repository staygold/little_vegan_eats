import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

String stripHtml(String input) {
  final first = html_parser.parseFragment(input).text ?? '';
  final second = html_parser.parseFragment(first).text ?? '';
  final cleaned = second.replaceAll(RegExp(r'<[^>]*>'), '');
  return cleaned.replaceAll('\u00A0', ' ').trim();
}

void main() {
  runApp(const LittleVeganEatsApp());
}

class LittleVeganEatsApp extends StatelessWidget {
  const LittleVeganEatsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Little Vegan Eats',
      theme: ThemeData(useMaterial3: true),
      home: const RecipeListScreen(),
    );
  }
}

/// List screen using the WPRM REST endpoint:
/// https://littleveganeats.co/wp-json/wp/v2/wprm_recipe
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

  static const int _perPage = 50; // WP usually allows up to 100
  int _page = 1;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadFirstPage();

    _scroll.addListener(() {
      final nearBottom = _scroll.position.pixels >
          _scroll.position.maxScrollExtent - 300;

      if (nearBottom && !_loading && !_loadingMore && _hasMore) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
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
    if (data is! List) throw Exception('Unexpected response shape (expected list).');

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
    return Scaffold(
      appBar: AppBar(title: const Text('Little Vegan Eats')),
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
              : RefreshIndicator(
                  onRefresh: _loadFirstPage,
                  child: ListView.separated(
                    controller: _scroll,
                    itemCount: _items.length + (_loadingMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (_loadingMore && index == _items.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final r = _items[index];
                      final id = r['id'] as int?;
                      final title = _titleOf(r);
                      final thumb = _thumbOf(r);

                      return ListTile(
                        leading: thumb == null
                            ? const SizedBox(width: 56, height: 56)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  thumb,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                ),
                              ),
                        title: Text(title),
                        subtitle: id == null ? null : Text('Recipe ID: $id'),
                        onTap: id == null
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RecipeDetailScreen(id: id),
                                  ),
                                ),
                      );
                    },
                  ),
                ),
    );
  }
}


class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({super.key, required this.id});
  final int id;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'LittleVeganEatsApp/1.0',
      },
    ),
  );

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _dio.get(
        'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe/${widget.id}',
      );
      final data = res.data;
      if (data is! Map) throw Exception('Unexpected response shape.');
      setState(() {
        _data = data.cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = (_data?['recipe'] is Map<String, dynamic>)
        ? (_data!['recipe'] as Map<String, dynamic>)
        : null;

    final title = (_data?['title']?['rendered'] as String?) ?? 'Recipe';
    final servings = recipe?['servings'];
    final servingsUnit = recipe?['servings_unit'];
    final prep = recipe?['prep_time'];
    final cook = recipe?['cook_time'];

    final ingredientsFlat = (recipe?['ingredients_flat'] is List)
        ? (recipe!['ingredients_flat'] as List)
        : const [];

    final stepsFlat = (recipe?['instructions_flat'] is List)
        ? (recipe!['instructions_flat'] as List)
        : const [];

    final cleanSteps = stepsFlat
        .whereType<Map>()
        .map((s) => stripHtml((s['text'] ?? '').toString()))
        .where((t) => t.trim().isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
                        ElevatedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(title, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      'Serves: ${servings ?? '-'} ${servingsUnit ?? ''} | Prep: ${prep ?? '-'}m | Cook: ${cook ?? '-'}m',
                    ),
                    const SizedBox(height: 16),

                    FilledButton(
                      onPressed: cleanSteps.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CookModeScreen(
                                    title: title,
                                    steps: cleanSteps,
                                  ),
                                ),
                              ),
                      child: const Text('Start Cook Mode'),
                    ),
                    const SizedBox(height: 16),

                    Text('Ingredients',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    ...ingredientsFlat.map((row) {
                      if (row is! Map) return const SizedBox.shrink();
                      final type = row['type'];

                      if (type == 'group') {
                        final name = (row['name'] ?? '').toString().trim();
                        if (name.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 6),
                          child: Text(name,
                              style: Theme.of(context).textTheme.titleSmall),
                        );
                      }

                      final amount = (row['amount'] ?? '').toString().trim();
                      final unit = (row['unit'] ?? '').toString().trim();
                      final name = (row['name'] ?? '').toString().trim();
                      final notes =
                          stripHtml((row['notes'] ?? '').toString()).trim();

                      final line =
                          [amount, unit, name].where((s) => s.isNotEmpty).join(' ');
                      if (line.isEmpty) return const SizedBox.shrink();

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $line${notes.isEmpty ? '' : ' — $notes'}'),
                      );
                    }),

                    const SizedBox(height: 16),
                    Text('Steps', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    ...cleanSteps.asMap().entries.map((entry) {
                      final i = entry.key + 1;
                      final text = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('$i. $text'),
                      );
                    }),
                  ],
                ),
    );
  }
}

class CookModeScreen extends StatefulWidget {
  const CookModeScreen({super.key, required this.title, required this.steps});
  final String title;
  final List<String> steps;

  @override
  State<CookModeScreen> createState() => _CookModeScreenState();
}

class _CookModeScreenState extends State<CookModeScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final hasSteps = widget.steps.isNotEmpty;
    final stepText = hasSteps ? widget.steps[index] : 'No steps found.';

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasSteps ? 'Step ${index + 1} of ${widget.steps.length}' : 'Cook Mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  stepText,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (!hasSteps || index == 0)
                        ? null
                        : () => setState(() => index--),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (!hasSteps || index >= widget.steps.length - 1)
                        ? null
                        : () => setState(() => index++),
                    child: const Text('Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

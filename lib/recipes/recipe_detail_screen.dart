import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../utils/text.dart';
import '../utils/images.dart';
import 'cook_mode_screen.dart';

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
    String? _str(dynamic v) =>
    (v is String && v.trim().isNotEmpty) ? v.trim() : null;

final imageUrl =
    _str(recipe?['image_url_full']) ?? // if available
    _str(recipe?['image_url']) ??
    _str(recipe?['image']) ??
    _str(recipe?['thumbnail_url']);

final heroUrl = upscaleJetpackImage(imageUrl, w: 1400, h: 788);



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
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ClipRRect(
  borderRadius: BorderRadius.circular(12),
  child: AspectRatio(
    aspectRatio: 16 / 9,
    child: imageUrl == null
        ? Container(
            color: const Color(0xFFEFEFEF),
            alignment: Alignment.center,
            child: const Text('No imageUrl in API'),
          )
        : Image.network(
  heroUrl ?? imageUrl!,
  fit: BoxFit.cover,
  filterQuality: FilterQuality.high,
  errorBuilder: (context, error, stackTrace) {
    return Container(
      color: const Color(0xFFEFEFEF),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  },
),
  ),
),
const SizedBox(height: 16),
                
                


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
                            builder: (_) =>
                                CookModeScreen(title: title, steps: cleanSteps),
                          ),
                        ),
                  child: const Text('Start Cook Mode'),
                ),
                const SizedBox(height: 16),

                Text(
                  'Ingredients',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                ...ingredientsFlat.map((row) {
                  if (row is! Map) return const SizedBox.shrink();
                  final type = row['type'];

                  if (type == 'group') {
                    final name = (row['name'] ?? '').toString().trim();
                    if (name.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    );
                  }

                  final amount = (row['amount'] ?? '').toString().trim();
                  final unit = (row['unit'] ?? '').toString().trim();
                  final name = (row['name'] ?? '').toString().trim();
                  final notes = stripHtml(
                    (row['notes'] ?? '').toString(),
                  ).trim();

                  final line = [
                    amount,
                    unit,
                    name,
                  ].where((s) => s.isNotEmpty).join(' ');
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
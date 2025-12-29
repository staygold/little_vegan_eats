import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../utils/text.dart';
import '../utils/images.dart';
import '../recipes/recipe_repository.dart';
import '../recipes/serving_engine.dart';
import '../recipes/favorites_service.dart';
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
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  // ✅ Used for serving guidance + scaling only
  int _adults = 2;
  int _kids = 1;

  // Keeps what Firestore said (internal only; no UI shown)
  int _profileAdults = 2;
  int _profileKids = 1;

  // Ingredient scaling multiplier
  double _scale = 1.0;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  @override
  void initState() {
    super.initState();
    _wireFamilyProfile();
    _load(forceRefresh: false);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  // ----------------------------
  // Family profile wiring (silent: no "Use profile" UI)
  // ----------------------------

  void _wireFamilyProfile() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _profileSub?.cancel();
      if (user == null) return;

      final docRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      _profileSub = docRef.snapshots().listen((snap) {
        final data = snap.data();
        if (data == null) return;

        final adults = (data['adults'] as List?) ?? const [];
        final children = (data['children'] as List?) ?? const [];

        // Count only "named" entries
        final adultCount = adults.where((e) {
          if (e is! Map) return false;
          final name = (e['name'] ?? '').toString().trim();
          return name.isNotEmpty;
        }).length;

        final kidCount = children.where((e) {
          if (e is! Map) return false;
          final name = (e['name'] ?? '').toString().trim();
          return name.isNotEmpty;
        }).length;

        final nextAdults = adultCount > 0 ? adultCount : 1;
        final nextKids = kidCount;

        if (!mounted) return;

        // Update internal "profile" values.
        // Only auto-update current values if they were still following old profile.
        if (nextAdults != _profileAdults || nextKids != _profileKids) {
          setState(() {
            final prevProfileAdults = _profileAdults;
            final prevProfileKids = _profileKids;

            _profileAdults = nextAdults;
            _profileKids = nextKids;

            final followsAdults = _adults == prevProfileAdults;
            final followsKids = _kids == prevProfileKids;

            if (followsAdults) _adults = _profileAdults;
            if (followsKids) _kids = _profileKids;
          });
        }
      });
    });
  }

  // ----------------------------
  // Data load (cache-first)
  // ----------------------------

  Future<void> _load({required bool forceRefresh}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await RecipeRepository.ensureRecipesLoaded(
        backgroundRefresh: true,
        forceRefresh: forceRefresh,
      );

      final cached = _findById(list, widget.id);
      if (cached != null) {
        setState(() {
          _data = cached;
          _loading = false;
        });
        return;
      }

      final res = await _dio.get(
        'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe/${widget.id}',
      );
      final data = res.data;
      if (data is! Map) throw Exception('Unexpected response shape.');

      setState(() {
        _data = Map<String, dynamic>.from(data.cast<String, dynamic>());
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _findById(List<Map<String, dynamic>> list, int id) {
    for (final r in list) {
      final rid = r['id'];
      if (rid is int && rid == id) return r;
      if (rid is String && int.tryParse(rid) == id) return r;
    }
    return null;
  }

  // ----------------------------
  // Serving panel + scaling CTA
  // ----------------------------

  ServingAdvice? _safeAdvice(Map<String, dynamic>? recipe) {
    if (recipe == null) return null;
    try {
      return buildServingAdvice(
        recipe: recipe,
        adults: _adults,
        kids: _kids,
      );
    } catch (_) {
      return null;
    }
  }

  void _applyScale(double value) {
    setState(() => _scale = value);
  }

  Widget _servingPanel(BuildContext context, Map<String, dynamic>? recipe) {
    final advice = _safeAdvice(recipe);
    if (advice == null) return const SizedBox.shrink();

    final needsMore = advice.multiplierRaw > 1.0;
    final canHalf = advice.canHalf && advice.mode == ServingMode.shared;

    final recommended = advice.recommendedMultiplier;
    final showRecommended = needsMore && recommended != null;

    final icon = needsMore ? Icons.warning_amber_rounded : Icons.check_circle;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFF4F6F7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  advice.headline,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(advice.detailLine),
          if (advice.extra != null && advice.extra!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              advice.extra!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),

          // People chips (NO profile label + NO "use profile" button)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _peopleChip('Adults', _adults, onChanged: (v) {
                setState(() => _adults = v);
              }),
              _peopleChip('Kids', _kids, onChanged: (v) {
                setState(() => _kids = v);
              }),
            ],
          ),

          const SizedBox(height: 10),

          // CTAs
          if (showRecommended) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _applyScale(recommended),
                    child: Text(
                      'Update ingredients (${_fmtMultiplier(recommended)})',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_scale != 1.0)
                  OutlinedButton(
                    onPressed: () => _applyScale(1.0),
                    child: const Text('Reset'),
                  ),
              ],
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canHalf)
                  OutlinedButton(
                    onPressed: () => _applyScale(0.5),
                    child: const Text('Make half batch (0.5x)'),
                  ),
                if (_scale != 1.0)
                  OutlinedButton(
                    onPressed: () => _applyScale(1.0),
                    child: const Text('Reset ingredients'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _peopleChip(
    String label,
    int value, {
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDFE3E6)),
        color: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: $value'),
          const SizedBox(width: 8),
          InkWell(
            onTap: value > 0 ? () => onChanged(value - 1) : null,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: value > 0 ? Colors.black87 : Colors.black26,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => onChanged(value + 1),
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.add_circle_outline, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------
  // Nutrition (Adult + Child only)
  // ----------------------------

  Map<String, dynamic>? _nutritionMap(Map<String, dynamic>? recipe) {
    if (recipe == null) return null;
    final n = recipe['nutrition'];
    if (n is Map) return Map<String, dynamic>.from(n.cast<String, dynamic>());
    return null;
  }

  List<dynamic>? _parseValueUnit(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final m = RegExp(r'^(-?\d+(?:\.\d+)?)\s*([^\d].*)?$').firstMatch(s);
    if (m == null) return null;

    final value = double.tryParse(m.group(1) ?? '');
    if (value == null) return null;

    final unit = (m.group(2) ?? '').trim();
    return [value, unit];
  }

  String _scaleNutritionString(dynamic raw, double mult) {
    if (raw == null) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty) return '-';

    final parsed = _parseValueUnit(s);
    if (parsed == null) return s;

    final value = (parsed[0] as double) * mult;
    final unit = parsed[1] as String;

    final pretty = _fmtSmart(value);
    return unit.isEmpty ? pretty : '$pretty $unit';
  }

  Widget _nutritionPanel(BuildContext context, Map<String, dynamic>? recipe) {
    final n = _nutritionMap(recipe);
    if (n == null || n.isEmpty) return const SizedBox.shrink();

    dynamic pick(List<String> keys) {
      for (final k in keys) {
        if (!n.containsKey(k)) continue;
        final v = n[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isEmpty) continue;
        return v;
      }
      return null;
    }

    final calories = pick(['calories', 'kcal', 'energy']);
    final fat = pick(['fat', 'total_fat']);
    final satFat = pick(['saturated_fat', 'sat_fat', 'saturates']);
    final carbs = pick(['carbohydrates', 'carbs']);
    final sugar = pick(['sugar', 'sugars']);
    final fibre = pick(['fiber', 'fibre']);
    final protein = pick(['protein']);
    final iron = pick(['iron']);
    final calcium = pick(['calcium']);
    final vitaminC = pick(['vitamin_c', 'vitaminC']);
    final sodium = pick(['sodium', 'salt']);

    final hasAny = [
      calories,
      fat,
      satFat,
      carbs,
      sugar,
      fibre,
      protein,
      iron,
      calcium,
      vitaminC,
      sodium,
    ].any((v) => v != null);

    if (!hasAny) return const SizedBox.shrink();

    Widget row({
      required String label,
      required dynamic value,
      bool strong = false,
      bool isSub = false,
    }) {
      if (value == null) return const SizedBox.shrink();

      final labelStyle = isSub
          ? Theme.of(context).textTheme.bodySmall
          : Theme.of(context).textTheme.bodyMedium;

      final valueStyle = TextStyle(
        fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
        fontSize: isSub ? 12 : null,
      );

      return Padding(
        padding: EdgeInsets.only(bottom: isSub ? 4 : 8, left: isSub ? 12 : 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isSub ? '• $label' : label,
                style: labelStyle,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 86,
              child: Text(
                _scaleNutritionString(value, 1.0),
                textAlign: TextAlign.right,
                style: valueStyle,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 86,
              child: Text(
                _scaleNutritionString(value, 0.5),
                textAlign: TextAlign.right,
                style: valueStyle,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Estimated Nutrition',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: SizedBox()),
            SizedBox(
              width: 86,
              child: Text(
                'Adult',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 86,
              child: Text(
                'Child',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        row(label: 'Calories', value: calories, strong: true),
        row(label: 'Fat', value: fat, strong: true),
        row(label: 'Sat fat', value: satFat, isSub: true),
        row(label: 'Carbs', value: carbs, strong: true),
        row(label: 'Sugar', value: sugar, isSub: true),
        row(label: 'Fibre', value: fibre, strong: true),
        row(label: 'Protein', value: protein, strong: true),
        row(label: 'Iron', value: iron, strong: true),
        row(label: 'Calcium', value: calcium, strong: true),
        row(label: 'Vitamin C', value: vitaminC, strong: true),
        row(label: 'Sodium', value: sodium, strong: true),
        const SizedBox(height: 6),
        Text(
          'Child values are estimated at 0.5 adult serving.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ----------------------------
  // Ingredient scaling helpers
  // ----------------------------

  String _scaledAmount(String rawAmount, double mult) {
    final a = rawAmount.trim();
    if (a.isEmpty) return a;
    if (mult == 1.0) return a;

    final mX = RegExp(r'^\s*([0-9]+(?:\.\d+)?)(\s*x\s*)$',
            caseSensitive: false)
        .firstMatch(a);
    if (mX != null) {
      final n = double.tryParse(mX.group(1) ?? '');
      if (n == null) return a;
      final scaled = n * mult;
      return '${_fmtSmart(scaled)} x';
    }

    final mMixed =
        RegExp(r'^\s*(\d+)\s+(\d+)\s*/\s*(\d+)\s*$').firstMatch(a);
    if (mMixed != null) {
      final whole = double.tryParse(mMixed.group(1) ?? '');
      final nume = double.tryParse(mMixed.group(2) ?? '');
      final deno = double.tryParse(mMixed.group(3) ?? '');
      if (whole == null || nume == null || deno == null || deno == 0) return a;
      final value = whole + (nume / deno);
      return _fmtSmart(value * mult);
    }

    final mFrac = RegExp(r'^\s*(\d+)\s*/\s*(\d+)\s*$').firstMatch(a);
    if (mFrac != null) {
      final nume = double.tryParse(mFrac.group(1) ?? '');
      final deno = double.tryParse(mFrac.group(2) ?? '');
      if (nume == null || deno == null || deno == 0) return a;
      final value = nume / deno;
      return _fmtSmart(value * mult);
    }

    final mNum = RegExp(r'^\s*([0-9]+(?:\.\d+)?)').firstMatch(a);
    if (mNum != null) {
      final n = double.tryParse(mNum.group(1) ?? '');
      if (n == null) return a;
      final scaled = n * mult;

      final replaced = a.replaceFirst(mNum.group(1)!, _fmtSmart(scaled));
      return replaced.trim();
    }

    return a;
  }

  String _fmtSmart(double v) {
    if ((v - v.roundToDouble()).abs() < 0.0001) return v.round().toString();
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  String _fmtMultiplier(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? '${s.substring(0, s.length - 2)}x' : '${s}x';
  }

  // ----------------------------
  // UI
  // ----------------------------

  @override
  Widget build(BuildContext context) {
    final recipe = (_data?['recipe'] is Map)
        ? Map<String, dynamic>.from(_data!['recipe'] as Map)
        : null;

    String? _str(dynamic v) =>
        (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    final title = (_data?['title']?['rendered'] as String?) ??
        (recipe?['name'] as String?) ??
        'Recipe';

    final prep = recipe?['prep_time'];
    final cook = recipe?['cook_time'];

    final imageUrl = _str(recipe?['image_url_full']) ??
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
      appBar: AppBar(
        title: Text(title),
        actions: [
          StreamBuilder<bool>(
            stream: FavoritesService.watchIsFavorite(widget.id),
            builder: (context, snap) {
              final isFav = snap.data == true;
              return IconButton(
                tooltip:
                    isFav ? 'Remove from favourites' : 'Save to favourites',
                icon: Icon(isFav ? Icons.star : Icons.star_border),
                onPressed: () async {
                  final newState = await FavoritesService.toggleFavorite(
                    recipeId: widget.id,
                    title: title,
                    imageUrl: imageUrl,
                  );

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(newState
                          ? 'Saved to favourites'
                          : 'Removed from favourites'),
                    ),
                  );
                },
              );
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
                          onPressed: () => _load(forceRefresh: false),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(forceRefresh: true),
                  child: ListView(
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
                                  child: const Icon(Icons.image_outlined,
                                      color: Colors.grey),
                                )
                              : Image.network(
                                  heroUrl ?? imageUrl,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: const Color(0xFFEFEFEF),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                          Icons.image_not_supported,
                                          color: Colors.grey),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(title,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),

                      _servingPanel(context, recipe),
                      const SizedBox(height: 12),

                      Text('Prep: ${prep ?? '-'}m | Cook: ${cook ?? '-'}m'),
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
                      const SizedBox(height: 18),

                      _nutritionPanel(context, recipe),
                      if (_nutritionMap(recipe) != null)
                        const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ingredients',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_scale != 1.0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF1F1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Scaled ${_fmtMultiplier(_scale)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      ...ingredientsFlat.map((row) {
                        if (row is! Map) return const SizedBox.shrink();
                        final type = row['type'];

                        if (type == 'group') {
                          final name = (row['name'] ?? '').toString().trim();
                          if (name.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding:
                                const EdgeInsets.only(top: 12, bottom: 6),
                            child: Text(
                              name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          );
                        }

                        final rawAmount =
                            (row['amount'] ?? '').toString().trim();
                        final amount = _scaledAmount(rawAmount, _scale);

                        final unit = (row['unit'] ?? '').toString().trim();
                        final name = (row['name'] ?? '').toString().trim();
                        final notes =
                            stripHtml((row['notes'] ?? '').toString()).trim();

                        final line = [amount, unit, name]
                            .where((s) => s.isNotEmpty)
                            .join(' ');
                        if (line.isEmpty) return const SizedBox.shrink();

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                              '• $line${notes.isEmpty ? '' : ' — $notes'}'),
                        );
                      }),

                      const SizedBox(height: 16),
                      Text('Steps',
                          style: Theme.of(context).textTheme.titleMedium),
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
                ),
    );
  }
}

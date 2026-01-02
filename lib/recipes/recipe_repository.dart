// lib/recipes/recipe_repository.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'recipe_cache.dart';

/// Minimal local unawaited helper (so you don't need pedantic).
void unawaited(Future<void> f) {}

class RecipeRepository {
  RecipeRepository._();

  static final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'LittleVeganEatsApp/1.0',
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static const int _perPage = 50;
  static const Duration _minCheckInterval = Duration(minutes: 1);
  static Future<void>? _refreshInFlight;

  static const String _boxName = 'recipe_cache_box';
  static const String _keyLastCheckedAtMs = 'recipes_last_checked_at_ms';
  static const String _keyLatestModified = 'recipes_latest_modified';

  // ----------------------------
  // Taxonomy Endpoints
  // ----------------------------
  static const String _epCuisine = 'https://littleveganeats.co/wp-json/wp/v2/wprm_cuisine';
  static const String _epSuitableFor = 'https://littleveganeats.co/wp-json/wp/v2/wprm_suitable_for';
  static const String _epNutritionTag = 'https://littleveganeats.co/wp-json/wp/v2/wprm_nutrition_tag';
  static const String _epCollectionsPlural = 'https://littleveganeats.co/wp-json/wp/v2/wprm_collections';
  static const String _epCollectionsSingular = 'https://littleveganeats.co/wp-json/wp/v2/wprm_collection';

  static Map<int, String> _cuisineMap = {};
  static Map<int, String> _suitableForMap = {};
  static Map<int, String> _nutritionTagMap = {};
  static Map<int, String> _collectionMap = {};

  static DateTime? _termMapsFetchedAt;
  static const Duration _termMapsTtl = Duration(hours: 6);

  static bool _needsTermRefresh() {
    final t = _termMapsFetchedAt;
    if (t == null) return true;
    return DateTime.now().difference(t) > _termMapsTtl;
  }

  static Future<Map<int, String>> _fetchAllTermsAsMap(String endpoint) async {
    final map = <int, String>{};
    int page = 1;

    while (true) {
      try {
        final res = await _dio.get(
          endpoint,
          queryParameters: {'per_page': 100, 'page': page, '_fields': 'id,name'},
        );
        final data = res.data;
        if (data is! List || data.isEmpty) break;

        for (final item in data) {
          if (item is! Map) continue;
          final id = int.tryParse('${item['id']}');
          final name = (item['name'] ?? '').toString().trim();
          if (id != null && id > 0 && name.isNotEmpty) map[id] = name;
        }
        if (data.length < 100) break;
        page++;
      } catch (e) {
        break;
      }
    }
    return map;
  }

  static Future<void> _ensureTermMapsFresh() async {
    if (!_needsTermRefresh() && _cuisineMap.isNotEmpty) return;

    await Future.wait([
      _safeUpdateMap(_epCuisine, _cuisineMap),
      _safeUpdateMap(_epSuitableFor, _suitableForMap),
      _safeUpdateMap(_epNutritionTag, _nutritionTagMap),
      _safeUpdateMap(_epCollectionsSingular, _collectionMap).then((_) {
        if (_collectionMap.isEmpty) return _safeUpdateMap(_epCollectionsPlural, _collectionMap);
      }),
    ]);

    _termMapsFetchedAt = DateTime.now();
  }

  static Future<void> _safeUpdateMap(String endpoint, Map<int, String> target) async {
    final map = await _fetchAllTermsAsMap(endpoint);
    target.addAll(map);
  }

  // ----------------------------
  // Extract & Learn Data
  // ----------------------------

  static void _learnTermsFromRecipes(List<Map<String, dynamic>> recipes) {
    void learn(dynamic fieldVal, Map<int, String> map) {
      if (fieldVal is List) {
        for (final item in fieldVal) {
          if (item is Map) {
            final id = int.tryParse('${item['term_id'] ?? item['id']}');
            final name = item['name']?.toString().trim();
            if (id != null && name != null && name.isNotEmpty) {
              map[id] = name;
            }
          }
        }
      }
    }

    for (final r in recipes) {
      learn(r['wprm_cuisine'], _cuisineMap);
      learn(r['wprm_suitable_for'], _suitableForMap);
      learn(r['wprm_nutrition_tag'], _nutritionTagMap);
      
      learn(r['wprm_collections'], _collectionMap);
      learn(r['wprm_collection'], _collectionMap);
      if (r['recipe'] is Map && (r['recipe']['tags'] is Map)) {
        final tags = r['recipe']['tags'];
        if (tags is Map) {
          learn(tags['collection'], _collectionMap);
          learn(tags['collections'], _collectionMap);
        }
      }
    }
  }

  static void _promoteNestedFields(Map<String, dynamic> r) {
    if (r['wprm_collections'] == null) {
      dynamic found;
      if (r['wprm_collection'] != null) found = r['wprm_collection'];
      else if (r['recipe'] is Map) {
        final recipe = r['recipe'];
        if (recipe['wprm_collections'] != null) found = recipe['wprm_collections'];
        else if (recipe['collections'] != null) found = recipe['collections'];
        else if (recipe['tags'] is Map) {
          final tags = recipe['tags'];
          found = tags['collection'] ?? tags['collections'];
        }
      }
      if (found != null) r['wprm_collections'] = found;
    }
  }

  static Future<void> _normalizeWprmTaxonomyFields(List<Map<String, dynamic>> recipes) async {
    _learnTermsFromRecipes(recipes);
    await _ensureTermMapsFresh();

    for (final r in recipes) {
      _promoteNestedFields(r);

      r['wprm_cuisine'] = _resolveTerms(r['wprm_cuisine'], _cuisineMap, 'Cuisine');
      r['wprm_suitable_for'] = _resolveTerms(r['wprm_suitable_for'], _suitableForMap, 'Suitable');
      r['wprm_nutrition_tag'] = _resolveTerms(r['wprm_nutrition_tag'], _nutritionTagMap, 'Nutrition');
      r['wprm_collections'] = _resolveTerms(r['wprm_collections'], _collectionMap, 'Collection');
    }
  }

  static List<String> _resolveTerms(dynamic raw, Map<int, String> map, String prefix) {
    if (raw == null) return const [];
    final out = <String>[];

    void add(dynamic val) {
      if (val is String && val.isNotEmpty) {
        final id = int.tryParse(val);
        if (id != null && map.containsKey(id)) {
          out.add(map[id]!);
        } else {
          out.add(val);
        }
        return;
      }
      
      if (val is int || val is num) {
        final id = val.toInt();
        out.add(map[id] ?? '$prefix #$id');
        return;
      }

      if (val is Map) {
        final name = val['name']?.toString().trim();
        if (name != null && name.isNotEmpty) out.add(name);
      }
    }

    if (raw is List) {
      for (final item in raw) add(item);
    } else {
      add(raw);
    }

    return out.toSet().toList();
  }

  // ----------------------------
  // Public API
  // ----------------------------

  static Future<List<Map<String, dynamic>>> ensureRecipesLoaded({
    bool backgroundRefresh = true,
    bool forceRefresh = false,
  }) async {
    final cached = await RecipeCache.load();

    if (cached.isNotEmpty) {
      if (backgroundRefresh) {
        unawaited(_refreshIfStale(cachedLength: cached.length, force: forceRefresh));
        return cached;
      } else {
        await _refreshIfStale(cachedLength: cached.length, force: forceRefresh);
        final updated = await RecipeCache.load();
        return updated.isNotEmpty ? updated : cached;
      }
    }

    try {
      final fresh = await fetchAllRecipesFromWp();
      if (fresh.isNotEmpty) {
        await RecipeCache.save(fresh);
        final latest = _latestModifiedFromList(fresh);
        if (latest != null) await _writeLatestModified(latest);
        await _writeLastCheckedAt(DateTime.now());
      }
      return fresh;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _refreshIfStale({required int cachedLength, bool force = false}) async {
    if (_refreshInFlight != null) return _refreshInFlight!;

    _refreshInFlight = () async {
      try {
        if (!force) {
          final lastChecked = await _readLastCheckedAt();
          if (lastChecked != null && DateTime.now().difference(lastChecked) < _minCheckInterval) return;
        }

        final signal = await _fetchStalenessSignal();
        if (signal == null) return;

        final cachedLatest = await _readLatestModified();
        final countChanged = (signal.total != null && signal.total != cachedLength);
        final modifiedChanged = (signal.latestModified != null && signal.latestModified != cachedLatest);
        final needBaseline = (cachedLatest == null && signal.latestModified != null);

        if (force || countChanged || modifiedChanged || needBaseline) {
          final fresh = await fetchAllRecipesFromWp();
          if (fresh.isNotEmpty) {
            await RecipeCache.save(fresh);
            final latest = _latestModifiedFromList(fresh) ?? signal.latestModified;
            if (latest != null) await _writeLatestModified(latest);
          }
        } else {
           if (cachedLatest == null && signal.latestModified != null) {
             await _writeLatestModified(signal.latestModified!);
           }
        }
        await _writeLastCheckedAt(DateTime.now());
      } catch (_) {} finally {
        _refreshInFlight = null;
      }
    }();
    return _refreshInFlight!;
  }

  // ✅ Added missing method
  static Future<_StalenessSignal?> _fetchStalenessSignal() async {
    try {
      final res = await _dio.get(
        'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe',
        queryParameters: {
          'per_page': 1,
          'page': 1,
          'orderby': 'modified',
          'order': 'desc',
          '_fields': 'id,modified',
        },
      );

      final totalStr = res.headers.value('x-wp-total');
      final total = int.tryParse(totalStr ?? '');

      String? latestModified;
      final data = res.data;
      if (data is List && data.isNotEmpty && data.first is Map) {
        final m = (data.first as Map)['modified'];
        if (m is String && m.trim().isNotEmpty) {
          latestModified = m.trim();
        }
      }

      if (total == null && latestModified == null) return null;
      return _StalenessSignal(total: total, latestModified: latestModified);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAllRecipesFromWp() async {
    final out = <Map<String, dynamic>>[];
    int page = 1;
    int? totalPages;

    while (true) {
      try {
        final res = await _dio.get(
          'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe',
          queryParameters: {'per_page': _perPage, 'page': page},
        );

        totalPages ??= int.tryParse(res.headers.value('x-wp-totalpages') ?? '');
        final data = res.data;
        if (data is! List) break;

        for (final item in data) {
          if (item is Map) out.add(Map<String, dynamic>.from(item));
        }

        if (totalPages != null) {
          if (page >= totalPages) break;
        } else {
          if (data.length < _perPage) break;
        }
        page++;
      } on DioException catch (e) {
        if (e.response?.statusCode == 400) break;
        rethrow;
      }
    }

    if (out.isNotEmpty) await _normalizeWprmTaxonomyFields(out);
    return out;
  }

  static Future<Map<String, dynamic>> fetchRecipeById(int wprmId) async {
    final res = await _dio.get(
      'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe/$wprmId',
    );

    final data = res.data;
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      try {
        await _normalizeWprmTaxonomyFields([m]);
      } catch (_) {}
      return m;
    }
    throw Exception('Unexpected recipe payload for id=$wprmId');
  }

  static Future<Map<String, dynamic>> getRecipeById(
    int wprmId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await RecipeCache.loadRecipe(wprmId);
      if (cached != null) return cached;
    }

    final fresh = await fetchRecipeById(wprmId);
    await RecipeCache.saveRecipe(wprmId, fresh);
    return fresh;
  }

  static String? _latestModifiedFromList(List<Map<String, dynamic>> list) {
    String? maxIso;
    for (final r in list) {
      final m = r['modified'];
      if (m is String && m.isNotEmpty) {
        if (maxIso == null || m.compareTo(maxIso) > 0) maxIso = m;
      }
    }
    return maxIso;
  }

  static Future<Box<dynamic>> _metaBox() async {
    if (!Hive.isBoxOpen(_boxName)) return await Hive.openBox<dynamic>(_boxName);
    return Hive.box<dynamic>(_boxName);
  }

  static Future<void> _writeLastCheckedAt(DateTime dt) async {
    final box = await _metaBox();
    await box.put(_keyLastCheckedAtMs, dt.millisecondsSinceEpoch);
  }

  static Future<DateTime?> _readLastCheckedAt() async {
    final box = await _metaBox();
    final v = box.get(_keyLastCheckedAtMs);
    return (v is int) ? DateTime.fromMillisecondsSinceEpoch(v) : null;
  }

  static Future<void> _writeLatestModified(String iso) async {
    final box = await _metaBox();
    await box.put(_keyLatestModified, iso);
  }

  static Future<String?> _readLatestModified() async {
    final box = await _metaBox();
    return box.get(_keyLatestModified) as String?;
  }
}

class _StalenessSignal {
  final int? total;
  final String? latestModified;
  _StalenessSignal({required this.total, required this.latestModified});
}
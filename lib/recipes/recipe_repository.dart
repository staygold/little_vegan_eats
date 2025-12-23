import 'dart:async';
import 'package:dio/dio.dart';
import 'recipe_cache.dart';

class RecipeRepository {
  RecipeRepository._();

  static final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'LittleVeganEatsApp/1.0',
      },
      connectTimeout: Duration(seconds: 15),
      receiveTimeout: Duration(seconds: 30),
    ),
  );

  static const int _perPage = 50;

  /// Loads cached recipes instantly.
  /// If cache exists but appears stale (WP total != cached length), refreshes.
  /// Also supports background refresh to avoid blocking boot.
  static Future<List<Map<String, dynamic>>> ensureRecipesLoaded({
    bool backgroundRefresh = true,
  }) async {
    final cached = await RecipeCache.load();
    if (cached.isNotEmpty) {
      if (backgroundRefresh) {
        // Don’t block app boot – refresh quietly.
        unawaited(_refreshIfStale(cachedLength: cached.length));
        return cached;
      } else {
        await _refreshIfStale(cachedLength: cached.length);
        final updated = await RecipeCache.load();
        return updated.isNotEmpty ? updated : cached;
      }
    }

    // Cache empty -> fetch everything
    final fresh = await fetchAllRecipesFromWp();
    if (fresh.isNotEmpty) {
      await RecipeCache.save(fresh);
    }
    return fresh;
  }

  static Future<void> _refreshIfStale({required int cachedLength}) async {
    try {
      // Fetch 1 item just to read WP totals from headers
      final res = await _dio.get(
        'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe',
        queryParameters: {
          'per_page': 1,
          'page': 1,
          // If your endpoint supports it, this reduces payload:
          // '_fields': 'id,title,slug,date,modified',
        },
      );

      final totalStr = res.headers.value('x-wp-total');
      final total = int.tryParse(totalStr ?? '');

      // If we can’t read totals, don’t nuke cache.
      if (total == null) return;

      if (total != cachedLength) {
        // Cache likely stale or previously incomplete.
        final fresh = await fetchAllRecipesFromWp();
        if (fresh.isNotEmpty) {
          await RecipeCache.save(fresh);
        }
      }
    } catch (_) {
      // Network error: keep cache.
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
          queryParameters: {
            'per_page': _perPage,
            'page': page,
            // If supported by this endpoint, you can force published-only:
            // 'status': 'publish',
          },
        );

        totalPages ??= int.tryParse(res.headers.value('x-wp-totalpages') ?? '');

        final data = res.data;
        if (data is! List) break;

        for (final item in data) {
          if (item is Map) {
            out.add(Map<String, dynamic>.from(item));
          }
        }

        if (totalPages != null) {
          if (page >= totalPages) break;
        } else {
          // Fallback if headers missing:
          if (data.length < _perPage) break;
        }

        page += 1;
      } on DioException catch (e) {
        // WP returns 400 when page is out of range.
        final code = e.response?.statusCode;
        if (code == 400) break;
        rethrow;
      }
    }

    return out;
  }
}

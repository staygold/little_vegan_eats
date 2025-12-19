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
    ),
  );

  static const int _perPage = 50;

  /// Loads cached recipes instantly.
  /// If cache is empty, downloads ALL recipes from WP and caches them.
  static Future<List<Map<String, dynamic>>> ensureRecipesLoaded() async {
    // 1) Try cache first (instant)
    final cached = await RecipeCache.load();
    if (cached.isNotEmpty) return cached;

    // 2) Cache empty -> fetch everything
    final fresh = await fetchAllRecipesFromWp();

    // 3) Save for future instant loads
    if (fresh.isNotEmpty) {
      await RecipeCache.save(fresh);
    }

    return fresh;
  }

  static Future<List<Map<String, dynamic>>> fetchAllRecipesFromWp() async {
    final out = <Map<String, dynamic>>[];
    int page = 1;

    while (true) {
      final res = await _dio.get(
        'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe',
        queryParameters: {'per_page': _perPage, 'page': page},
      );

      final data = res.data;
      if (data is! List) break;

      final batch = data.cast<Map<String, dynamic>>();
      out.addAll(batch);

      if (batch.length < _perPage) break;
      page += 1;
    }

    return out;
  }
}

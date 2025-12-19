import 'dart:convert';
import 'package:http/http.dart' as http;

/// Simple WP REST fetcher for recipes.
/// Adjust the baseUrl and endpoint params to match your site.
class RecipeApi {
  // ✅ CHANGE THIS to your actual WP site domain
  static const String baseUrl = 'https://littleveganeats.co';

  /// Fetch all recipes (paginated).
  /// If your WP endpoint is different, change the path.
  static Future<List<Map<String, dynamic>>> fetchAllRecipes() async {
    final out = <Map<String, dynamic>>[];

    int page = 1;
    const int perPage = 100;

    while (true) {
      final uri = Uri.parse(
        '$baseUrl/wp-json/wp/v2/posts'
        '?categories=recipes' // ✅ if you use category slug filtering differently, remove/adjust
        '&per_page=$perPage'
        '&page=$page'
        '&_embed=1',
      );

      final res = await http.get(uri);

      if (res.statusCode == 400 || res.statusCode == 404) {
        // Usually means page out of range or endpoint mismatch
        break;
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Recipe fetch failed: ${res.statusCode} ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) break;

      final list = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      out.addAll(list);

      if (list.length < perPage) break;
      page++;
    }

    return out;
  }
}

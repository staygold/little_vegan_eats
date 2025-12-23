import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class RecipeCache {
  static const String _boxName = 'recipe_cache_box';
  static const String _keyRecipes = 'recipes_json';
  static const String _keyUpdatedAt = 'updated_at_ms';

  static Future<Box> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      debugPrint('[RecipeCache] opening box');
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  /// Save full recipe payload to cache
  static Future<void> save(List<Map<String, dynamic>> recipes) async {
    debugPrint('[RecipeCache] save ${recipes.length} recipes');
    final box = await _box();

    try {
      final encoded = jsonEncode(recipes);
      await box.put(_keyRecipes, encoded);
      await box.put(_keyUpdatedAt, DateTime.now().millisecondsSinceEpoch);
      debugPrint('[RecipeCache] save complete');
    } catch (e, st) {
      debugPrint('[RecipeCache] save ERROR $e');
      debugPrint('$st');
      rethrow;
    }
  }

  /// Load recipes from cache (instant)
  static Future<List<Map<String, dynamic>>> load() async {
    final box = await _box();
    final raw = box.get(_keyRecipes);

    debugPrint(
      '[RecipeCache] load rawType=${raw.runtimeType} '
      'size=${raw is String ? raw.length : 'n/a'}',
    );

    if (raw is! String || raw.isEmpty) {
      debugPrint('[RecipeCache] load → empty');
      return [];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        debugPrint('[RecipeCache] decoded is not List');
        return [];
      }

      final list = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      debugPrint('[RecipeCache] load → returning ${list.length}');
      return list;
    } catch (e, st) {
      debugPrint('[RecipeCache] load ERROR $e');
      debugPrint('$st');
      return [];
    }
  }

  /// Timestamp of last successful cache update
  static Future<DateTime?> lastUpdated() async {
    final box = await _box();
    final ms = box.get(_keyUpdatedAt);

    debugPrint('[RecipeCache] lastUpdated raw=$ms');

    if (ms is int) {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  /// Clear recipe cache completely
  static Future<void> clear() async {
    debugPrint('[RecipeCache] clear');
    final box = await _box();
    await box.delete(_keyRecipes);
    await box.delete(_keyUpdatedAt);
  }
}

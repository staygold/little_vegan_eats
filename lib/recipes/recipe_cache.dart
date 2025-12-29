import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class RecipeCache {
  static const String _boxName = 'recipe_cache_box';

  // List cache keys (existing)
  static const String _keyRecipes = 'recipes_json';
  static const String _keyUpdatedAt = 'updated_at_ms';

  // Per-recipe cache key helpers (new)
  static String _recipeKey(int wprmId) => 'recipe_$wprmId';
  static String _recipeUpdatedAtKey(int wprmId) => 'recipe_${wprmId}_updated_at_ms';

  static Future<Box> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      debugPrint('[RecipeCache] opening box');
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  // ---------------------------------------------------------------------------
  // LIST cache (unchanged)
  // ---------------------------------------------------------------------------

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

  /// Timestamp of last successful list cache update
  static Future<DateTime?> lastUpdated() async {
    final box = await _box();
    final ms = box.get(_keyUpdatedAt);

    debugPrint('[RecipeCache] lastUpdated raw=$ms');

    if (ms is int) {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // SINGLE recipe cache (new)
  // ---------------------------------------------------------------------------

  /// Save a single recipe payload (by WPRM ID).
  /// Stores JSON string for safety + an updated timestamp.
  static Future<void> saveRecipe(int wprmId, Map<String, dynamic> recipe) async {
    final box = await _box();
    try {
      final encoded = jsonEncode(recipe);
      await box.put(_recipeKey(wprmId), encoded);
      await box.put(
        _recipeUpdatedAtKey(wprmId),
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint('[RecipeCache] saveRecipe id=$wprmId');
    } catch (e, st) {
      debugPrint('[RecipeCache] saveRecipe ERROR id=$wprmId $e');
      debugPrint('$st');
      rethrow;
    }
  }

  /// Load a single recipe payload (by WPRM ID).
  /// Returns null if not present or decode fails.
  static Future<Map<String, dynamic>?> loadRecipe(int wprmId) async {
    final box = await _box();
    final raw = box.get(_recipeKey(wprmId));

    if (raw is! String || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (e, st) {
      debugPrint('[RecipeCache] loadRecipe ERROR id=$wprmId $e');
      debugPrint('$st');
      return null;
    }
  }

  /// Timestamp of last successful single recipe cache update
  static Future<DateTime?> recipeLastUpdated(int wprmId) async {
    final box = await _box();
    final ms = box.get(_recipeUpdatedAtKey(wprmId));
    if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
    return null;
  }

  /// Clear one single recipe cache entry
  static Future<void> clearRecipe(int wprmId) async {
    final box = await _box();
    await box.delete(_recipeKey(wprmId));
    await box.delete(_recipeUpdatedAtKey(wprmId));
    debugPrint('[RecipeCache] clearRecipe id=$wprmId');
  }

  // ---------------------------------------------------------------------------
  // Clear all
  // ---------------------------------------------------------------------------

  /// Clear recipe cache completely (list + per-recipe)
  static Future<void> clear() async {
    debugPrint('[RecipeCache] clear');
    final box = await _box();

    // remove list keys
    await box.delete(_keyRecipes);
    await box.delete(_keyUpdatedAt);

    // remove per-recipe keys (simple scan)
    final keys = box.keys.toList();
    for (final k in keys) {
      if (k is String &&
          (k.startsWith('recipe_') || k.startsWith('recipe_') && k.contains('_updated_at_ms'))) {
        await box.delete(k);
      }
    }
  }
}

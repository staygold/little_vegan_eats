import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class RecipeCache {
  static const String _boxName = 'recipe_cache_box';

  static const String _keyRecipes = 'recipes_json';
  static const String _keyUpdatedAt = 'updated_at_ms';

  static String _recipeKey(int wprmId) => 'recipe_$wprmId';
  static String _recipeUpdatedAtKey(int wprmId) => 'recipe_${wprmId}_updated_at_ms';

  static void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }

  static Future<Box> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      _log('[RecipeCache] opening box');
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  static Future<void> save(List<Map<String, dynamic>> recipes) async {
    _log('[RecipeCache] save ${recipes.length} recipes');
    final box = await _box();

    try {
      final encoded = jsonEncode(recipes);
      await box.put(_keyRecipes, encoded);
      await box.put(_keyUpdatedAt, DateTime.now().millisecondsSinceEpoch);
      _log('[RecipeCache] save complete');
    } catch (e, st) {
      _log('[RecipeCache] save ERROR $e');
      if (kDebugMode) _log('$st');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> load() async {
    final box = await _box();
    final raw = box.get(_keyRecipes);

    _log(
      '[RecipeCache] load rawType=${raw.runtimeType} '
      'size=${raw is String ? raw.length : 'n/a'}',
    );

    if (raw is! String || raw.isEmpty) {
      _log('[RecipeCache] load → empty');
      return [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _log('[RecipeCache] decoded is not List');
        return [];
      }

      final list = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      _log('[RecipeCache] load → returning ${list.length}');
      return list;
    } catch (e, st) {
      _log('[RecipeCache] load ERROR $e');
      if (kDebugMode) _log('$st');
      return [];
    }
  }

  static Future<DateTime?> lastUpdated() async {
    final box = await _box();
    final ms = box.get(_keyUpdatedAt);
    _log('[RecipeCache] lastUpdated raw=$ms');
    if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
    return null;
  }

  static Future<void> saveRecipe(int wprmId, Map<String, dynamic> recipe) async {
    final box = await _box();
    try {
      final encoded = jsonEncode(recipe);
      await box.put(_recipeKey(wprmId), encoded);
      await box.put(_recipeUpdatedAtKey(wprmId), DateTime.now().millisecondsSinceEpoch);
      _log('[RecipeCache] saveRecipe id=$wprmId');
    } catch (e, st) {
      _log('[RecipeCache] saveRecipe ERROR id=$wprmId $e');
      if (kDebugMode) _log('$st');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> loadRecipe(int wprmId) async {
    final box = await _box();
    final raw = box.get(_recipeKey(wprmId));
    if (raw is! String || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (e, st) {
      _log('[RecipeCache] loadRecipe ERROR id=$wprmId $e');
      if (kDebugMode) _log('$st');
      return null;
    }
  }

  static Future<DateTime?> recipeLastUpdated(int wprmId) async {
    final box = await _box();
    final ms = box.get(_recipeUpdatedAtKey(wprmId));
    if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
    return null;
  }

  static Future<void> clearRecipe(int wprmId) async {
    final box = await _box();
    await box.delete(_recipeKey(wprmId));
    await box.delete(_recipeUpdatedAtKey(wprmId));
    _log('[RecipeCache] clearRecipe id=$wprmId');
  }

  static Future<void> clear() async {
    _log('[RecipeCache] clear');
    final box = await _box();

    await box.delete(_keyRecipes);
    await box.delete(_keyUpdatedAt);

    final keys = box.keys.toList();
    for (final k in keys) {
      if (k is String && k.startsWith('recipe_')) {
        await box.delete(k);
      }
    }
  }
}

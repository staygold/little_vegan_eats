import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

class RecipeCache {
  static const String _boxName = 'recipe_cache_box';
  static const String _keyRecipes = 'recipes_json';
  static const String _keyUpdatedAt = 'updated_at_ms';

  static Future<Box> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  static Future<void> save(List<Map<String, dynamic>> recipes) async {
    final box = await _box();
    await box.put(_keyRecipes, jsonEncode(recipes));
    await box.put(_keyUpdatedAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Map<String, dynamic>>> load() async {
    final box = await _box();
    final raw = box.get(_keyRecipes);
    if (raw is! String || raw.isEmpty) return [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<DateTime?> lastUpdated() async {
    final box = await _box();
    final ms = box.get(_keyUpdatedAt);
    if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
    return null;
  }

  static Future<void> clear() async {
    final box = await _box();
    await box.delete(_keyRecipes);
    await box.delete(_keyUpdatedAt);
  }
}

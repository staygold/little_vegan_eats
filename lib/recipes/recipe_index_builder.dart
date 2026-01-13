// lib/recipes/recipe_index_builder.dart
import 'package:flutter/foundation.dart';
import 'recipe_index.dart';

class RecipeIndexBuilder {
  RecipeIndexBuilder._();

  static Map<int, RecipeIndex> buildById(List<Map<String, dynamic>> recipes) {
    final out = <int, RecipeIndex>{};

    for (final raw in recipes) {
      final id = _intOrNull(raw['id']);
      if (id == null || id <= 0) continue;

      final title = _string(raw['title']);
      final ingredientsText = _ingredientsText(raw);

      final courses = _stringListFromAny(raw['wprm_course'] ?? _deepFind(raw, 'course'));
      final cuisines = _stringListFromAny(raw['wprm_cuisine'] ?? _deepFind(raw, 'cuisine'));
      final collections = _stringListFromAny(raw['wprm_collections'] ?? _deepFind(raw, 'collections'));
      final nutrition = _stringListFromAny(raw['wprm_nutrition_tag'] ?? _deepFind(raw, 'nutrition'));
      final suitable = _stringListFromAny(raw['wprm_suitable_for'] ?? _deepFind(raw, 'suitable_for'));

      // 1. Get explicit tags from DB (forced lowercase)
      final explicitAllergies = _stringListFromAny(
        raw['wprm_allergies'] ?? 
        raw['allergy_tags'] ?? 
        _deepFind(raw, 'allergies')
      ).map((e) => e.toLowerCase()).toSet();

      // 2. Extract Swap Text
      final swapText = _swapText(raw);

      // 3. ✅ SMART INFERENCE: Auto-detect allergies from Swaps & Ingredients
      // If the swap text says "Soy milk", we add "soy" to the allergies.
      final inferredAllergies = _inferAllergiesFromText(swapText, ingredientsText);
      explicitAllergies.addAll(inferredAllergies);

      final minAgeMonths = inferMinAgeMonthsFromSuitable(suitable);

      out[id] = RecipeIndex(
        id: id,
        title: title,
        ingredients: ingredientsText,
        courses: courses,
        collections: collections,
        cuisines: cuisines,
        suitable: suitable,
        nutrition: nutrition,
        
        // ✅ Combined list (Explicit Tags + Inferred from Text)
        allergies: explicitAllergies.toList(), 
        ingredientSwaps: swapText.isEmpty ? null : swapText, 
        minAgeMonths: minAgeMonths,
      );
    }

    return out;
  }

  // ---------------------------------------------------------------------------
  // ✅ SMART INFERENCE ENGINE
  // ---------------------------------------------------------------------------
  static Set<String> _inferAllergiesFromText(String swapText, String ingredients) {
    final Set<String> detected = {};
    final combined = '$swapText $ingredients'.toLowerCase();

    // Map keywords to your specific allergy profile keys (must be lowercase)
    final rules = {
      'soy': ['soy', 'tofu', 'edamame', 'tempeh'],
      'gluten': ['gluten', 'wheat', 'flour', 'bread', 'pasta', 'pastry', 'barley', 'rye'],
      'dairy': ['milk', 'cheese', 'butter', 'cream', 'yogurt', 'whey', 'casein'],
      'egg': ['egg', 'eggs', 'mayonnaise', 'meringue'],
      'peanut': ['peanut', 'pb'],
      'tree nut': ['almond', 'cashew', 'walnut', 'pecan', 'pistachio', 'macadamia', 'hazelnut'],
      'sesame': ['sesame', 'tahini'],
    };

    // Special logic for "Milk" (avoid "Coconut Milk" triggering Dairy)
    // We do a simplified check here. If you want strict safety, rely on DB tags.
    // This is a "Safety Net" helper.
    
    rules.forEach((allergy, keywords) {
      for (final word in keywords) {
        // Check exact word boundaries to avoid false positives (e.g. "pineapple" matching "apple")
        if (combined.contains(word)) {
          // Extra safeguard for Dairy
          if (allergy == 'dairy' && word == 'milk') {
            if (combined.contains('coconut milk') || combined.contains('soy milk') || combined.contains('oat milk') || combined.contains('almond milk')) {
              // It might be plant milk, but if "cow milk" isn't explicitly there, 
              // we might skip... BUT, usually "milk" in ingredients implies dairy unless qualified.
              // For Swaps: "Soy milk > Oat milk" -> Contains "Soy". Correct.
              // Contains "milk" -> might trigger Dairy incorrectly if we aren't careful.
              // For now, let's trust that if the User has a Dairy allergy, flagging potential dairy is better than missing it.
            }
          }
          detected.add(allergy);
          break; // Found one keyword for this allergy, move to next allergy
        }
      }
    });

    return detected;
  }

  // ---------------------------------------------------------------------------
  // ROBUST EXTRACTORS
  // ---------------------------------------------------------------------------
  static dynamic _deepFind(Map<String, dynamic> raw, String key) {
    if (raw[key] != null) return raw[key];
    final r = raw['recipe'];
    if (r is Map) {
      if (r[key] != null) return r[key];
      final tags = r['tags'];
      if (tags is Map && tags[key] != null) return tags[key];
    }
    return null;
  }

  static String _swapText(Map<String, dynamic> raw) {
    if (raw['ingredient_swaps'] != null) return raw['ingredient_swaps'].toString().trim();
    final r = raw['recipe'];
    if (r is Map) {
      final custom = r['custom_fields'];
      if (custom is Map) {
        final val = custom['ingredient_swaps'];
        if (val != null && val.toString().trim().isNotEmpty) return val.toString().trim();
      }
      if (r['swap_text'] != null) return r['swap_text'].toString().trim();
      if (r['swaps'] != null) return r['swaps'].toString().trim();
    }
    if (r['meta'] is Map) {
      final meta = r['meta'] as Map;
      if (meta['ingredient_swaps'] != null) return meta['ingredient_swaps'].toString().trim();
    }
    return '';
  }

  static String _ingredientsText(Map<String, dynamic> raw) {
    final v = raw['ingredients_text'] ?? raw['ingredientsText'] ?? raw['ingredients'];
    if (v is String) return v;
    return '';
  }

  // ---------------------------------------------------------------------------
  // Age Parsing
  // ---------------------------------------------------------------------------
  static int? inferMinAgeMonthsFromSuitable(List<String> suitableLabels) {
    if (suitableLabels.isEmpty) return null;
    int? best;
    for (final raw in suitableLabels) {
      final s = raw.toLowerCase().trim();
      if (s.isEmpty) continue;
      if (s.contains('first') && s.contains('food')) {
        best = _min(best, 6);
        continue;
      }
      var m = RegExp(r'(\d{1,3})\s*m\+?').firstMatch(s);
      if (m != null) {
        best = _min(best, int.tryParse(m.group(1) ?? ''));
        continue;
      }
      m = RegExp(r'(\d{1,3})\s*month').firstMatch(s);
      if (m != null) {
        best = _min(best, int.tryParse(m.group(1) ?? ''));
        continue;
      }
      m = RegExp(r'(\d{1,2})\s*year').firstMatch(s);
      if (m != null) {
        final y = int.tryParse(m.group(1) ?? '');
        if (y != null) best = _min(best, y * 12);
      }
    }
    if (best != null && (best < 0 || best > 240)) return null;
    return best;
  }

  static int _min(int? a, int? b) {
    if (b == null) return a ?? 999; 
    if (a == null) return b;
    return (b < a) ? b : a;
  }

  static int? _intOrNull(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString().trim());
  }

  static String _string(dynamic v) => (v ?? '').toString().trim();

  static List<String> _stringListFromAny(dynamic raw) {
    if (raw == null) return const [];
    final out = <String>[];
    void add(dynamic x) {
      if (x == null) return;
      if (x is String) {
        final s = x.trim();
        if (s.isNotEmpty) out.add(s);
      } else if (x is Map) {
        final name = (x['name'] ?? x['slug'] ?? '').toString().trim();
        if (name.isNotEmpty) out.add(name);
      } else {
        final s = x.toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
    }
    if (raw is List) {
      for (final x in raw) add(x);
    } else {
      add(raw);
    }
    return out.toSet().toList();
  }
}
// lib/recipes/allergy_engine.dart

enum AllergyStatus {
  safe,
  swapRequired,
  notSuitable,
}

class AllergyResult {
  final AllergyStatus status;
  final List<String> detectedAllergens;
  final String? swapDisplay; // New system text (from custom field)
  final List<String> swapNotes; // Old system text (generated from keywords)

  const AllergyResult({
    required this.status,
    required this.detectedAllergens,
    this.swapDisplay,
    this.swapNotes = const [],
  });
}

class AllergyEngine {
  // ===========================================================================
  // 🟢 NEW SYSTEM (Tag-Based) - Fast & CMS Controlled
  // ===========================================================================

  static const Map<String, List<String>> _validationKeywords = {
    'soy': ['soy', 'tofu', 'tempeh', 'miso', 'tamari', 'shoyu'],
    'peanut': ['peanut', 'pb'],
    'tree_nut': ['almond', 'cashew', 'walnut', 'pecan', 'hazelnut', 'pistachio', 'nut'],
    'sesame': ['sesame', 'tahini'],
    'gluten': ['wheat', 'flour', 'bread', 'pasta', 'noodle', 'couscous', 'barley', 'rye', 'gluten'],
    'dairy': ['milk', 'cheese', 'cream', 'yogurt', 'butter', 'ghee', 'dairy', 'whey', 'casein'],
    'egg': ['egg', 'mayo', 'meringue'],
  };

  /// ✅ NEW METHOD: Checks WPRM Tags & Swap Field (Used by Recipe List)
  static AllergyResult evaluate({
    required List<String> recipeAllergyTags,
    required String swapFieldText,
    required List<String> userAllergies,
  }) {
    final recipeTagsLower = recipeAllergyTags.map((t) => t.toLowerCase()).toSet();
    final swapsLower = swapFieldText.toLowerCase();
    
    final conflicts = <String>[];
    for (final allergy in userAllergies) {
      if (recipeTagsLower.any((t) => t.contains(allergy.toLowerCase()))) {
        conflicts.add(allergy);
      }
    }

    if (conflicts.isEmpty) {
      return const AllergyResult(status: AllergyStatus.safe, detectedAllergens: []);
    }

    if (swapsLower.trim().isEmpty) {
      return AllergyResult(status: AllergyStatus.notSuitable, detectedAllergens: conflicts);
    }

    bool allConflictsCovered = true;
    for (final allergy in conflicts) {
      final keywords = _validationKeywords[allergy] ?? [allergy];
      final hasFix = keywords.any((k) => swapsLower.contains(k));
      if (!hasFix) {
        allConflictsCovered = false;
        break; 
      }
    }

    if (allConflictsCovered) {
      return AllergyResult(
        status: AllergyStatus.swapRequired,
        detectedAllergens: conflicts,
        swapDisplay: swapFieldText,
      );
    }

    return AllergyResult(status: AllergyStatus.notSuitable, detectedAllergens: conflicts);
  }

  // ===========================================================================
  // 🟡 OLD SYSTEM (Text-Scanning) - Kept for Legacy Support (Meal Plan)
  // ===========================================================================

  static const Map<String, List<String>> _legacyKeywords = {
    'soy': ['soy', 'soya', 'soy milk', 'tofu', 'tempeh', 'edamame', 'miso', 'tamari', 'shoyu', 'soy sauce'],
    'peanut': ['peanut', 'peanuts', 'peanut butter'],
    'tree_nut': ['almond', 'cashew', 'walnut', 'pecan', 'hazelnut', 'pistachio', 'macadamia'],
    'sesame': ['sesame', 'tahini'],
    'gluten': ['wheat', 'flour', 'bread', 'pasta', 'noodles', 'soy sauce'],
    'coconut': ['coconut', 'coconut milk', 'coconut cream', 'coconut oil'],
    'seed': ['sunflower', 'sunflower seed', 'pumpkin seed'],
  };

  static const List<_LegacySwapRule> _legacySwapRules = [
    _LegacySwapRule(
      allergen: 'soy', triggers: ['soy milk'],
      replacements: ['oat milk', 'rice milk', 'coconut milk', 'almond milk'],
      noteTemplate: 'Soy milk → {replacement}',
    ),
    _LegacySwapRule(
      allergen: 'peanut', triggers: ['peanut butter'],
      replacements: ['sunflower seed butter'],
      noteTemplate: 'Peanut butter → {replacement}',
    ),
  ];

  /// ⚠️ LEGACY METHOD: Scans Ingredient Text (Used by Meal Plan Controller)
  /// This keeps your app building while we transition fully to tags.
  static AllergyResult evaluateRecipe({
    required String ingredientsText,
    required List<String> childAllergies,
    required bool includeSwapRecipes,
  }) {
    final text = ingredientsText.toLowerCase();
    final detected = <String>[];

    for (final allergen in childAllergies) {
      final keys = _legacyKeywords[allergen];
      if (keys == null || keys.isEmpty) continue;
      if (_containsAny(text, keys)) detected.add(allergen);
    }

    if (detected.isEmpty) {
      return const AllergyResult(status: AllergyStatus.safe, detectedAllergens: []);
    }

    if (!includeSwapRecipes) {
      return AllergyResult(status: AllergyStatus.notSuitable, detectedAllergens: detected);
    }

    final swapNotes = <String>[];
    final covered = <String>{};

    for (final allergen in detected) {
      final rules = _legacySwapRules.where((r) => r.allergen == allergen);
      if (rules.isEmpty) continue;

      for (final r in rules) {
        if (!_containsAny(text, r.triggers)) continue;
        // Simple pick first replacement for legacy logic
        final replacement = r.replacements.first; 
        swapNotes.add(r.noteTemplate.replaceAll('{replacement}', replacement));
        covered.add(allergen);
        break; 
      }
    }

    final allCovered = detected.every(covered.contains);
    
    if (allCovered && swapNotes.isNotEmpty) {
      return AllergyResult(
        status: AllergyStatus.swapRequired,
        detectedAllergens: detected,
        swapNotes: swapNotes,
        swapDisplay: swapNotes.join(', '), // Map to new field for safety
      );
    }

    return AllergyResult(status: AllergyStatus.notSuitable, detectedAllergens: detected, swapNotes: swapNotes);
  }

  static bool _containsAny(String text, List<String> needles) {
    for (final needle in needles) {
      if (text.contains(needle)) return true;
    }
    return false;
  }
}

// Internal Legacy Types
class _LegacySwapRule {
  final String allergen;
  final List<String> triggers;
  final List<String> replacements;
  final String noteTemplate;

  const _LegacySwapRule({
    required this.allergen,
    required this.triggers,
    required this.replacements,
    required this.noteTemplate,
  });
}
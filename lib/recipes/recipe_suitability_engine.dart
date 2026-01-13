// lib/recipes/recipe_suitability_engine.dart
import 'allergy_engine.dart';
import 'profile_person.dart';
import 'recipe_index.dart';

enum RecipeSuitability {
  allowed,
  allowedWithSwaps,
  blocked,
}

class RecipeSuitabilityResult {
  final RecipeSuitability suitability;
  final String? reason;

  const RecipeSuitabilityResult({
    required this.suitability,
    this.reason,
  });
}

class RecipeSuitabilityEngine {
  /// ✅ THE ONE ENGINE
  ///
  /// Rules:
  /// - No allergies in people → allowed
  /// - Allergy tag + no swap text → BLOCKED
  /// - Allergy tag + swap text → allowedWithSwaps (if enabled by caller)
  static RecipeSuitabilityResult evaluate({
    required RecipeIndex recipe,
    required List<ProfilePerson> people,
    bool allowSwaps = true,
  }) {
    // Collect all allergies across selected people
    final userAllergies = <String>{};
    for (final p in people) {
      if (p.hasAllergies && p.allergies.isNotEmpty) {
        userAllergies.addAll(p.allergies);
      }
    }

    // No allergies → always allowed
    if (userAllergies.isEmpty) {
      return const RecipeSuitabilityResult(
        suitability: RecipeSuitability.allowed,
      );
    }

    // No allergy tags on recipe → cannot verify → block (v1 strict)
    if (recipe.allergyTags.isEmpty) {
      return const RecipeSuitabilityResult(
        suitability: RecipeSuitability.blocked,
        reason: 'Recipe has no allergy tags',
      );
    }

    final res = AllergyEngine.evaluate(
      recipeAllergyTags: recipe.allergyTags,
      swapFieldText: recipe.swapText,
      userAllergies: userAllergies.toList(),
    );

    switch (res.status) {
      case AllergyStatus.safe:
        return const RecipeSuitabilityResult(
          suitability: RecipeSuitability.allowed,
        );

      case AllergyStatus.swapRequired:
        if (allowSwaps) {
          return const RecipeSuitabilityResult(
            suitability: RecipeSuitability.allowedWithSwaps,
          );
        }
        return const RecipeSuitabilityResult(
          suitability: RecipeSuitability.blocked,
          reason: 'Swap required but swaps not allowed',
        );

      case AllergyStatus.notSuitable:
        return const RecipeSuitabilityResult(
          suitability: RecipeSuitability.blocked,
          reason: 'Contains allergen',
        );

      // ✅ ADD THIS CASE
      case AllergyStatus.unknown:
        return const RecipeSuitabilityResult(
          suitability: RecipeSuitability.blocked,
          reason: 'Safety could not be determined',
        );
    }
  }
}

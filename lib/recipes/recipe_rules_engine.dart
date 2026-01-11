// lib/recipes/recipe_rules_engine.dart
import 'allergy_engine.dart';
import 'allergy_keys.dart';
import 'profile_person.dart';
import 'recipe_index.dart';

class RecipeRulesEngine {
  static bool isAllowedForPerson({
    required ProfilePerson p,
    required RecipeIndex ix,
    required AllergiesSelection selection,
  }) {
    if (!p.hasAllergies || p.allergies.isEmpty) return true;

    final res = AllergyEngine.evaluate(
      recipeAllergyTags: ix.allergyTags,
      swapFieldText: ix.swapText,
      userAllergies: p.allergies,
    );

    if (res.status == AllergyStatus.safe) return true;
    if (selection.includeSwaps && res.status == AllergyStatus.swapRequired) return true;
    return false;
  }

  static ({String? tag, String? swapHint}) tagForRecipe({
    required RecipeIndex ix,
    required List<ProfilePerson> activeProfiles,
    required AllergiesSelection selection,
  }) {
    final anyActive =
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);
    if (!anyActive) return (tag: null, swapHint: null);

    bool anySwap = false;
    bool anyNotSuitable = false;

    for (final p in activeProfiles) {
      if (!p.hasAllergies || p.allergies.isEmpty) continue;

      final res = AllergyEngine.evaluate(
        recipeAllergyTags: ix.allergyTags,
        swapFieldText: ix.swapText,
        userAllergies: p.allergies,
      );

      if (res.status == AllergyStatus.notSuitable) anyNotSuitable = true;
      if (res.status == AllergyStatus.swapRequired) anySwap = true;
    }

    if (anyNotSuitable) return (tag: '⛔ Not suitable', swapHint: null);

    if (anySwap) {
      final label = activeProfiles.length > 1
          ? '⚠️ Swap required (one or more)'
          : '⚠️ Swap required';
      return (tag: label, swapHint: null);
    }

    if (selection.mode == SuitabilityMode.specificPeople) {
      if (activeProfiles.length == 1) {
        return (tag: '✅ Safe for ${activeProfiles.first.name}', swapHint: null);
      }
      return (tag: '✅ Safe for ${activeProfiles.length} selected', swapHint: null);
    }

    if (selection.mode == SuitabilityMode.allChildren) {
      return (tag: '✅ Safe for all children', swapHint: null);
    }

    return (tag: '✅ Safe for whole family', swapHint: null);
  }

  static String activeAllergiesLabelFor(List<ProfilePerson> people) {
    final set = <String>{};
    for (final p in people) {
      if (p.hasAllergies && p.allergies.isNotEmpty) set.addAll(p.allergies);
    }
    final list = set.toList()..sort();
    return list.map(AllergyKeys.label).join(', ');
  }
}

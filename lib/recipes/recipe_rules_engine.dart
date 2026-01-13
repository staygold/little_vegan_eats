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

    // ✅ add these
    required int? youngestChildMonths,
    required String? youngestChildName,
  }) {
    final parts = <String>[];

    // -------------------------
    // 1) AGE TAG (youngest child)
    // -------------------------
    final minAge = ix.minAgeMonths;
    if (youngestChildMonths != null && youngestChildMonths > 0) {
      final name = (youngestChildName?.trim().isNotEmpty == true)
          ? youngestChildName!.trim()
          : 'your youngest';

      if (minAge != null && minAge > youngestChildMonths) {
        parts.add('Not suitable for $name (${youngestChildMonths}m)');
      } else if (minAge != null) {
        // If it passes age gate, we don't need to scream it — but for now, show it.
        parts.add('✅ Suitable for $name');
      } else {
        // No min age info in tags
        parts.add('⚠️ Check for $name');
      }
    }

    // -------------------------
    // 2) ALLERGY TAG (existing)
    // -------------------------
    final anyActive =
        activeProfiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);

    if (anyActive) {
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

      if (anyNotSuitable) {
        parts.add('Allergy: Not suitable');
      } else if (anySwap) {
        final label = activeProfiles.length > 1
            ? '⚠️ Allergy: Swap required'
            : '⚠️ Allergy: Swap required';
        parts.add(label);
      } else {
        // Only show "safe" if you're currently showing "safe" labels everywhere
        if (selection.mode == SuitabilityMode.specificPeople) {
          if (activeProfiles.length == 1) {
            parts.add('✅ Allergy: Safe for ${activeProfiles.first.name}');
          } else {
            parts.add('✅ Allergy: Safe for ${activeProfiles.length} selected');
          }
        } else if (selection.mode == SuitabilityMode.allChildren) {
          parts.add('✅ Allergy: Safe for all children');
        } else {
          parts.add('✅ Allergy: Safe for whole family');
        }
      }
    }

    if (parts.isEmpty) return (tag: null, swapHint: null);

    // For now return one string; later we can return two pills cleanly.
    return (tag: parts.join(' • '), swapHint: null);
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

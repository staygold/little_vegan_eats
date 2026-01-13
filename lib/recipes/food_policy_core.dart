// lib/recipes/food_policy_core.dart
import 'profile_person.dart';
import 'recipe_index.dart';
import 'allergy_engine.dart'; 

class FoodPolicyCore {
  
  // ... (Keep isAllowedForProfiles exactly as it is) ...
  static bool isAllowedForProfiles({
    required RecipeIndex ix,
    required List<ProfilePerson> profiles,
    required AllergiesSelection selection,
  }) {
    if (!selection.enabled) return true;

    final blockedAllergies = <String>{};
    
    if (selection.mode == SuitabilityMode.specificPeople) {
      for (final p in profiles) {
        if (selection.personIds.contains(p.id) && p.hasAllergies) {
          blockedAllergies.addAll(p.allergies.map((e) => e.toLowerCase()));
        }
      }
    } else {
      for (final p in profiles) {
        if (p.hasAllergies) {
          blockedAllergies.addAll(p.allergies.map((e) => e.toLowerCase()));
        }
      }
    }

    if (blockedAllergies.isEmpty) return true;

    final conflicts = <String>{};
    for (final allergen in ix.allergies) {
      if (blockedAllergies.contains(allergen)) {
        conflicts.add(allergen);
      }
    }

    if (conflicts.isEmpty) return true;

    if (!selection.includeSwaps) return false; 

    final hasSwaps = ix.ingredientSwaps != null && ix.ingredientSwaps!.trim().isNotEmpty;
    
    return hasSwaps; 
  }

  // ... (Rest of file) ...

  /// ✅ SIMPLIFIED LABEL GENERATOR
  static ({String? tag, String? swapHint}) allergyTagForRecipe({
    required RecipeIndex ix,
    required List<ProfilePerson> activeProfiles,
    required AllergiesSelection selection,
  }) {
    if (!selection.enabled) return (tag: null, swapHint: null);

    final blockedAllergies = <String>{};
    for (final p in activeProfiles) {
      if (p.hasAllergies) {
        blockedAllergies.addAll(p.allergies.map((e) => e.toLowerCase()));
      }
    }

    if (blockedAllergies.isEmpty) return (tag: null, swapHint: null);

    final conflicts = <String>{};
    for (final allergen in ix.allergies) {
      if (blockedAllergies.contains(allergen)) {
        conflicts.add(allergen);
      }
    }

    // 1. Safe
    if (conflicts.isEmpty) {
      return (tag: 'Safe for whole family', swapHint: null);
    }

    // 2. Needs Swap (Generic)
    if (selection.includeSwaps) {
      final hasSwaps = ix.ingredientSwaps != null && ix.ingredientSwaps!.trim().isNotEmpty;
      if (hasSwaps) {
        // ✅ User requested simple label
        return (tag: 'Needs swap', swapHint: ix.ingredientSwaps);
      }
    }

    // 3. Blocked
    final conflictStr = conflicts.join(', ');
    return (tag: 'Contains $conflictStr', swapHint: null);
  }

  // ... (Keep babySuitabilityLabel and activeAllergiesLabelFor as is) ...
  static String? babySuitabilityLabel({
    required RecipeIndex ix,
    required dynamic youngestChild,
    required int? youngestMonths,
  }) {
    if (youngestChild == null || youngestMonths == null) return null;
    
    final minAge = ix.minAgeMonths;
    String name = 'baby';
    if (youngestChild is ProfilePerson) {
      name = youngestChild.name;
    } else if (youngestChild is Map) {
      name = (youngestChild['name'] ?? 'baby').toString();
    }

    if (minAge == null || minAge <= 0) {
        return 'Check suitability for $name (no age tag)';
    }

    if (minAge > youngestMonths) {
      return 'Not suitable for $name yet';
    }
    
    return null; 
  }
  
  static String activeAllergiesLabelFor(List<ProfilePerson> people) {
    final set = <String>{};
    for (final p in people) {
      if (p.hasAllergies) set.addAll(p.allergies);
    }
    if (set.isEmpty) return '';
    final list = set.toList()..sort();
    return list.join(', ');
  }
}
// lib/recipes/household_food_policy.dart

import 'package:flutter/foundation.dart';
import '../utils/text.dart'; // Needed for stripHtml if used, or standard string manip
import 'allergy_engine.dart';
import 'family_profile.dart';
import 'family_profile_repository.dart';
import 'profile_person.dart'; // ✅ FIXED: Added missing import
import 'recipe_index.dart';
import 'widgets/recipe_filters_ui.dart';

// ✅ MATCHING CLASS NAME: Matches what RecipeListScreen expects
class FilterResult {
  final List<Map<String, dynamic>> visible;
  final int totalMatches;

  FilterResult({required this.visible, required this.totalMatches});
}

class HouseholdFoodPolicy {
  final FamilyProfileRepository familyRepo;

  HouseholdFoodPolicy({required this.familyRepo});

  // --- AGE HELPERS (Restored from your old code) ---
  DateTime _getBirthDate(ProfilePerson p) {
    if (p.dob != null) return p.dob!;
    if (p.dobYear != null) return DateTime(p.dobYear!, p.dobMonth ?? 1, 1);
    return DateTime.now().subtract(const Duration(days: 365 * 30));
  }

  int _parseMinMonths(List<String> tags) {
    int minMonths = 0; 
    for (final t in tags) {
      final lower = t.toLowerCase().trim();
      if (lower.contains('12m') || lower.contains('12 m') || lower.contains('1 year') || lower.contains('toddler')) {
        if (12 > minMonths) minMonths = 12;
      } else if (lower.contains('9m') || lower.contains('9 m')) {
        if (9 > minMonths) minMonths = 9;
      } else if (lower.contains('6m') || lower.contains('6 m')) {
        if (6 > minMonths) minMonths = 6;
      }
    }
    return minMonths;
  }

  /// --------------------------------------------------------------------------
  /// MAIN FILTER PIPELINE
  /// --------------------------------------------------------------------------
  FilterResult filterRecipes({
    required List<Map<String, dynamic>> items,
    required Map<int, RecipeIndex> indexById,
    required RecipeFilterSelection filters,
    required String query,
    required FamilyProfile family,
    required AllergiesSelection selection,
  }) {
    final q = query.toLowerCase().trim();
    final visible = <Map<String, dynamic>>[];

    // 1. Identify Active People
    List<ProfilePerson> peopleToCheck = [];
    if (selection.enabled) {
      peopleToCheck = activeProfiles(family: family, selection: selection);
    }

    // 2. Pre-calculate "Safety Age" (Youngest Child Rule)
    int? safetyAgeMonths;
    if (selection.enabled && peopleToCheck.isNotEmpty) {
      int minAge = 999;
      bool foundChild = false;
      final now = DateTime.now();
      
      for (final p in peopleToCheck) {
        if (p.isChild) {
           final birthDate = _getBirthDate(p);
           final ageMonths = (now.difference(birthDate).inDays / 30).floor();
           if (ageMonths < minAge) minAge = ageMonths;
           foundChild = true;
        }
      }
      if (foundChild) safetyAgeMonths = minAge;
    }

    // 3. Iterate Items
    for (final item in items) {
      final id = item['id'];
      if (id is! int) continue;
      final ix = indexById[id];
      if (ix == null) continue;

      // --- SEARCH (Title OR Ingredients) ---
      if (q.isNotEmpty) {
        final title = (ix.title).toLowerCase();
        final ingredients = (ix.ingredients).toLowerCase();
        if (!title.contains(q) && !ingredients.contains(q)) continue;
      }

      // --- TAXONOMY FILTERS ---
      if (filters.course != 'All' && !ix.courses.contains(filters.course)) continue;
      if (filters.cuisine != 'All' && !ix.cuisines.contains(filters.cuisine)) continue;
      if (filters.suitableFor != 'All' && !ix.suitable.contains(filters.suitableFor)) continue;
      if (filters.nutritionTag != 'All' && !ix.nutrition.contains(filters.nutritionTag)) continue;
      if (filters.collection != 'All' && !ix.collections.contains(filters.collection)) continue;

      // --- SUITABILITY CHECKS ---
      if (selection.enabled) {
        
        // A. AGE CHECK (Strict Mode Only)
        if (safetyAgeMonths != null) {
          final recipeMinMonths = _parseMinMonths(ix.suitable);
          // Only filter out if "Strict Age" is checked.
          // Otherwise, we let it pass, and the UI Card shows a warning tag.
          if (selection.strictAge && recipeMinMonths > safetyAgeMonths) {
            continue; 
          }
        }

        // B. ALLERGY CHECK (The Fix)
        if (peopleToCheck.isNotEmpty) {
          final allergies = peopleToCheck.expand((p) => p.allergies).toList();
          
          if (allergies.isNotEmpty) {
             final result = AllergyEngine.evaluate(
               recipeAllergyTags: ix.allergies,
               // Use Index data if available, fallback to Map
               swapFieldText: ix.ingredientSwaps ?? (item['ingredient_swaps']?.toString() ?? ''), 
               userAllergies: allergies,
             );

             // 1. Hard Block (Red) - User cannot fix this.
             if (result.status == AllergyStatus.notSuitable) {
               if (selection.hideUnsafe) continue; 
             }
             
             // 2. Swap Required (Amber) - User CAN fix this.
             if (result.status == AllergyStatus.swapRequired) {
               // Only hide if the user explicitely turned OFF swaps
               if (!selection.includeSwaps) {
                 continue; 
               }
               // If includeSwaps is TRUE, we DO NOT continue. We let it add to visible.
             }
          }
        }
      }

      visible.add(item);
    }

    return FilterResult(visible: visible, totalMatches: visible.length);
  }

  /// --------------------------------------------------------------------------
  /// HELPERS
  /// --------------------------------------------------------------------------

  List<ProfilePerson> activeProfiles({
    required FamilyProfile family,
    required AllergiesSelection selection,
  }) {
    if (!selection.enabled) return [];
    switch (selection.mode) {
      case SuitabilityMode.wholeFamily:
        return family.allPeople;
      case SuitabilityMode.allChildren:
        return family.children;
      case SuitabilityMode.specificPeople:
        return family.allPeople
            .where((p) => selection.personIds.contains(p.id))
            .toList();
    }
  }
  
  String activeAllergiesLabel(List<ProfilePerson> people) {
    final Set<String> allergies = {};
    for(var p in people) allergies.addAll(p.allergies);
    if (allergies.isEmpty) return 'None';
    return allergies.join(', ');
  }

  bool hasAnyAllergies({required List<ProfilePerson> profiles, required AllergiesSelection selection}) {
    if (!selection.enabled) return false;
    for (final p in profiles) {
      if (p.allergies.isNotEmpty) return true;
    }
    return false;
  }
  
  ProfilePerson? youngestChild(FamilyProfile f) {
    if (f.children.isEmpty) return null;
    final sorted = List<ProfilePerson>.from(f.children);
    sorted.sort((a, b) => _getBirthDate(b).compareTo(_getBirthDate(a))); 
    return sorted.first;
  }
  
  int youngestChildAgeMonths(FamilyProfile f) {
    final y = youngestChild(f);
    if (y == null) return 999;
    return (DateTime.now().difference(_getBirthDate(y)).inDays / 30).floor(); 
  }


    // --------------------------------------------------------------------------
  // ✅ UI LABEL HELPERS (status text with names)
  // --------------------------------------------------------------------------

  String _formatNames(List<ProfilePerson> people) {
    final names = people
        .map((p) => (p.name ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();

    if (names.isEmpty) return 'your household';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    final last = names.last;
    final others = names.sublist(0, names.length - 1).join(', ');
    return '$others & $last';
  }

  /// Returns a UI-friendly status string for RecipeSuitabilityDisplay.
  /// Examples:
  /// - "Safe for Mike"
  /// - "Needs allergy swap (peanut)"
  /// - "Not suitable (peanut, sesame)"
  String? allergyStatusLabel({
    required RecipeIndex ix,
    required Map<String, dynamic> item,
    required FamilyProfile family,
    required AllergiesSelection selection,
  }) {
    if (!selection.enabled) return null;

    final people = activeProfiles(family: family, selection: selection);
    if (people.isEmpty) return null;

    final userAllergies = people.expand((p) => p.allergies).toList();
    if (userAllergies.isEmpty) return null;

    final result = AllergyEngine.evaluate(
      recipeAllergyTags: ix.allergies,
      swapFieldText: (ix.ingredientSwaps ?? (item['ingredient_swaps']?.toString() ?? '')),
      userAllergies: userAllergies,
    );

    final who = _formatNames(people);

    switch (result.status) {
      case AllergyStatus.safe:
        // ✅ this is what you asked for
        return 'Safe for $who';

      case AllergyStatus.swapRequired:
        if (!selection.includeSwaps) return null;
        final swaps = result.swapIngredients;
        if (swaps.isEmpty) return 'Needs allergy swap';
        return 'Needs allergy swap (${swaps.join(', ')})';

      case AllergyStatus.notSuitable:
        final blocking = result.blockingIngredients;
        if (blocking.isEmpty) return 'Not suitable';
        return 'Not suitable (${blocking.join(', ')})';

      case AllergyStatus.unknown:
        return 'Check allergy details';
    }
  }

}
// lib/recipes/household_food_policy.dart
import 'family_profile.dart';
import 'profile_person.dart';
import 'recipe_index.dart';
import 'recipe_rules_engine.dart';
import 'family_profile_repository.dart';

class HouseholdFoodPolicy {
  final FamilyProfileRepository familyRepo;

  HouseholdFoodPolicy({
    required this.familyRepo,
  });

  // ----------------------------
  // 1) Household source of truth
  // ----------------------------
  Stream<FamilyProfile> watchFamily() => familyRepo.watchFamilyProfile();

  // ----------------------------
  // 2) Active profiles helper
  // ----------------------------
  List<ProfilePerson> activeProfiles({
    required FamilyProfile family,
    required AllergiesSelection selection,
  }) {
    return family.activeProfilesFor(selection);
  }

  bool hasAnyAllergies({
    required List<ProfilePerson> profiles,
    required AllergiesSelection selection,
  }) {
    if (!selection.enabled) return false;
    return profiles.any((p) => p.hasAllergies && p.allergies.isNotEmpty);
  }

  // ----------------------------
  // 3) Core policy decisions
  // ----------------------------
  bool isRecipeAllowedForProfiles({
    required RecipeIndex ix,
    required List<ProfilePerson> profiles,
    required AllergiesSelection selection,
  }) {
    if (!selection.enabled) return true;

    for (final p in profiles) {
      if (!RecipeRulesEngine.isAllowedForPerson(
        p: p,
        ix: ix,
        selection: selection,
      )) {
        return false;
      }
    }
    return true;
  }

  ({String? tag, String? swapHint}) tagForRecipe({
    required RecipeIndex ix,
    required List<ProfilePerson> profiles,
    required AllergiesSelection selection,
  }) {
    if (!selection.enabled) return (tag: null, swapHint: null);

    return RecipeRulesEngine.tagForRecipe(
      ix: ix,
      activeProfiles: profiles,
      selection: selection,
    );
  }

  String activeAllergiesLabel(List<ProfilePerson> profiles) {
    return RecipeRulesEngine.activeAllergiesLabelFor(profiles);
  }

  // ------------------------------------------------
  // 4) Convenience: list filtering + tags in one go
  // ------------------------------------------------
  ({List<Map<String, dynamic>> visible, Map<int, ({String? tag, String? swapHint})> tags})
      filterRecipes({
    required List<Map<String, dynamic>> items,
    required Map<int, RecipeIndex> indexById,
    required RecipeFilterSelection filters,
    required String query,
    required FamilyProfile family,
    required AllergiesSelection selection,
  }) {
    final q = query.trim().toLowerCase();

    // caller can still short-circuit earlier if they want,
    // but doing it here is what gives you "one service".
    final profiles = activeProfiles(family: family, selection: selection);
    final needsAllergyEval = hasAnyAllergies(profiles: profiles, selection: selection);

    final out = <Map<String, dynamic>>[];
    final outTags = <int, ({String? tag, String? swapHint})>{};

    for (final r in items) {
      final id = r['id'];
      if (id is! int) continue;

      final ix = indexById[id];
      if (ix == null) continue;

      // NOTE: filtering by taxonomy is still based on ix fields you already built.
      // This keeps RecipeListScreen fast and unchanged architecturally.

      if (filters.course != 'All' && !ix.courses.contains(filters.course)) continue;
      if (filters.cuisine != 'All' && !ix.cuisines.contains(filters.cuisine)) continue;
      if (filters.suitableFor != 'All' && !ix.suitable.contains(filters.suitableFor)) continue;
      if (filters.nutritionTag != 'All' && !ix.nutrition.contains(filters.nutritionTag)) continue;
      if (filters.collection != 'All' && !ix.collections.contains(filters.collection)) continue;

      if (q.isNotEmpty && !ix.titleLower.contains(q) && !ix.ingredientsLower.contains(q)) {
        continue;
      }

      if (needsAllergyEval) {
        if (!isRecipeAllowedForProfiles(ix: ix, profiles: profiles, selection: selection)) {
          continue;
        }
        outTags[id] = tagForRecipe(ix: ix, profiles: profiles, selection: selection);
      }

      out.add(r);
    }

    return (visible: out, tags: outTags);
  }
}

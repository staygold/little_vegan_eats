// lib/recipes/recipe_index.dart

class RecipeIndex {
  final int id;
  
  // ✅ Searchable fields (Standardized names)
  final String title;
  final String ingredients; // Was 'ingredientsText'

  // ✅ Taxonomy
  final List<String> courses;
  final List<String> collections;
  final List<String> cuisines;
  final List<String> suitable;
  final List<String> nutrition;

  // ✅ Policy Fields (Standardized for new FoodPolicyCore)
  final List<String> allergies;       // Was 'allergyTags'
  final String? ingredientSwaps;      // Was 'swapText'
  final int? minAgeMonths;

  const RecipeIndex({
    required this.id,
    required this.title,
    required this.ingredients,
    required this.courses,
    required this.collections,
    required this.cuisines,
    required this.suitable,
    required this.nutrition,
    required this.allergies,
    required this.ingredientSwaps,
    this.minAgeMonths,
  });

  // ✅ Computed Getters for Search (HouseholdFoodPolicy uses these)
  String get titleLower => title.toLowerCase();
  String get ingredientsLower => ingredients.toLowerCase();
  
  // ✅ Alias Getters (Optional: Keeps old code working if you have other references)
  List<String> get allergyTags => allergies;
  String get swapText => ingredientSwaps ?? '';
}
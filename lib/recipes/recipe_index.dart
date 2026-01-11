// lib/recipes/recipe_index.dart

class RecipeIndex {
  final int id;
  final String titleLower;
  final String ingredientsText;
  final String ingredientsLower;
  final List<String> courses;
  final List<String> collections; // names
  final List<String> cuisines;
  final List<String> suitable;
  final List<String> nutrition;

  final List<String> allergyTags; // names (from WP tags)
  final String swapText;

  const RecipeIndex({
    required this.id,
    required this.titleLower,
    required this.ingredientsText,
    required this.ingredientsLower,
    required this.courses,
    required this.collections,
    required this.cuisines,
    required this.suitable,
    required this.nutrition,
    required this.allergyTags,
    required this.swapText,
  });
}

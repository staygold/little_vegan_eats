// lib/recipes/course_page.dart
import 'package:flutter/material.dart';

import 'recipe_list_screen.dart';

class CoursePage extends StatelessWidget {
  const CoursePage({
    super.key,
    required this.courseSlug,
    required this.title,
    required this.subtitle,
    this.recipes,
    this.favoriteIds,
  });

  final String courseSlug;
  final String title;
  final String subtitle;

  // Kept for backwards compatibility with any callers, but unused.
  // RecipeListScreen handles loading + favs + household now.
  final List<Map<String, dynamic>>? recipes;
  final Set<int>? favoriteIds;

  @override
  Widget build(BuildContext context) {
    return RecipeListScreen(
      initialCourseSlug: courseSlug,
      lockCourse: true,
      pageTitle: title,
    );
  }
}

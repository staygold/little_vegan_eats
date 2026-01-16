import 'package:flutter/material.dart';
import 'recipe_list_screen.dart';


class RecipeListPage extends StatelessWidget {
  const RecipeListPage({
    super.key,
    this.initialCourseSlug,
    this.lockCourse = false,
    this.titleOverride,
  });

  /// WPRM course term slug, e.g. "mains", "breakfast", "sauces-and-dips"
  final String? initialCourseSlug;

  /// If true, hide the course dropdown to make it feel like a dedicated page
  final bool lockCourse;

  /// Optional page title override (useful for Course pages)
  final String? titleOverride;

  @override
  Widget build(BuildContext context) {
    // ✅ SIMPLIFIED: Just let RecipeListScreen handle the "Page Mode"
    // by passing the pageTitle.
    return RecipeListScreen(
      initialCourseSlug: initialCourseSlug,
      lockCourse: lockCourse,
      pageTitle: titleOverride ?? 'ALL Recipes',
    );
  }
}
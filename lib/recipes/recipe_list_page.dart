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
    final title = (titleOverride != null && titleOverride!.trim().isNotEmpty)
        ? titleOverride!.trim()
        : 'Recipes';

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFECF3F4),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: RecipeListScreen(
        initialCourseSlug: initialCourseSlug,
        lockCourse: lockCourse,
      ),
    );
  }
}

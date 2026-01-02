import 'package:flutter/material.dart';

import 'recipe_list_screen.dart';

// ✅ reuse shared UI (same as Favourites / CoursePage)
import '../app/sub_header_bar.dart';

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
        : 'ALL Recipes';

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          // ✅ Same sub header bar as Favourites / Course pages
          SubHeaderBar(title: title),

          // ✅ Content
          Expanded(
            child: RecipeListScreen(
              initialCourseSlug: initialCourseSlug,
              lockCourse: lockCourse,
            ),
          ),
        ],
      ),
    );
  }
}

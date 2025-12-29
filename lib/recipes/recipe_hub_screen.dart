import 'package:flutter/material.dart';

import 'recipes_bootstrap_gate.dart';
import 'recipe_list_page.dart';
import 'favorites_screen.dart';
import 'course_page.dart';

class RecipeHubScreen extends StatelessWidget {
  const RecipeHubScreen({super.key});

  static const _courses = <_CourseLink>[
    _CourseLink(
      title: 'Breakfast',
      slug: 'breakfast',
      icon: Icons.wb_sunny_outlined,
      subtitle: 'Quick wins for busy mornings',
    ),
    _CourseLink(
      title: 'Drinks',
      slug: 'drinks',
      icon: Icons.local_cafe_outlined,
      subtitle: 'Smoothies, shakes, and more',
    ),
    _CourseLink(
      title: 'Mains',
      slug: 'mains',
      icon: Icons.restaurant_menu_outlined,
      subtitle: 'Family meals that actually land',
    ),
    _CourseLink(
      title: 'Sauces and Dips',
      slug: 'sauces-and-dips',
      icon: Icons.soup_kitchen_outlined,
      subtitle: 'Extras that make meals easy',
    ),
    _CourseLink(
      title: 'Snacks',
      slug: 'snacks',
      icon: Icons.cookie_outlined,
      subtitle: 'Lunchbox + between-meal favourites',
    ),
    _CourseLink(
      title: 'Staples',
      slug: 'staples',
      icon: Icons.kitchen_outlined,
      subtitle: 'Batch, basics, and everyday go-tos',
    ),
    _CourseLink(
      title: 'Sweets',
      slug: 'sweets',
      icon: Icons.icecream_outlined,
      subtitle: 'Treats without the chaos',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Recipes',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),

          // View all
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RecipesBootstrapGate(
                      child: RecipeListPage(),
                    ),
                  ),
                );
              },
              child: const Text('View all recipes'),
            ),
          ),

          const SizedBox(height: 12),

          // View favourites
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.star),
              label: const Text('View favourites'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RecipesBootstrapGate(
                      child: FavoritesScreen(),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          Text(
            'Browse by course',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),

          ..._courses.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CourseTile(
                title: c.title,
                subtitle: c.subtitle,
                icon: c.icon,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecipesBootstrapGate(
                        child: CoursePage(
                          courseSlug: c.slug,
                          title: c.title,
                          subtitle: c.subtitle,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseLink {
  const _CourseLink({
    required this.title,
    required this.slug,
    required this.icon,
    required this.subtitle,
  });

  final String title;
  final String slug;
  final IconData icon;
  final String subtitle;
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

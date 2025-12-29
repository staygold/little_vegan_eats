import 'package:flutter/material.dart';

import 'recipes_bootstrap_gate.dart';
import 'recipe_list_page.dart';
import 'favorites_screen.dart';
import '../recipes/favorites_service.dart';

class RecipeHubScreen extends StatelessWidget {
  const RecipeHubScreen({super.key});

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

          
        ],
      ),
    );
  }
}

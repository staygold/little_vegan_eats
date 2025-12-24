import 'package:flutter/material.dart';

import 'recipe_list_screen.dart';

class RecipeListPage extends StatelessWidget {
  const RecipeListPage({super.key});

  @override
  Widget build(BuildContext context) {
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
        title: const Text(
          'Recipes',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: const RecipeListScreen(),
    );
  }
}

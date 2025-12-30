import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../recipes/recipes_bootstrap_gate.dart';
import '../recipes/recipe_list_page.dart';

class TopHeaderBar extends StatelessWidget {
  const TopHeaderBar({super.key});

  void _openRecipeSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RecipesBootstrapGate(
          child: RecipeListPage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2F3).withOpacity(0.9),
      ),
      child: Row(
        children: [
          // Logo
          SvgPicture.asset(
            'assets/images/LVE.svg',
            height: 44,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => const SizedBox(
              height: 44,
              width: 44,
            ),
          ),

          const Spacer(),

          // Search pill
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _openRecipeSearch(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.06),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.search, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Search',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

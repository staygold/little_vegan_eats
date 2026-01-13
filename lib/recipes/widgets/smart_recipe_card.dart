import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'recipe_card.dart'; 
import 'recipe_suitability_display.dart'; 

class SmartRecipeCard extends StatelessWidget {
  const SmartRecipeCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.onTap,
    this.isFavorite = false,
    this.tags = const [],
    this.allergyStatus,
    this.ageWarning,
    this.childNames = const [],
    this.actions = const [],
  });

  final String title;
  final String? imageUrl;
  final VoidCallback? onTap;
  final bool isFavorite;
  final List<String> tags;
  final String? allergyStatus;
  final String? ageWarning;
  final List<String> childNames;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Widget? badge;
    if (isFavorite) {
      badge = Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.90),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
      );
    }

    Widget? trailing;
    if (actions.isNotEmpty) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: actions,
      );
    } else {
      trailing = const Icon(Icons.chevron_right, color: Colors.grey);
    }

    return RecipeCard(
      title: title,
      imageUrl: imageUrl,
      onTap: onTap,
      badge: badge,
      trailing: trailing,
      subtitleWidget: RecipeSuitabilityDisplay(
        tags: tags,
        allergyStatus: allergyStatus,
        ageWarning: ageWarning,
        childNames: childNames,
      ),
    );
  }
}
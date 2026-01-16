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

    /// ✅ Adults + kids (for “Safe for [name]” fallback)
    this.householdNames = const [],

    this.actions = const [],

    // ✅ meal plan highlight badge (LEFTOVER / BATCH / REPEAT)
    this.mealPlanBadge,
  });

  final String title;
  final String? imageUrl;
  final VoidCallback? onTap;
  final bool isFavorite;

  final List<String> tags;
  final String? allergyStatus;
  final String? ageWarning;

  final List<String> childNames;
  final List<String> householdNames;

  final List<Widget> actions;

  /// Expect values like: 'LEFTOVER', 'BATCH', 'REPEAT'
  final String? mealPlanBadge;

  @override
  Widget build(BuildContext context) {
    Widget? _buildFavoriteBadge() {
      if (!isFavorite) return null;
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.90),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
      );
    }

    Widget? _buildMealPlanBadge() {
      final b = (mealPlanBadge ?? '').trim().toUpperCase();
      if (b.isEmpty) return null;

      String text;
      IconData icon;

      switch (b) {
        case 'LEFTOVER':
          text = 'Reused';
          icon = Icons.replay_rounded;
          break;
        case 'BATCH':
          text = 'Batch';
          icon = Icons.kitchen_rounded;
          break;
        case 'REPEAT':
          text = 'Repeat';
          icon = Icons.repeat_rounded;
          break;
        default:
          return null;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.black87),
            const SizedBox(width: 6),
            Text(
              text,
              style: (Theme.of(context).textTheme.labelMedium ?? const TextStyle())
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    final fav = _buildFavoriteBadge();
    final mp = _buildMealPlanBadge();

    Widget? badge;
    if (fav != null && mp != null) {
      badge = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          mp,
          const SizedBox(height: 8),
          fav,
        ],
      );
    } else {
      badge = mp ?? fav;
    }

    

    return RecipeCard(
      title: title,
      imageUrl: imageUrl,
      onTap: onTap,
      badge: badge,
     
      subtitleWidget: RecipeSuitabilityDisplay(
        tags: tags,
        allergyStatus: allergyStatus,
        ageWarning: ageWarning,
        childNames: childNames,
        householdNames: householdNames,
        variant: RecipeSuitabilityVariant.card,
      ),
    );
  }
}

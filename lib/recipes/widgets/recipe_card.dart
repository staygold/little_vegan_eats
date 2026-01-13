// lib/recipes/widgets/recipe_card.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.imageUrl,
    this.onTap,
    this.trailing,
    this.badge,
    this.compact = false,
    this.statusText,
    this.statusIcon,
    this.cardColor,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final String? imageUrl;

  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? badge;
  final bool compact;
  final String? statusText;
  final IconData? statusIcon;
  final Color? cardColor;

  @override
  Widget build(BuildContext context) {
    // Defines the MINIMUM height, but allows growth
    final minH = compact ? 82.0 : 92.0;
    final imgW = compact ? 104.0 : 112.0;

    final hasSubtitle = (subtitle != null && subtitle!.trim().isNotEmpty) || subtitleWidget != null;
    final hasStatus = statusText != null && statusText!.trim().isNotEmpty;

    return Card(
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // ✅ CHANGED: Use ConstrainedBox + IntrinsicHeight to allow dynamic expansion
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minH),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch, // stretches image to full height
              children: [
                SizedBox(
                  width: imgW,
                  // Image height will now match the tallest content (the text column)
                  child: _ImageWithBadge(url: imageUrl, badge: badge),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2, // Allow title to wrap if needed
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (hasStatus) ...[
                              const SizedBox(width: 10),
                              RecipeStatusPill(
                                text: statusText!.trim(),
                                icon: statusIcon,
                              ),
                            ],
                          ],
                        ),

                        if (hasSubtitle) ...[
                          const SizedBox(height: 6),
                          // Render widget or text
                          subtitleWidget ?? 
                          Text(
                            subtitle!.trim(),
                            maxLines: 2, // Allow subtitle to wrap
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Center(child: trailing), // Center trailing icon vertically
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageWithBadge extends StatelessWidget {
  const _ImageWithBadge({this.url, this.badge});

  final String? url;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (u == null || u.isEmpty)
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.restaurant_menu, size: 22),
          )
        else
          Image.network(
            u,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.restaurant_menu, size: 22),
            ),
          ),
        if (badge != null)
          Positioned(
            top: 8,
            right: 8,
            child: badge!,
          ),
      ],
    );
  }
}

class RecipeStatusPill extends StatelessWidget {
  const RecipeStatusPill({
    super.key,
    required this.text,
    this.icon,
  });

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
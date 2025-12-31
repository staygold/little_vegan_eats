import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.onTap,
    this.trailing,
    this.badge,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;

  final VoidCallback? onTap;

  /// Right-side area (e.g. star icon button, chevron, etc.)
  final Widget? trailing;

  /// Small overlay on the image (e.g. favourite star, allergy icon)
  final Widget? badge;

  /// For tighter lists if needed
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 82.0 : 92.0;
    final imgW = compact ? 104.0 : 112.0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: h,
          child: Row(
            children: [
              SizedBox(
                width: imgW,
                height: double.infinity,
                child: _ImageWithBadge(url: imageUrl, badge: badge),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          maxLines: 1,
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
                  child: trailing,
                ),
            ],
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

/// Small standard “pill” you can reuse for status (safe/swap/blocked) if you want.
class RecipeStatusPill extends StatelessWidget {
  const RecipeStatusPill({super.key, required this.text, this.icon});

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

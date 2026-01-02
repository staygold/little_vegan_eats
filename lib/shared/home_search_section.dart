// lib/shared/home_search_section.dart
import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';

class QuickActionItem {
  final String label;
  final String asset; // svg asset path (e.g. assets/images/icons/latest.svg)
  final VoidCallback onTap;

  const QuickActionItem({
    required this.label,
    required this.asset,
    required this.onTap,
  });
}

class HomeSearchSection extends StatelessWidget {
  final String? firstName;
  final bool showGreeting;

  /// Tap anywhere on the "search bar" to open your search experience.
  final VoidCallback onSearchTap;

  /// Exactly 4 buttons (Latest, Popular, Mains, Snacks)
  final List<QuickActionItem> quickActions;

  const HomeSearchSection({
    super.key,
    required this.onSearchTap,
    required this.quickActions,
    this.firstName,
    this.showGreeting = true,
  }) : assert(quickActions.length == 4, 'Expected exactly 4 quick actions');

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF005A4F);
    const pillBg = Colors.white;
    const iconGrey = Color.fromRGBO(4, 66, 70, 0.45);
    const quickBg = Color.fromRGBO(255, 255, 255, 0.10);

    final greetingName =
        (firstName != null && firstName!.trim().isNotEmpty)
            ? firstName!.trim()
            : null;

    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Optional greeting (Home only)
          if (showGreeting && greetingName != null) ...[
            Text(
              'Hey, $greetingName!',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
          ] else if (showGreeting) ...[
            const SizedBox(height: 8),
          ],

          // Heading
          const Text(
            'What do you feel like eating?',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 16),

          // Search "bar" (button, not editable)
          // ✅ Robust tap handling (works reliably inside scrollables)
          Semantics(
            button: true,
            label: 'Search recipes or by ingredients',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onSearchTap,
                borderRadius: BorderRadius.circular(999),
                // ✅ Forces InkWell to compete properly in gesture arena
                // (prevents "tap dies" when inside a scroll view)
                splashFactory: InkSparkle.splashFactory,
                child: Ink(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.search,
                        size: 30,
                        color: iconGrey,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search recipes or by ingredients',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontVariations: [FontVariation('wght', 600)],
                            height: 1.0,
                            letterSpacing: 0,
                            color: AppColors.brandDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Quick actions (exactly 4)
          Row(
            children: [
              for (final item in quickActions)
                Expanded(
                  child: _QuickActionButton(
                    item: item,
                    bg: quickBg,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final QuickActionItem item;
  final Color bg;

  const _QuickActionButton({
    required this.item,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  item.asset,
                  width: 34,
                  height: 34,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

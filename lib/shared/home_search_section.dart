// lib/shared/home_search_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    const pillText = Color(0xFF044246);
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
      fontSize: 19,
      fontWeight: FontWeight.w400, // regular
      color: Colors.white70, // 80% white
    ),
  ),
  const SizedBox(height: 2), // ✅ exact gap
] else if (showGreeting) ...[
  const SizedBox(height: 6),
],
          // Heading
          const Text(
  'What do you feel like eating?',
  style: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800, // extra bold
    color: Colors.white, // 100% white
    height: 1.2,
  ),
),

          const SizedBox(height: 16),

          // Search "bar" (button, not editable)
          Semantics(
            button: true,
            label: 'Search recipes or by ingredients',
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onSearchTap,
              child: Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Search recipes or by ingredients',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: pillText,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.search, size: 30, color: iconGrey),
                  ],
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
    return InkWell(
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
    );
  }
}

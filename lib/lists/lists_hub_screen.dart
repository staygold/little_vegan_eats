// lib/lists/lists_hub_screen.dart
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ListsHubScreen extends StatelessWidget {
  const ListsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      body: SafeArea(
        top: false, // top header already handles inset
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: const [
            Text(
              'Lists',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontVariations: [FontVariation('wght', 900)],
                color: Color(0xFF044246),
              ),
            ),
            SizedBox(height: 12),
            _HubCard(
              title: 'Shopping List',
              subtitle:
                  'Add ingredients from recipes and meal plans, then tick things off at the shops.',
              iconAsset: 'assets/images/icons/lists.svg',
            ),
          ],
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String iconAsset;

  const _HubCard({
    required this.title,
    required this.subtitle,
    required this.iconAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const _ShoppingListPlaceholderScreen(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconChip(asset: iconAsset),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontVariations: [FontVariation('wght', 800)],
                        color: Color(0xFF044246),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF044246),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  fontVariations: [FontVariation('wght', 600)],
                  color: Color(0xFF3A6A67),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  final String asset;
  const _IconChip({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F3),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: SvgPicture.asset(
        asset,
        width: 18,
        height: 18,
        colorFilter: const ColorFilter.mode(
          Color(0xFF005A4F),
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// PLACEHOLDER (replace with real shopping list screen)
/// ---------------------------------------------------------------------------

class _ShoppingListPlaceholderScreen extends StatelessWidget {
  const _ShoppingListPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF6F8F7),
      appBar: _BasicAppBar(title: 'Shopping List'),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Shopping list screen placeholder.\n\nNext: ingredient rows, quantities, and tick-off state.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
              fontVariations: [FontVariation('wght', 700)],
              color: Color(0xFF044246),
            ),
          ),
        ),
      ),
    );
  }
}

class _BasicAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _BasicAppBar({required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      iconTheme: const IconThemeData(color: Color(0xFF044246)),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 16,
          fontWeight: FontWeight.w800,
          fontVariations: [FontVariation('wght', 800)],
          color: Color(0xFF044246),
        ),
      ),
    );
  }
}

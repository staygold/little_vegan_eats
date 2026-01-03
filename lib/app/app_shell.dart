// lib/shell/app_shell.dart
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../home/home_screen.dart';
import '../recipes/recipe_hub_screen.dart';
import '../meal_plan/plans_hub_screen.dart';
import '../lists/lists_hub_screen.dart'; // 👈 NEW
import '../profile/profile_screen.dart';

import 'top_header_bar.dart';

class AppShell extends StatefulWidget {
  final int initialIndex;

  const AppShell({super.key, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index;

  // Family is NOT in bottom nav
  static const int _familyIndex = 4;

  final List<Widget> _pages = const [
    HomeScreen(),        // 0
    RecipeHubScreen(),   // 1
    PlansHubScreen(),    // 2
    ListsHubScreen(),    // 3  👈 NEW
    ProfileScreen(),    // 4 (Family)
  ];

  static const Color inactiveColor = Color(0xFF005A4F);
  static const Color activeColor = Color(0xFF32998D);
  static const double iconSize = 24;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _pages.length - 1);
  }

  void _goFamily() {
    if (_index == _familyIndex) return;
    setState(() => _index = _familyIndex);
  }

  Widget _buildHeader() {
    return TopHeaderBar(
      onFamilyTap: _goFamily,
    );
  }

  Widget _navIcon(String asset, bool active) {
    return SvgPicture.asset(
      asset,
      width: iconSize,
      height: iconSize,
      colorFilter: ColorFilter.mode(
        active ? activeColor : inactiveColor,
        BlendMode.srcIn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );

    // Bottom nav only maps to first 4 pages
    final int bottomIndex = (_index <= 3) ? _index : 3;

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false,
              child: IndexedStack(
                index: _index,
                children: _pages,
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: Theme(
        data: theme,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                blurRadius: 20,
                color: Color.fromRGBO(0, 0, 0, 0.2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: BottomNavigationBar(
                currentIndex: bottomIndex,
                onTap: (i) {
                  if (i == bottomIndex) return;
                  setState(() => _index = i);
                },
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.white,
                elevation: 0,
                iconSize: iconSize,
                selectedItemColor: activeColor,
                unselectedItemColor: inactiveColor,
                selectedFontSize: 12,
                unselectedFontSize: 12,
                selectedLabelStyle: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w700,
                  fontVariations: [FontVariation('wght', 700)],
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w700,
                  fontVariations: [FontVariation('wght', 700)],
                ),
                items: [
                  BottomNavigationBarItem(
                    icon: _navIcon('assets/images/icons/home.svg', false),
                    activeIcon:
                        _navIcon('assets/images/icons/home.svg', true),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: _navIcon('assets/images/icons/recipes.svg', false),
                    activeIcon:
                        _navIcon('assets/images/icons/recipes.svg', true),
                    label: 'Recipes',
                  ),
                  BottomNavigationBarItem(
                    icon: _navIcon('assets/images/icons/plans.svg', false),
                    activeIcon:
                        _navIcon('assets/images/icons/plans.svg', true),
                    label: 'Plans',
                  ),
                  BottomNavigationBarItem(
                    icon: _navIcon('assets/images/icons/lists.svg', false),
                    activeIcon:
                        _navIcon('assets/images/icons/lists.svg', true),
                    label: 'Lists',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

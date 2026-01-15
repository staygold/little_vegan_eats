// lib/shell/app_shell.dart
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../home/home_screen.dart';
import '../recipes/recipe_hub_screen.dart';
import '../meal_plan/plans_hub_screen.dart';
import '../lists/lists_hub_screen.dart';
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
    HomeScreen(),       // 0
    RecipeHubScreen(),  // 1
    PlansHubScreen(),   // 2
    ListsHubScreen(),   // 3
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

  BottomNavigationBarItem _item({
    required String asset,
    required String label,
    required bool isFamily,
  }) {
    // When on Family/Profile, make activeIcon identical to icon so
    // nothing ever looks "selected".
    final icon = _navIcon(asset, false);

    return BottomNavigationBarItem(
      icon: icon,
      activeIcon: isFamily ? icon : _navIcon(asset, true),
      label: label,
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

    final bool isFamily = _index == _familyIndex;

    // Bottom nav only maps to first 4 pages
    final int bottomIndex = _index.clamp(0, 3);

    // When on Family, force a valid index but style it so nothing looks selected.
    final int navIndex = isFamily ? 0 : bottomIndex;

    final Color navSelectedColor = isFamily ? inactiveColor : activeColor;
    final Color navUnselectedColor = inactiveColor;

    final TextStyle navLabelStyle = const TextStyle(
      fontFamily: 'Montserrat',
      fontWeight: FontWeight.w700,
      fontVariations: [FontVariation('wght', 700)],
    );

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
                currentIndex: navIndex,
                onTap: (i) {
                  // Always navigate to actual tab pages (0..3)
                  if (i == bottomIndex && !isFamily) return;
                  setState(() => _index = i);
                },
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.white,
                elevation: 0,
                iconSize: iconSize,

                // ✅ Make selected + unselected look the same when on Family
                selectedItemColor: navSelectedColor,
                unselectedItemColor: navUnselectedColor,
                selectedFontSize: 12,
                unselectedFontSize: 12,
                selectedLabelStyle: navLabelStyle,
                unselectedLabelStyle: navLabelStyle,

                items: [
                  _item(
                    asset: 'assets/images/icons/home.svg',
                    label: 'Home',
                    isFamily: isFamily,
                  ),
                  _item(
                    asset: 'assets/images/icons/recipes.svg',
                    label: 'Recipes',
                    isFamily: isFamily,
                  ),
                  _item(
                    asset: 'assets/images/icons/plans.svg',
                    label: 'Plans',
                    isFamily: isFamily,
                  ),
                  _item(
                    asset: 'assets/images/icons/lists.svg',
                    label: 'Lists',
                    isFamily: isFamily,
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

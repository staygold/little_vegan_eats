import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../home/home_screen.dart';
import '../recipes/recipe_list_screen.dart';
import '../meal_plan/plans_hub_screen.dart';
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

  final _pages = const [
    HomeScreen(),
    RecipeListScreen(),
    PlansHubScreen(),
    ProfileScreen(),
  ];

  // 🎨 Colours
  static const Color inactiveColor = Color(0xFF044246);
  static const Color activeColor = Color(0xFF32998D);

  // 📐 Sizing
  static const double barHeight = 92;
  static const double iconSize = 24;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _pages.length - 1);
  }

  Widget _navIcon(String asset, bool active) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          asset,
          width: iconSize,
          height: iconSize,
          colorFilter: ColorFilter.mode(
            active ? activeColor : inactiveColor,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(height: 4), // ✅ exact icon → label gap
      ],
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const TopHeaderBar(),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: _pages,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Theme(
        data: theme,
        child: Container(
          height: barHeight,
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                offset: Offset(0, 0),
                blurRadius: 20,
                spreadRadius: 0,
                color: Color.fromRGBO(4, 66, 70, 0.20),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 0,
            selectedItemColor: activeColor,
            unselectedItemColor: inactiveColor,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            selectedLabelStyle: const TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w600,
            ),
            items: [
              BottomNavigationBarItem(
                icon: _navIcon('assets/images/icons/home.svg', false),
                activeIcon: _navIcon('assets/images/icons/home.svg', true),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: _navIcon('assets/images/icons/recipes.svg', false),
                activeIcon: _navIcon('assets/images/icons/recipes.svg', true),
                label: 'Recipes',
              ),
              BottomNavigationBarItem(
                icon: _navIcon('assets/images/icons/plans.svg', false),
                activeIcon: _navIcon('assets/images/icons/plans.svg', true),
                label: 'Plans',
              ),
              BottomNavigationBarItem(
                icon: _navIcon('assets/images/icons/family.svg', false),
                activeIcon: _navIcon('assets/images/icons/family.svg', true),
                label: 'Family',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

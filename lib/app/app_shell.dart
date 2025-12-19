import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../recipes/recipe_list_screen.dart';
import '../meal_plan/meal_plan_screen.dart';
import '../meal_plan/saved_meal_plans_screen.dart';

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
    MealPlanScreen(),
    SavedMealPlansScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _pages.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: _pages,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.restaurant_menu), label: 'Recipes'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Meal Plan'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Saved'),
        ],
      ),
    );
  }
}

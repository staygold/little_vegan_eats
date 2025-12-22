import 'package:flutter/material.dart';

import 'meal_plan_screen.dart';
import 'saved_meal_plans_screen.dart';
import 'core/meal_plan_keys.dart'; // ✅ correct path

class PlansHubScreen extends StatelessWidget {
  const PlansHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final todayKey = MealPlanKeys.todayKey();

    Widget card({
      required IconData icon,
      required String title,
      required VoidCallback onTap,
    }) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meal plans')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          card(
            icon: Icons.today,
            title: "Today's meal plan",
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MealPlanScreen(focusDayKey: todayKey),
                ),
              );
            },
          ),
          card(
            icon: Icons.calendar_month,
            title: "Next 7 days",
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MealPlanScreen()),
              );
            },
          ),
          card(
            icon: Icons.bookmark,
            title: 'Saved meal plans',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedMealPlansScreen()),
              );
            },
          ),
          card(
            icon: Icons.history,
            title: 'Previous meal plans',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedMealPlansScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

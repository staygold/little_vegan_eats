import 'package:flutter/material.dart';

import 'meal_plan_screen.dart';
import 'saved_meal_plans_screen.dart';

class PlansHubScreen extends StatelessWidget {
  const PlansHubScreen({super.key});

  String _dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = _dayKey(DateTime.now());

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
            title: "This week's meal plan",
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

          // Optional: for now, Previous can just point to Saved until you build history.
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

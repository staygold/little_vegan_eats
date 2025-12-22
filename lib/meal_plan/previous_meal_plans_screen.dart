import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'meal_plan_screen.dart';
import 'meal_plan_keys.dart';

class PreviousMealPlansScreen extends StatelessWidget {
  const PreviousMealPlansScreen({super.key});

  Query<Map<String, dynamic>>? _query() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPlansWeeks');
  }

  @override
  Widget build(BuildContext context) {
    final q = _query();
    if (q == null) {
      return const Scaffold(
        body: Center(child: Text('Log in to view previous meal plans')),
      );
    }

    final currentWeekId = MealPlanKeys.currentWeekId();

    return Scaffold(
      appBar: AppBar(title: const Text('Previous meal plans')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Firestore error: ${snap.error}'),
            );
          }

          final docs = snap.data?.docs ?? [];

          // Exclude the current forward-anchored week
          final previous = docs.where((d) => d.id != currentWeekId).toList();

          if (previous.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No previous meal plans yet.'),
            );
          }

          // Sort newest → oldest (YYYY-MM-DD string sort works)
          previous.sort((a, b) => b.id.compareTo(a.id));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: previous.length,
            itemBuilder: (context, i) {
              final weekId = previous[i].id;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(
                    weekId,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Tap to view'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MealPlanScreen(weekId: weekId),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

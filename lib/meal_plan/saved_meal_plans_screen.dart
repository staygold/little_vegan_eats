import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'meal_plan_screen.dart';

class SavedMealPlansScreen extends StatelessWidget {
  const SavedMealPlansScreen({super.key});

  Query<Map<String, dynamic>>? _query() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedMealPlans')
        .orderBy('savedAt', descending: true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query();
    if (q == null) {
      return const Scaffold(body: Center(child: Text('Log in to view saved meal plans')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Saved meal plans')),
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
          if (docs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No saved meal plans yet.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final weekId = (data['weekId'] ?? '').toString().trim();
              final title = (data['title'] ?? '').toString().trim();

              final display = title.isNotEmpty ? title : (weekId.isNotEmpty ? weekId : 'Saved meal plan');

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(display, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: weekId.isNotEmpty ? Text('Week: $weekId') : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: weekId.isEmpty
                      ? null
                      : () {
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

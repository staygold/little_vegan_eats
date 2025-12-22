import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'meal_plan_screen.dart';

class PreviousMealPlansScreen extends StatelessWidget {
  const PreviousMealPlansScreen({super.key});

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _todayKey() => _dateKey(_dateOnly(DateTime.now()));

  Query<Map<String, dynamic>>? _query() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    // If you later add a field like "createdAt" / "weekStart", orderBy that instead.
    // For now we’ll just list docs as-is (Firestore can’t order by docId without a field).
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPlansWeeks');
  }

  @override
  Widget build(BuildContext context) {
    final q = _query();
    if (q == null) {
      return const Scaffold(body: Center(child: Text('Log in to view previous meal plans')));
    }

    final currentWeekId = _todayKey();

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

          // treat doc.id as weekId (matches your existing pattern)
          final previous = docs.where((d) => d.id != currentWeekId).toList();

          if (previous.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No previous meal plans yet.'),
            );
          }

          // Simple sort by doc id string (works with YYYY-MM-DD)
          previous.sort((a, b) => b.id.compareTo(a.id));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: previous.length,
            itemBuilder: (context, i) {
              final weekId = previous[i].id;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(weekId, style: const TextStyle(fontWeight: FontWeight.w700)),
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

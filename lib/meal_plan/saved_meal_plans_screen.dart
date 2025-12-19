import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'meal_plan_screen.dart';

class SavedMealPlansScreen extends StatefulWidget {
  const SavedMealPlansScreen({super.key});

  @override
  State<SavedMealPlansScreen> createState() => _SavedMealPlansScreenState();
}

class _SavedMealPlansScreenState extends State<SavedMealPlansScreen> {
  User? get _user => FirebaseAuth.instance.currentUser;

  CollectionReference<Map<String, dynamic>>? get _col {
    final u = _user;
    if (u == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .collection('mealPlansWeeks');
  }

  String _prettyDocId(String docId) {
    // docId format expected: YYYY-MM-DD
    // Display as DD/MM/YYYY
    if (docId.length != 10) return docId;
    final y = docId.substring(0, 4);
    final m = docId.substring(5, 7);
    final d = docId.substring(8, 10);
    return '$d/$m/$y';
  }

  @override
  Widget build(BuildContext context) {
    final col = _col;

    if (_user == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Log in to view saved meal plans.'),
        ),
      );
    }

    if (col == null) {
      return const Center(child: Text('Could not load saved plans.'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Meal Plans')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: col.orderBy('updatedAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snap.error}'),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No saved plans yet.'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();

              final weekId = (data['weekId'] ?? d.id).toString();
              final safeForAll = data['safeForAllChildren'];
              final selectedChild = data['selectedChildName'];

              final subtitleParts = <String>[];
              if (safeForAll == true) subtitleParts.add('All children');
              if (safeForAll == false && selectedChild != null) {
                subtitleParts.add('For $selectedChild');
              }

              return Card(
                child: ListTile(
                  title: Text('Week starting ${_prettyDocId(weekId)}'),
                  subtitle: subtitleParts.isEmpty
                      ? null
                      : Text(subtitleParts.join(' • ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MealPlanScreen(savedWeekId: weekId),
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

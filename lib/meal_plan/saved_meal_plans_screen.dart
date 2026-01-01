// lib/meal_plan/saved_meal_plans_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'saved_meal_plan_detail_screen.dart';

// ✅ reuse shared UI
import '../app/sub_header_bar.dart';

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
    final theme = Theme.of(context);

    if (q == null) {
      return const Scaffold(
        body: Center(child: Text('Log in to view saved meal plans')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          // ✅ Sub header only (no search)
          const SubHeaderBar(title: 'Saved meal plans'),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();

                    final title = (data['title'] ?? '').toString().trim();
                    final type = (data['type'] ?? '').toString().trim(); // day | week

                    final display =
                        title.isNotEmpty ? title : 'Saved meal plan';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SavedMealPlanDetailScreen(
                                  savedPlanId: doc.id,
                                ),
                              ),
                            );
                          },
                          child: ListTile(
                            title: Text(
                              display,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle:
                                type.isNotEmpty ? Text('Type: $type') : null,
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

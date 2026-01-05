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

  // ---------------------------------------------------------------------------
  // ✅ Limit enforcement + auto-heal counter
  // We DON'T enforce the cap here (creation happens elsewhere), but we:
  // - show current count / cap
  // - auto-heal savedMealPlanCount on the user doc if missing/out of sync
  // ---------------------------------------------------------------------------

  static const int maxSavedMealPlans = 20;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  Future<void> _ensureCounterHealthy({
    required String uid,
    required int actualCount,
  }) async {
    final userRef = _userRef(uid);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        final data = snap.data() ?? <String, dynamic>{};

        final stored = data['savedMealPlanCount'];
        final storedCount = (stored is int) ? stored : null;

        // If missing or out-of-sync, set it.
        if (storedCount == null || storedCount != actualCount) {
          tx.set(userRef, {'savedMealPlanCount': actualCount}, SetOptions(merge: true));
        }
      });
    } catch (_) {
      // ignore (best-effort)
    }
  }

  // ---------------------------------------------------------------------------
  // ✅ Safe delete (decrements counter)
  // ---------------------------------------------------------------------------

  Future<void> _deleteSavedPlan({
    required BuildContext context,
    required String uid,
    required String savedPlanId,
  }) async {
    final db = FirebaseFirestore.instance;
    final userRef = _userRef(uid);
    final planRef = userRef.collection('savedMealPlans').doc(savedPlanId);

    try {
      await db.runTransaction((tx) async {
        final planSnap = await tx.get(planRef);
        if (!planSnap.exists) return;

        tx.delete(planRef);
        tx.set(
          userRef,
          {'savedMealPlanCount': FieldValue.increment(-1)},
          SetOptions(merge: true),
        );
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved meal plan deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete saved meal plan?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return res == true;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final q = _query();
    final theme = Theme.of(context);

    if (q == null || user == null) {
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

                // ✅ Best-effort: keep savedMealPlanCount in sync with reality
                // (helps if you created plans before implementing the counter)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _ensureCounterHealthy(uid: user.uid, actualCount: docs.length);
                });

                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No saved meal plans yet.'),
                  );
                }

                final count = docs.length;
                final atCap = count >= maxSavedMealPlans;

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: docs.length + 1, // + header status row
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Saved: $count / $maxSavedMealPlans',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (atCap)
                                  Text(
                                    'Limit reached',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    final doc = docs[i - 1];
                    final data = doc.data();

                    final title = (data['title'] ?? '').toString().trim();
                    final type = (data['type'] ?? '').toString().trim(); // day | week

                    final display = title.isNotEmpty ? title : 'Saved meal plan';

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
                            subtitle: type.isNotEmpty ? Text('Type: $type') : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await _confirmDelete(context);
                                    if (!ok) return;

                                    await _deleteSavedPlan(
                                      context: context,
                                      uid: user.uid,
                                      savedPlanId: doc.id,
                                    );
                                  },
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
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

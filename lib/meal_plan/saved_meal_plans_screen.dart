// lib/meal_plan/saved_meal_plans_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core/meal_plan_controller.dart';
import 'core/meal_plan_keys.dart';
import 'core/meal_plan_repository.dart';
import 'services/meal_plan_manager.dart';

import 'saved_meal_plan_detail_screen.dart';

class SavedMealPlansScreen extends StatefulWidget {
  const SavedMealPlansScreen({super.key});

  @override
  State<SavedMealPlansScreen> createState() => _SavedMealPlansScreenState();
}

class _SavedMealPlansScreenState extends State<SavedMealPlansScreen> {
  MealPlanController? _activeCtrl;
  late final MealPlanRepository _repo;

  // Subscriptions
  StreamSubscription? _plansSub;

  // Data Cache
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _savedPlans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repo = MealPlanRepository(FirebaseFirestore.instance);
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      _initController(user);
      _initPlansStream(user);
    }
  }

  void _initController(User user) {
    // We only use controller for its helpers / consistency.
    // This does NOT affect calendar logic.
    _activeCtrl = MealPlanController(
      auth: FirebaseAuth.instance,
      repo: _repo,
      initialWeekId: MealPlanKeys.currentWeekId(),
    );

    _activeCtrl!.addListener(() {
      if (mounted) setState(() {});
    });

    _activeCtrl!.start();
    _activeCtrl!.ensureWeek();
  }

  void _initPlansStream(User user) {
    _plansSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedMealPlans')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _savedPlans = snap.docs;

        // Sort client-side newest first (handles pending serverTimestamp)
        _savedPlans.sort((a, b) {
          final tsA = a.data()['savedAt'];
          final tsB = b.data()['savedAt'];
          final dA = (tsA is Timestamp) ? tsA.toDate() : DateTime.now();
          final dB = (tsB is Timestamp) ? tsB.toDate() : DateTime.now();
          return dB.compareTo(dA);
        });

        _isLoading = false;
      });
    });
  }

  @override
  void dispose() {
    _plansSub?.cancel();
    _activeCtrl?.stop();
    _activeCtrl?.dispose();
    super.dispose();
  }

  // -------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------

  bool _isDayPlan(Map<String, dynamic> d) {
    final planType = (d['planType'] ?? d['type'] ?? '').toString().trim().toLowerCase();
    if (planType == 'day') return true;
    if (planType == 'week') return false;
    final typeRaw = (d['type'] ?? '').toString().trim().toLowerCase();
    return typeRaw.contains('day') || (d['days'] is Map && (d['days'] as Map).length == 1);
  }

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return '';
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Scan the calendar weeks from "today" forward and see whether this saved plan appears anywhere.
  /// We only care about FUTURE impact for delete warnings.
  Future<int> _countFutureScheduledUses(String planId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0;

    // We already use 52-week horizon in the system.
    const weeksToScan = 52;

    final today = _dateOnly(DateTime.now());
    int count = 0;

    for (int i = 0; i < weeksToScan; i++) {
      final dateInWeek = today.add(Duration(days: i * 7));
      final weekId = MealPlanKeys.weekIdForDate(dateInWeek);
      final docRef = _repo.weekDoc(uid: uid, weekId: weekId);
      final snap = await docRef.get();
      if (!snap.exists) continue;

      final data = snap.data() ?? {};
      final cfg = data['config'];
      if (cfg is! Map) continue;

      // 1) Week link
      final sourceWeekPlanId = (cfg['sourceWeekPlanId'] ?? '').toString().trim();
      if (sourceWeekPlanId == planId && sourceWeekPlanId.isNotEmpty) {
        // Count only days >= today in that week
        final dayKeys = MealPlanKeys.weekDayKeys(weekId);
        for (final dk in dayKeys) {
          final dt = MealPlanKeys.parseDayKey(dk);
          if (dt != null && !dt.isBefore(today)) count++;
        }
        continue;
      }

      // 2) Day links
      final daySources = cfg['daySources'];
      if (daySources is Map) {
        daySources.forEach((dayKey, v) {
          if ((v ?? '').toString().trim() != planId) return;
          final dt = MealPlanKeys.parseDayKey(dayKey.toString());
          if (dt != null && !dt.isBefore(today)) count++;
        });
      }
    }

    return count;
  }

  // -------------------------------------------------------
  // ACTIONS
  // -------------------------------------------------------

  Future<void> _deletePlan(String planId, Map<String, dynamic> planData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    int futureUses = 0;
    try {
      futureUses = await _countFutureScheduledUses(planId);
    } catch (_) {
      // If scanning fails, we still allow delete with the simpler warning.
      futureUses = -1;
    }

    final isScheduled = futureUses > 0;
    final unknown = futureUses == -1;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete meal plan?'),
        content: Text(
          unknown
              ? 'This cannot be undone.\n\nIf this plan is scheduled in your calendar, deleting it may remove future meals created from it.'
              : (isScheduled
                  ? 'This cannot be undone.\n\nThis plan is scheduled on your calendar.\nDeleting it will remove all future meals created from it.'
                  : 'This cannot be undone.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final manager = MealPlanManager(
        auth: FirebaseAuth.instance,
        firestore: FirebaseFirestore.instance,
      );
      await manager.deleteSavedPlan(planId: planId, planData: planData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _openPlanDetail(String planId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SavedMealPlanDetailScreen(savedPlanId: planId)),
    );
  }

  // -------------------------------------------------------
  // BUILD
  // -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const Scaffold(body: Center(child: Text('Log in')));
    }

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFECF3F4),
        appBar: PreferredSize(preferredSize: Size.fromHeight(56), child: SizedBox()),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_savedPlans.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFECF3F4),
        appBar: AppBar(title: const Text('Created Plans')),
        body: const Center(
          child: Text('No meal plans yet.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(title: const Text('Created Plans')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _savedPlans.length,
        itemBuilder: (context, index) {
          final doc = _savedPlans[index];
          final data = doc.data();

          final isDay = _isDayPlan(data);
          final title = (data['title'] ?? 'Untitled').toString();
          final savedAt = _formatDate(data['savedAt']);

          final flagText = isDay ? 'DAY' : 'WEEK';
          final flagColor = isDay ? Colors.blue.shade50 : Colors.teal.shade50;
          final flagTextColor = isDay ? Colors.blue.shade700 : Colors.teal.shade700;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 1,
            child: InkWell(
              onTap: () => _openPlanDetail(doc.id),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF044246),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                savedAt.isNotEmpty ? 'Created $savedAt' : 'Created',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black.withOpacity(0.5),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: flagColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  flagText,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: flagTextColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ]),
                      ),
                      IconButton(
                        onPressed: () => _deletePlan(doc.id, data),
                        icon: const Icon(Icons.delete_outline, color: Colors.grey),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

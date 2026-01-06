import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core/meal_plan_controller.dart';
import 'core/meal_plan_keys.dart';
import 'core/meal_plan_repository.dart';

import 'saved_meal_plan_detail_screen.dart';
import 'meal_plan_screen.dart'; 

class SavedMealPlansScreen extends StatefulWidget {
  const SavedMealPlansScreen({super.key});

  @override
  State<SavedMealPlansScreen> createState() => _SavedMealPlansScreenState();
}

class _SavedMealPlansScreenState extends State<SavedMealPlansScreen> {
  MealPlanController? _activeCtrl;

  @override
  void initState() {
    super.initState();
    _activeCtrl = MealPlanController(
      auth: FirebaseAuth.instance,
      repo: MealPlanRepository(FirebaseFirestore.instance),
      initialWeekId: MealPlanKeys.currentWeekId(),
    );
    _activeCtrl!.start();
  }

  @override
  void dispose() {
    _activeCtrl?.stop();
    _activeCtrl?.dispose();
    super.dispose();
  }

  bool _isPlanActive(Map<String, dynamic> savedPlanData, String savedDocId) {
    if (_activeCtrl?.weekData == null) return false;
    
    final activeConfig = _activeCtrl!.weekData!['config'];
    if (activeConfig is! Map) return false;

    final activeSourceId = activeConfig['sourcePlanId'];
    if (activeSourceId != null && activeSourceId.toString() == savedDocId) {
      return true;
    }
    return false;
  }

  // ----------------------------
  // ✅ DATA NORMALIZATION (Shared with Detail Screen)
  // ----------------------------
  Map<String, dynamic> _normalizeForActivation(Map<String, dynamic> rawDayData) {
    final processed = <String, dynamic>{};
    processed.addAll(rawDayData);

    for (final slot in ['breakfast', 'lunch', 'dinner', 'snack1', 'snack2']) {
      if (rawDayData[slot] is Map) {
        final entry = Map<String, dynamic>.from(rawDayData[slot]);
        
        // Unify Type/Kind for backward compatibility
        final kind = entry['kind'] ?? entry['type'];
        if (kind != null) {
          entry['kind'] = kind;
          entry['type'] = kind; 
        }

        // Unify ID/RecipeId for Home Screen compatibility
        final id = entry['id'] ?? entry['recipeId'];
        if (id != null) {
          entry['id'] = id;
          entry['recipeId'] = id; 
        }

        processed[slot] = entry;
      }
    }
    return processed;
  }

  // ✅ ROBUST ACTIVATION LOGIC
  Future<void> _activatePlan(Map<String, dynamic> planData, String docId) async {
    // 1. DETECT TYPE & SCRUB DATA
    Map<String, dynamic>? dayData;
    Map<String, dynamic>? daysData;
    bool isDayPlan = false;

    if (planData['day'] is Map) {
      isDayPlan = true;
      dayData = Map<String, dynamic>.from(planData['day']);
    } else if (planData['days'] is Map) {
      final map = planData['days'] as Map<String, dynamic>;
      if (map.length == 1) {
        isDayPlan = true;
        dayData = Map<String, dynamic>.from(map.values.first);
      } else {
        daysData = map;
      }
    }

    // Scrub nested wrapper if present (Prevents "empty" items)
    if (isDayPlan && dayData != null) {
       if (dayData!.containsKey('day') && dayData!['day'] is Map) {
         dayData = Map<String, dynamic>.from(dayData!['day']);
       } else if (dayData!.containsKey('meals') && dayData!['meals'] is Map) {
         dayData = Map<String, dynamic>.from(dayData!['meals']);
       }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use this plan?'),
        content: Text(
          isDayPlan 
          ? 'This will replace your meal plan for TODAY.'
          : 'This will replace your current weekly schedule.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activate Plan'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final currentWeekId = MealPlanKeys.currentWeekId();
      final batch = FirebaseFirestore.instance.batch();

      final weekRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mealPlansWeeks')
          .doc(currentWeekId);

      final todayKey = MealPlanKeys.todayKey();
      final targetDateKeys = MealPlanKeys.weekDayKeys(currentWeekId);

      // 2. APPLY UPDATE (Normalized for compatibility)
      if (isDayPlan && dayData != null) {
        final safeDayData = _normalizeForActivation(dayData!);

        batch.set(weekRef, {
          'uid': user.uid,
          'weekId': currentWeekId,
          'days': { todayKey: safeDayData },
          'config': { 
            'sourcePlanId': docId, 
            'updatedAt': FieldValue.serverTimestamp(),
            'daysToPlan': 1,
            'startDate': todayKey
          }
        }, SetOptions(merge: true)); 
      } else if (daysData != null) {
        final sourceKeys = daysData.keys.toList()..sort();
        final remapped = <String, dynamic>{};
        
        for (int i = 0; i < targetDateKeys.length; i++) {
          if (i < sourceKeys.length) {
            final rawDay = daysData[sourceKeys[i]];
            if (rawDay is Map<String, dynamic>) {
              remapped[targetDateKeys[i]] = _normalizeForActivation(rawDay);
            } else {
              remapped[targetDateKeys[i]] = rawDay;
            }
          }
        }

        batch.set(weekRef, {
          'uid': user.uid,
          'weekId': currentWeekId,
          'days': remapped,
          'config': { 
            'sourcePlanId': docId, 
            'updatedAt': FieldValue.serverTimestamp(),
            'daysToPlan': 7,
            'startDate': targetDateKeys.first
          }
        }, SetOptions(merge: true));
      }

      // 3. UPDATE USER POINTER
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      batch.set(userRef, {
        'activeSavedMealPlanId': docId
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan activated!')),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error activating: $e')),
      );
    }
  }

  Future<void> _deletePlan(String docId, bool isActive) async {
    final title = isActive ? 'Delete active plan?' : 'Delete saved plan?';
    final content = isActive 
        ? 'This plan is currently active.\n\nDeleting it will remove it from your library AND clear your current weekly schedule.' 
        : 'This cannot be undone.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (isActive) {
        await _activeCtrl?.clearPlan();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('savedMealPlans')
          .doc(docId)
          .delete();
          
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'savedMealPlanCount': FieldValue.increment(-1),
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isActive ? 'Plan deleted & schedule cleared' : 'Plan deleted')),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting plan')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(title: const Text('Created Plans')),
      body: AnimatedBuilder(
        animation: _activeCtrl!,
        builder: (context, _) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('savedMealPlans')
                .orderBy('savedAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allDocs = snap.data?.docs ?? [];
              if (allDocs.isEmpty) {
                return const Center(
                  child: Text(
                    'No saved plans yet.\nCreate one from the Home screen!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              QueryDocumentSnapshot<Map<String, dynamic>>? activeDoc;
              final otherDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              for (final doc in allDocs) {
                if (_isPlanActive(doc.data(), doc.id)) {
                  activeDoc = doc;
                } else {
                  otherDocs.add(doc);
                }
              }

              final displayList = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (activeDoc != null) displayList.add(activeDoc);
              displayList.addAll(otherDocs);

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: displayList.length,
                itemBuilder: (context, index) {
                  final doc = displayList[index];
                  final data = doc.data();
                  final isActive = (activeDoc != null && doc.id == activeDoc.id);

                  return Column(
                    children: [
                      if (isActive && index == 0) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8.0, left: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'CURRENTLY ACTIVE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF32998D),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (!isActive && index == (activeDoc != null ? 1 : 0) && activeDoc != null) ...[
                        const SizedBox(height: 12),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8.0, left: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'OTHER PLANS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Colors.grey,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ],

                      _SavedPlanCard(
                        data: data,
                        isActive: isActive,
                        onTap: () {
                          if (isActive) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MealPlanScreen(weekId: MealPlanKeys.currentWeekId()),
                              ),
                            );
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SavedMealPlanDetailScreen(savedPlanId: doc.id),
                              ),
                            );
                          }
                        },
                        onActivate: () => _activatePlan(data, doc.id),
                        onDelete: () => _deletePlan(doc.id, isActive),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SavedPlanCard extends StatelessWidget {
  const _SavedPlanCard({
    required this.data,
    required this.isActive,
    required this.onTap,
    required this.onActivate,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return '';
  }

  String _cleanTitle(String? raw, bool isDay) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty || s.toLowerCase().contains('week_generated') || s.toLowerCase().contains('generated')) {
      return isDay ? 'My Day Plan' : 'My Week Plan';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final typeRaw = (data['type'] ?? 'Custom').toString();
    bool isDay = typeRaw.toLowerCase().contains('day');

    if (!isDay && data['days'] is Map) {
      final map = data['days'] as Map;
      if (map.length == 1) {
        isDay = true;
      }
    }

    final title = _cleanTitle(data['title'], isDay);
    final savedAt = _formatDate(data['savedAt']);

    final String flagText = isDay ? 'DAY' : 'WEEK';
    final Color flagColor = isDay ? Colors.blue.shade50 : Colors.teal.shade50;
    final Color flagTextColor = isDay ? Colors.blue.shade700 : Colors.teal.shade700;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isActive 
          ? const BorderSide(color: Color(0xFF32998D), width: 2) 
          : BorderSide.none,
      ),
      elevation: isActive ? 4 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF044246),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              isActive ? 'Active Plan' : 'Created $savedAt',
                              style: TextStyle(
                                fontSize: 12,
                                color: isActive ? const Color(0xFF32998D) : Colors.black.withOpacity(0.5),
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (!isActive) ...[
                              const SizedBox(width: 8),
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
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2F1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle,
                              size: 16, color: Color(0xFF32998D)),
                          SizedBox(width: 4),
                          Text(
                            'ACTIVE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF32998D),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isActive)
                    TextButton.icon(
                      onPressed: onActivate,
                      icon: const Icon(Icons.play_circle_outline, size: 20),
                      label: const Text('Make Active'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF32998D),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.grey),
                    tooltip: 'Delete',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
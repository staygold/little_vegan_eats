// lib/meal_plan/saved_meal_plans_screen.dart
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
  late final MealPlanRepository _repo;

  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _repo = MealPlanRepository(FirebaseFirestore.instance);

    _activeCtrl = MealPlanController(
      auth: FirebaseAuth.instance,
      repo: _repo,
      initialWeekId: MealPlanKeys.currentWeekId(),
    );
    _activeCtrl!.start();
    _activeCtrl!.ensureWeek();

    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _activeCtrl?.stop();
    _activeCtrl?.dispose();
    super.dispose();
  }

  // -------------------------------------------------------
  // ACTIVE DETECTION
  // -------------------------------------------------------

  bool _weekUsesSavedPlan(Map<String, dynamic>? weekData, String planId) {
    if (weekData == null) return false;

    final cfg = weekData['config'];
    if (cfg is! Map) return false;

    // Check Week Plan pointer
    final sourceWeekPlanId = (cfg['sourceWeekPlanId'] ?? '').toString().trim();
    if (sourceWeekPlanId.isNotEmpty && sourceWeekPlanId == planId) return true;

    // Check Day pointers
    final daySources = cfg['daySources'];
    if (daySources is Map) {
      for (final v in daySources.values) {
        final id = (v ?? '').toString().trim();
        if (id == planId) return true;
      }
    }

    // Legacy fallback
    final legacySource = (cfg['sourcePlanId'] ?? '').toString().trim();
    if (legacySource.isNotEmpty && legacySource == planId) return true;

    return false;
  }

  bool _isPlanActive(Map<String, dynamic> savedPlanData, String savedDocId) {
    return _weekUsesSavedPlan(_activeCtrl?.weekData, savedDocId);
  }

  // ----------------------------
  // DATA NORMALIZATION
  // ----------------------------
  Map<String, dynamic> _normalizeForActivation(Map<String, dynamic> rawDayData) {
    final processed = <String, dynamic>{};
    processed.addAll(rawDayData);

    for (final slot in ['breakfast', 'lunch', 'dinner', 'snack1', 'snack2']) {
      final raw = rawDayData[slot];
      if (raw is Map) {
        final entry = Map<String, dynamic>.from(raw);
        // Normalize keys
        final kind = entry['kind'] ?? entry['type'];
        if (kind != null) {
          entry['kind'] = kind;
          entry['type'] = kind;
        }
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

  // -------------------------------------------------------
  // PLAN SHAPE DETECTION
  // -------------------------------------------------------

  ({bool isDayPlan, Map<String, dynamic>? dayData, Map<String, dynamic>? daysData})
      _extractSavedPlanShape(Map<String, dynamic> planData) {
    Map<String, dynamic>? dayData;
    Map<String, dynamic>? daysData;
    bool isDayPlan = false;

    final typeRaw = (planData['type'] ?? '').toString().trim().toLowerCase();
    if (typeRaw == 'day') {
      isDayPlan = true;
    }

    if (planData['day'] is Map) {
      isDayPlan = true;
      dayData = Map<String, dynamic>.from(planData['day'] as Map);
    } else if (planData['days'] is Map) {
      final map = Map<String, dynamic>.from(planData['days'] as Map);
      if (map.isEmpty) {
        // empty
      } else if (isDayPlan || map.length == 1) {
        isDayPlan = true;
        final first = map.values.first;
        if (first is Map) dayData = Map<String, dynamic>.from(first as Map);
      } else {
        daysData = map;
      }
    }

    return (isDayPlan: isDayPlan, dayData: dayData, daysData: daysData);
  }

  // -------------------------------------------------------
  // ✅ ACTIVATION LOGIC (FIXED)
  // -------------------------------------------------------

  Future<void> _activatePlan(Map<String, dynamic> planData, String docId) async {
    final shape = _extractSavedPlanShape(planData);
    final isDayPlan = shape.isDayPlan;
    var dayData = shape.dayData;
    final daysData = shape.daysData;
    final String title = planData['title'] ?? 'Untitled Plan';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use this plan?'),
        content: Text(
          isDayPlan
              ? 'This will replace your plan for TODAY (${MealPlanKeys.formatPretty(MealPlanKeys.todayKey())}).'
              : 'This will replace your current weekly schedule.',
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

    final uid = user.uid;
    final currentWeekId = MealPlanKeys.currentWeekId();
    final todayKey = MealPlanKeys.todayKey();
    final horizonKeys = MealPlanKeys.weekDayKeys(currentWeekId);

    try {
      await _repo.ensureWeekExists(uid: uid, weekId: currentWeekId);

      final weekRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('mealPlansWeeks')
          .doc(currentWeekId);

      // ---------------------------------------------------------
      // CASE A: Activate Day Plan (Fix: Switch to Day Mode)
      // ---------------------------------------------------------
      if (isDayPlan) {
        if (dayData == null) return;
        final safeDayData = _normalizeForActivation(dayData);

        // We update the map destructively to ensure we leave "Week Mode"
        final updates = <String, dynamic>{
          // 1. Write content to specific day
          'days.$todayKey': safeDayData,
          'days.$todayKey.title': title, 

          // 2. Set Day Source tracking
          'config.daySources.$todayKey': docId,
          'config.dayPlanTitles.$todayKey': title,

          // 3. ✅ FORCE "DAY MODE"
          'config.horizon': 'day',
          'config.mode': 'day',

          // 4. ✅ REMOVE "WEEK PLAN" OVERRIDES
          // This tells Hub to stop showing the Single Card
          'config.sourceWeekPlanId': FieldValue.delete(),
          'config.title': FieldValue.delete(), 

          'updatedAt': FieldValue.serverTimestamp(),
        };

        await weekRef.update(updates);
      } 
      // ---------------------------------------------------------
      // CASE B: Activate Week Plan (Fix: Switch to Week Mode)
      // ---------------------------------------------------------
      else {
        if (daysData == null) return;

        // Remap keys
        final sourceKeys = daysData.keys.map((e) => e.toString()).toList()..sort();
        final remapped = <String, Map<String, dynamic>>{};

        for (int i = 0; i < horizonKeys.length; i++) {
          final hk = horizonKeys[i];
          if (i >= sourceKeys.length) {
            remapped[hk] = <String, dynamic>{};
            continue;
          }
          final rawDay = daysData[sourceKeys[i]];
          if (rawDay is Map) {
            remapped[hk] = _normalizeForActivation(Map<String, dynamic>.from(rawDay as Map));
          } else {
            remapped[hk] = <String, dynamic>{};
          }
        }

        // We replace the week config to ensure we enter "Week Mode"
        await weekRef.set({
          'days': remapped,
          'config': {
            'title': title,
            'sourceWeekPlanId': docId,
            
            // ✅ FORCE "WEEK MODE"
            'horizon': 'week',
            'mode': 'week',
            'daysToPlan': 7,
            
            // ✅ REMOVE "DAY PLAN" OVERRIDES
            // This ensures we don't have stray day titles
            'daySources': FieldValue.delete(),
            'dayPlanTitles': FieldValue.delete(),

            'updatedAt': FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true));
      }

      await _activeCtrl?.setWeek(currentWeekId);
      await _activeCtrl?.ensureWeek();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan activated!')),
      );
      Navigator.pop(context); // Go back
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error activating: $e')),
      );
    }
  }

  // -------------------------------------------------------
  // DELETE
  // -------------------------------------------------------
  Future<void> _deletePlan(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved plan?'),
        content: const Text(
          'This cannot be undone.\n\n'
          'If this plan is currently used, it will be removed from your current schedule.',
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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final currentWeekId = MealPlanKeys.currentWeekId();

    try {
      final weekRef = _repo.weekDoc(uid: uid, weekId: currentWeekId);
      final weekSnap = await weekRef.get();
      final weekData = weekSnap.data();
      final batch = FirebaseFirestore.instance.batch();

      if (_weekUsesSavedPlan(weekData, docId) && weekData != null) {
        final cfg = weekData['config'] as Map<String, dynamic>? ?? {};
        
        // Detach Week
        if ((cfg['sourceWeekPlanId'] ?? '').toString().trim() == docId) {
          batch.set(weekRef, {'config': {'sourceWeekPlanId': FieldValue.delete()}}, SetOptions(merge: true));
        }

        // Detach Days
        final ds = cfg['daySources'];
        if (ds is Map) {
          final updates = <String, dynamic>{};
          for (final e in ds.entries) {
            if ((e.value ?? '').toString().trim() == docId) {
              updates['config.daySources.${e.key}'] = FieldValue.delete();
              updates['config.dayPlanTitles.${e.key}'] = FieldValue.delete();
              updates['days.${e.key}'] = <String, dynamic>{}; // clear meals
            }
          }
          if (updates.isNotEmpty) batch.update(weekRef, updates);
        }
      }

      final savedRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('savedMealPlans').doc(docId);
      batch.delete(savedRef);
      await batch.commit();

      await _activeCtrl?.setWeek(currentWeekId);
      await _activeCtrl?.ensureWeek();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Log in to view your saved plans')));

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(title: const Text('Created Plans')),
      body: AnimatedBuilder(
        animation: _activeCtrl!,
        builder: (context, _) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('savedMealPlans').orderBy('savedAt', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final allDocs = snap.data?.docs ?? [];
              if (allDocs.isEmpty) return const Center(child: Text('No saved plans yet.', style: TextStyle(color: Colors.grey)));

              QueryDocumentSnapshot<Map<String, dynamic>>? activeDoc;
              final otherDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              for (final doc in allDocs) {
                if (_isPlanActive(doc.data(), doc.id)) activeDoc = doc;
                else otherDocs.add(doc);
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
                      if (isActive && index == 0) _sectionHeader('CURRENTLY ACTIVE', Color(0xFF32998D)),
                      if (!isActive && index == (activeDoc != null ? 1 : 0) && activeDoc != null) ...[
                        const SizedBox(height: 12),
                        _sectionHeader('OTHER PLANS', Colors.grey),
                      ],
                      _SavedPlanCard(
                        data: data,
                        isActive: isActive,
                        onTap: () {
                          if (isActive) Navigator.of(context).push(MaterialPageRoute(builder: (_) => MealPlanScreen(weekId: MealPlanKeys.currentWeekId())));
                          else Navigator.of(context).push(MaterialPageRoute(builder: (_) => SavedMealPlanDetailScreen(savedPlanId: doc.id)));
                        },
                        onActivate: () => _activatePlan(data, doc.id),
                        onDelete: () => _deletePlan(doc.id),
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

  Widget _sectionHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.0)),
      ),
    );
  }
}

class _SavedPlanCard extends StatelessWidget {
  const _SavedPlanCard({required this.data, required this.isActive, required this.onTap, required this.onActivate, required this.onDelete});
  final Map<String, dynamic> data;
  final bool isActive;
  final VoidCallback onTap, onActivate, onDelete;

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return '';
  }

  bool _isDayPlan(Map<String, dynamic> d) {
    final typeRaw = (d['type'] ?? '').toString().trim().toLowerCase();
    if (typeRaw.contains('day')) return true;
    final days = d['days'];
    if (days is Map && days.length == 1) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDay = _isDayPlan(data);
    final title = data['title'] ?? 'Untitled';
    final savedAt = _formatDate(data['savedAt']);
    final flagText = isDay ? 'DAY' : 'WEEK';
    final flagColor = isDay ? Colors.blue.shade50 : Colors.teal.shade50;
    final flagTextColor = isDay ? Colors.blue.shade700 : Colors.teal.shade700;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: isActive ? const BorderSide(color: Color(0xFF32998D), width: 2) : BorderSide.none),
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
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF044246))),
                      const SizedBox(height: 4),
                      Row(children: [
                        Text(isActive ? 'Active Plan' : 'Created $savedAt', style: TextStyle(fontSize: 12, color: isActive ? const Color(0xFF32998D) : Colors.black.withOpacity(0.5), fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                        if (!isActive) ...[
                          const SizedBox(width: 8),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: flagColor, borderRadius: BorderRadius.circular(4)), child: Text(flagText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: flagTextColor))),
                        ],
                      ]),
                    ]),
                  ),
                  if (isActive) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(8)), child: const Row(children: [Icon(Icons.check_circle, size: 16, color: Color(0xFF32998D)), SizedBox(width: 4), Text('ACTIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF32998D)))]))
                ],
              ),
              const Divider(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (!isActive) TextButton.icon(onPressed: onActivate, icon: const Icon(Icons.play_circle_outline, size: 20), label: const Text('Make Active'), style: TextButton.styleFrom(foregroundColor: const Color(0xFF32998D))),
                const Spacer(),
                IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, color: Colors.grey), tooltip: 'Delete'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
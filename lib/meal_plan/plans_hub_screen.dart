import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core/meal_plan_keys.dart';
import 'services/meal_plan_manager.dart';
import 'meal_plan_screen.dart';
import 'builder/meal_plan_builder_screen.dart';
import 'saved_meal_plans_screen.dart';

class PlansHubScreen extends StatefulWidget {
  const PlansHubScreen({super.key});

  @override
  State<PlansHubScreen> createState() => _PlansHubScreenState();
}

class _PlansHubScreenState extends State<PlansHubScreen> {
  static const Color _brandDark = Color(0xFF005A4F);
  static const Color _brandTeal = Color(0xFF32998D);

  // ---------- NAVIGATION ----------

  void _navigateToBuilder({String? dayKey}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanBuilderScreen(
          initialSelectedDayKey: dayKey,
          startAsDayPlan: dayKey != null,
        ),
      ),
    );
  }

  void _openMealPlanWeek() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanScreen(
          weekId: MealPlanKeys.currentWeekId(),
          initialViewMode: MealPlanViewMode.week,
        ),
      ),
    );
  }

  void _openMealPlanForDay(String dayKey) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealPlanScreen(
          weekId: MealPlanKeys.currentWeekId(),
          focusDayKey: dayKey,
          initialViewMode: MealPlanViewMode.today,
        ),
      ),
    );
  }

  void _openSavedPlansList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedMealPlansScreen()),
    );
  }

  // ---------- ACTIONS ----------

  Future<void> _onRemoveWeekPressed() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear entire week?"),
        content: const Text("This will remove all plans currently scheduled for this week."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("Clear All", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MealPlanManager().removeActiveWeekPlan(MealPlanKeys.currentWeekId());
    }
  }

  Future<void> _removeDayPlan(String dayKey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove this day plan?"),
        content: Text("Clear the meals for ${MealPlanKeys.formatPretty(dayKey)}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("Remove", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MealPlanManager().removeDayFromWeek(
        weekId: MealPlanKeys.currentWeekId(), 
        dayKey: dayKey
      );
    }
  }

  Future<void> _nukeCurrentWeek() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("NUKE WEEK (DEBUG)"),
        content: const Text("Delete active week document? Use to fix ghost states."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("DELETE", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('mealPlansWeeks')
        .doc(MealPlanKeys.currentWeekId())
        .delete();
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Please log in')));

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        title: const Text('Meal Planner'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: const TextStyle(color: _brandDark, fontWeight: FontWeight.bold, fontSize: 20),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: _brandDark),
            tooltip: 'Saved Plans',
            onPressed: _openSavedPlansList,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            tooltip: 'NUKE WEEK',
            onPressed: _nukeCurrentWeek,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users').doc(user.uid)
            .collection('mealPlansWeeks').doc(MealPlanKeys.currentWeekId())
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 1. If document doesn't exist -> Show Empty State
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _NoActivePlanView(
              onTapCreate: () => _navigateToBuilder(),
              onTapViewAll: _openSavedPlansList,
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final daysMap = data['days'] as Map<String, dynamic>? ?? {};

          // 2. ✅ FIX: If document exists but HAS NO FOOD -> Show Empty State
          // (This prevents showing 7 empty slots)
          bool hasAnyFood = false;
          if (daysMap.isNotEmpty) {
            for (final v in daysMap.values) {
              if (v is Map && v.isNotEmpty) {
                hasAnyFood = true;
                break;
              }
            }
          }

          if (!hasAnyFood) {
             return _NoActivePlanView(
              onTapCreate: () => _navigateToBuilder(),
              onTapViewAll: _openSavedPlansList,
            );
          }

          // 3. Otherwise show the plan
          final config = data['config'] as Map<String, dynamic>? ?? {};
          String mode = config['horizon'] ?? config['mode'] ?? config['activeMode'] ?? 'week';

          if (mode == 'day') {
            return _buildDayByDayList(data);
          } else {
            return _buildWeeklyCardView(data);
          }
        },
      ),
    );
  }

  // ---------- VIEW 1: WEEKLY CARD ----------

  Widget _buildWeeklyCardView(Map<String, dynamic> data) {
    final String title = data['config']?['title'] ?? 'Weekly Meal Plan';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        const Text('THIS WEEK’S PLAN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _brandDark)),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _brandTeal, width: 2)),
          child: ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            subtitle: const Text('Active for the full week'),
            trailing: const Icon(Icons.chevron_right, color: _brandTeal),
            onTap: _openMealPlanWeek,
          ),
        ),
        const SizedBox(height: 24),
        _RemoveButton(label: 'Clear Entire Week', onPressed: _onRemoveWeekPressed),
        
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _openSavedPlansList,
            child: const Text("View All Saved Plans", style: TextStyle(color: _brandTeal, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // ---------- VIEW 2: 7 DAY SLOTS ----------

  Widget _buildDayByDayList(Map<String, dynamic> data) {
    final daysMap = data['days'] as Map<String, dynamic>? ?? {};
    final config = data['config'] as Map<String, dynamic>? ?? {};
    final weekKeys = MealPlanKeys.weekDayKeys(MealPlanKeys.currentWeekId());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      children: [
        const Text('YOUR WEEKLY SCHEDULE', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _brandDark)),
        const SizedBox(height: 16),

        ...weekKeys.map((dayKey) {
          final dayData = daysMap[dayKey];
          bool isActive = dayData != null && dayData.isNotEmpty;

          String displayTitle = config['title']?.toString() ?? "Active Plan"; 

          if (isActive) {
            if (dayData is Map && dayData['title'] != null && dayData['title'].toString().isNotEmpty) {
              displayTitle = dayData['title'].toString();
            } 
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: isActive ? 2 : 0,
            color: isActive ? Colors.white : Colors.white.withOpacity(0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isActive ? _brandTeal : Colors.grey.shade300, width: isActive ? 1.5 : 1),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(
                MealPlanKeys.formatPretty(dayKey),
                style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
              ),
              subtitle: Text(
                isActive ? displayTitle : "No plan set - tap to create", 
                style: TextStyle(
                  color: isActive ? _brandTeal : Colors.grey, 
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal
                ),
              ),
              trailing: isActive 
                ? PopupMenuButton<String>(
                    onSelected: (v) => v == 'remove' ? _removeDayPlan(dayKey) : _openMealPlanForDay(dayKey),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'view', child: Text("View/Edit Day")),
                      const PopupMenuItem(value: 'remove', child: Text("Remove Day Plan", style: TextStyle(color: Colors.red))),
                    ],
                    icon: const Icon(Icons.more_vert, color: _brandTeal),
                  )
                : const Icon(Icons.add_circle_outline, color: _brandTeal),
              onTap: () {
                if (isActive) {
                  _openMealPlanForDay(dayKey);
                } else {
                  _navigateToBuilder(dayKey: dayKey);
                }
              },
            ),
          );
        }),
        const SizedBox(height: 12),
        _RemoveButton(label: 'Clear All Active Days', onPressed: _onRemoveWeekPressed),

        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _openSavedPlansList,
            child: const Text("View All Saved Plans", style: TextStyle(color: _brandTeal, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}

// ---------- UI HELPERS ----------

class _RemoveButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _RemoveButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
        label: Text(label, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _NoActivePlanView extends StatelessWidget {
  final VoidCallback onTapCreate;
  final VoidCallback onTapViewAll; 

  const _NoActivePlanView({
    required this.onTapCreate,
    required this.onTapViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.restaurant_menu, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              "No Active Meal Plan", 
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)
            ),
            const SizedBox(height: 8),
            const Text(
              "Your schedule is empty for this week.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            
            // OPTION 1: CREATE
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: onTapCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF32998D),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                child: const Text('CREATE NEW PLAN', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            
            const SizedBox(height: 16),
            const Text("— OR —", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),

            // OPTION 2: ADD
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: onTapViewAll,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF32998D),
                  side: const BorderSide(color: Color(0xFF32998D), width: 2),
                  shape: const StadiumBorder(),
                ),
                child: const Text("ADD FROM SAVED PLANS", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// lib/meal_plan/saved_meal_plan_detail_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_repository.dart';
import 'core/meal_plan_keys.dart';
import 'core/meal_plan_repository.dart';

class SavedMealPlanDetailScreen extends StatefulWidget {
  final String savedPlanId;

  const SavedMealPlanDetailScreen({
    super.key,
    required this.savedPlanId,
  });

  @override
  State<SavedMealPlanDetailScreen> createState() => _SavedMealPlanDetailScreenState();
}

class _SavedMealPlanDetailScreenState extends State<SavedMealPlanDetailScreen> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>> _recipes = [];

  // ✅ New world pointers
  Map<String, dynamic>? _currentActiveWeekConfig;
  String? _activeRecurringWeekPlanId;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _planSub;

  late final MealPlanRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = MealPlanRepository(FirebaseFirestore.instance);
    _load();
  }

  @override
  void dispose() {
    _planSub?.cancel();
    super.dispose();
  }

  String? _uid() => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _savedPlanRef(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('savedMealPlans').doc(widget.savedPlanId);
  }

  void _startSavedPlanListener(String uid) {
    _planSub?.cancel();
    _planSub = _savedPlanRef(uid).snapshots().listen((snap) {
      final data = snap.data();
      if (!mounted) return;

      if (data == null) {
        setState(() {
          _plan = null;
          _error = 'Saved plan not found.';
        });
        return;
      }

      setState(() => _plan = data);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = _uid();
      if (uid == null) throw Exception('Not logged in');

      _startSavedPlanListener(uid);

      final savedSnap = await _savedPlanRef(uid).get(const GetOptions(source: Source.serverAndCache));
      final data = savedSnap.data();
      if (data == null) throw Exception('Saved plan not found.');

      final currentWeekId = MealPlanKeys.currentWeekId();
      final weekSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('mealPlansWeeks')
          .doc(currentWeekId)
          .get();
      final weekConfig = weekSnap.data()?['config'] as Map<String, dynamic>?;

      final recurringId = await _repo.getActiveRecurringWeekPlanId(uid: uid);

      List<Map<String, dynamic>> recipes = [];
      try {
        recipes = await RecipeRepository.ensureRecipesLoaded();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _plan = data;
        _recipes = recipes;
        _currentActiveWeekConfig = weekConfig;
        _activeRecurringWeekPlanId = recurringId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ----------------------------
  // Plan type
  // ----------------------------
  bool get _isDayPlan {
    final plan = _plan;
    if (plan == null) return false;

    final planType = (plan['planType'] ?? plan['type'] ?? '').toString().trim().toLowerCase();
    if (planType == 'day') return true;
    if (planType == 'week') return false;

    if (plan['day'] is Map) return true;
    final days = plan['days'];
    if (days is Map && days.length == 1) return true;

    return false;
  }

  bool get _recurringEnabled => (_plan?['recurringEnabled'] == true);

  bool get _isRecurringTemplate {
    if (_isDayPlan) return false;
    return (_activeRecurringWeekPlanId ?? '') == widget.savedPlanId;
  }

  bool get _isActiveInCurrentWeek {
    final cfg = _currentActiveWeekConfig;
    if (cfg == null) return false;

    final weekId = (cfg['sourceWeekPlanId'] ?? '').toString().trim();
    if (weekId.isNotEmpty && weekId == widget.savedPlanId) return true;

    final ds = cfg['daySources'];
    if (ds is Map) {
      for (final v in ds.values) {
        if ((v ?? '').toString().trim() == widget.savedPlanId) return true;
      }
    }

    final legacy = (cfg['sourcePlanId'] ?? '').toString().trim();
    if (legacy.isNotEmpty && legacy == widget.savedPlanId) return true;

    return false;
  }

  String _planTitle() {
    final s = (_plan?['title'] ?? '').toString().trim();
    return s.isNotEmpty ? s : 'Meal plan';
  }

  // ----------------------------
  // Normalization
  // ----------------------------
  Map<String, dynamic> _normalizeForActivation(Map<String, dynamic> rawDayData) {
    final processed = <String, dynamic>{};
    processed.addAll(rawDayData);

    for (final slot in ['breakfast', 'lunch', 'dinner', 'snack1', 'snack2']) {
      if (rawDayData[slot] is Map) {
        final entry = Map<String, dynamic>.from(rawDayData[slot]);
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

  // ----------------------------
  // Activate (kept simple)
  // ----------------------------
  Future<void> _usePlan() async {
    if (_isActiveInCurrentWeek) return;
    final plan = _plan!;
    final uid = _uid();
    if (uid == null) return;

    Map<String, dynamic>? dayData;
    Map<String, dynamic>? daysData;

    if (_isDayPlan) {
      if (plan['day'] is Map) {
        dayData = Map<String, dynamic>.from(plan['day']);
      } else if (plan['days'] is Map) {
        final map = Map<String, dynamic>.from(plan['days'] as Map);
        if (map.isNotEmpty) {
          final first = map.values.first;
          if (first is Map) dayData = Map<String, dynamic>.from(first as Map);
        }
      }
    } else {
      if (plan['days'] is Map) {
        daysData = Map<String, dynamic>.from(plan['days'] as Map);
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Activate Plan?'),
        content: Text(
          _isDayPlan ? "This will replace your meal plan for TODAY." : "This will replace your current weekly schedule.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Activate')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final currentWeekId = MealPlanKeys.currentWeekId();
      final weekRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('mealPlansWeeks').doc(currentWeekId);

      await _repo.ensureWeekExists(uid: uid, weekId: currentWeekId);

      if (_isDayPlan && dayData != null) {
        final title = _planTitle();
        final todayKey = MealPlanKeys.todayKey();
        final safeDayData = _normalizeForActivation(dayData);

        await weekRef.update({
          'days.$todayKey': safeDayData,
          'days.$todayKey.title': title,
          'config.daySources.$todayKey': widget.savedPlanId,
          'config.dayPlanTitles.$todayKey': title,
          'config.horizon': 'day',
          'config.mode': 'day',
          'config.sourceWeekPlanId': FieldValue.delete(),
          'config.title': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (daysData != null) {
        final title = _planTitle();
        final targetDateKeys = MealPlanKeys.weekDayKeys(currentWeekId);

        final sourceKeys = daysData.keys.map((e) => e.toString()).toList()..sort();
        final remapped = <String, Map<String, dynamic>>{};

        for (int i = 0; i < targetDateKeys.length; i++) {
          final k = targetDateKeys[i];
          if (i >= sourceKeys.length) {
            remapped[k] = <String, dynamic>{};
            continue;
          }
          final raw = daysData[sourceKeys[i]];
          if (raw is Map) {
            remapped[k] = _normalizeForActivation(Map<String, dynamic>.from(raw as Map));
          } else {
            remapped[k] = <String, dynamic>{};
          }
        }

        await weekRef.set({
          'days': remapped,
          'config': {
            'title': title,
            'sourceWeekPlanId': widget.savedPlanId,
            'horizon': 'week',
            'mode': 'week',
            'daysToPlan': 7,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await weekRef.update({
          'config.daySources': FieldValue.delete(),
          'config.dayPlanTitles': FieldValue.delete(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan Activated!')));

      // ✅ refresh active week config (NO duplicate currentWeekId)
      final weekSnap = await weekRef.get();
      if (!mounted) return;
      setState(() => _currentActiveWeekConfig = weekSnap.data()?['config'] as Map<String, dynamic>?);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ----------------------------
  // ✅ Recurring controls
  // ----------------------------
  List<int> _readRecurringWeekdays() {
    final raw = _plan?['recurringWeekdays'];
    if (raw is List) {
      return raw
          .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
          .where((e) => e >= 1 && e <= 7)
          .toSet()
          .toList()
        ..sort();
    }
    return <int>[];
  }

  Future<void> _setRecurringDayPlan({
    required bool enabled,
    required List<int> weekdays,
  }) async {
    final uid = _uid();
    if (uid == null) return;

    final clean = weekdays.where((e) => e >= 1 && e <= 7).toSet().toList()..sort();
    if (enabled && clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one weekday.')));
      return;
    }

    try {
      await _repo.setSavedPlanRecurring(
        uid: uid,
        planId: widget.savedPlanId,
        enabled: enabled,
        planType: 'day',
        weekAnchorDateKey: null,
        weekdays: enabled ? clean : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enabled ? 'Recurring enabled' : 'Recurring disabled')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _setRecurringWeekTemplate({required bool enabled}) async {
    final uid = _uid();
    if (uid == null) return;

    try {
      await _repo.setSavedPlanRecurring(
        uid: uid,
        planId: widget.savedPlanId,
        enabled: enabled,
        planType: 'week',
        weekAnchorDateKey: (_plan?['recurringWeekAnchorDate'] ?? MealPlanKeys.todayKey()).toString(),
        weekdays: null,
      );

      await _repo.setActiveRecurringWeekPlanId(uid: uid, planId: enabled ? widget.savedPlanId : null);

      final recurringId = await _repo.getActiveRecurringWeekPlanId(uid: uid);
      if (!mounted) return;
      setState(() => _activeRecurringWeekPlanId = recurringId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enabled ? 'Template enabled' : 'Template disabled')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ----------------------------
  // Delete (safe with recurring template)
  // ----------------------------
  Future<void> _deletePlan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Plan?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final uid = _uid();
    if (uid == null) return;

    final fs = FirebaseFirestore.instance;
    final currentWeekId = MealPlanKeys.currentWeekId();
    final todayKey = MealPlanKeys.todayKey();

    try {
      // If this is the active recurring template, clear pointer first
      if (!_isDayPlan && _isRecurringTemplate) {
        await _repo.setActiveRecurringWeekPlanId(uid: uid, planId: null);
      }

      _planSub?.cancel();
      _planSub = null;

      final batch = fs.batch();

      final savedRef = fs.collection('users').doc(uid).collection('savedMealPlans').doc(widget.savedPlanId);
      final weekRef = fs.collection('users').doc(uid).collection('mealPlansWeeks').doc(currentWeekId);

      // delete saved plan doc
      batch.delete(savedRef);

      // if current week uses it, detach cleanly
      final weekSnap = await weekRef.get();
      final cfg = weekSnap.data()?['config'] as Map<String, dynamic>?;

      bool weekUsesIt = false;
      if (cfg != null) {
        final sw = (cfg['sourceWeekPlanId'] ?? '').toString().trim();
        if (sw == widget.savedPlanId) weekUsesIt = true;

        final ds = cfg['daySources'];
        if (!weekUsesIt && ds is Map) {
          for (final v in ds.values) {
            if ((v ?? '').toString().trim() == widget.savedPlanId) {
              weekUsesIt = true;
              break;
            }
          }
        }
      }

      if (weekUsesIt) {
        if (_isDayPlan) {
          batch.set(
            weekRef,
            {
              'config': {
                'daySources': FieldValue.delete(),
                'dayPlanTitles': FieldValue.delete(),
              },
              'days': {todayKey: <String, dynamic>{}},
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } else {
          // detach week plan pointer but don’t nuke whole doc structure
          batch.set(
            weekRef,
            {
              'config': {
                'sourceWeekPlanId': FieldValue.delete(),
                'title': FieldValue.delete(),
              },
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      // reattach listener on failure
      final uid2 = _uid();
      if (uid2 != null) _startSavedPlanListener(uid2);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // ----------------------------
  // UI helpers
  // ----------------------------
  int? _recipeIdFrom(Map r) {
    final raw = r['id'] ?? r['recipeId'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  String _decodeHtmlLite(String s) {
    return s.replaceAll('&#038;', '&').replaceAll('&amp;', '&');
  }

  String _getRecipeTitle(int id) {
    final r = _recipes.firstWhere((e) => _recipeIdFrom(e) == id, orElse: () => {});
    if (r.isNotEmpty && r['title'] is Map) {
      final t = r['title']['rendered']?.toString() ?? 'Recipe #$id';
      return _decodeHtmlLite(t);
    }
    return 'Recipe #$id';
  }

  String? _getRecipeImage(int id) {
    final r = _recipes.firstWhere((e) => _recipeIdFrom(e) == id, orElse: () => {});
    if (r.isNotEmpty && r['recipe'] is Map) {
      return r['recipe']['image_url']?.toString();
    }
    return null;
  }

  Widget _buildSlot(String slotName, dynamic entry) {
    if (entry is! Map) return const SizedBox.shrink();
    final type = entry['kind'] ?? entry['type'];
    if (type == 'clear') return const SizedBox.shrink();

    String title = 'Item';
    String? img;

    if (type == 'recipe' || entry.containsKey('id') || entry.containsKey('recipeId')) {
      final rid = _recipeIdFrom(entry);
      if (rid != null) {
        title = _getRecipeTitle(rid);
        img = _getRecipeImage(rid);
      }
    } else if (type == 'note') {
      title = (entry['text'] ?? 'Note').toString();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
              image: img != null ? DecorationImage(image: NetworkImage(img), fit: BoxFit.cover) : null,
            ),
            child: img == null ? const Icon(Icons.restaurant, size: 20, color: Colors.grey) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                slotName.toUpperCase(),
                style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ]),
          )
        ],
      ),
    );
  }

  Widget _buildDaySection(String label, Map data) {
    final slots = ['breakfast', 'lunch', 'dinner', 'snack1', 'snack2'];
    final hasData = slots.any((s) => data[s] != null);
    if (!hasData) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ...slots.map((s) => _buildSlot(s, data[s])),
      ],
    );
  }

  String _weekdayLabel(int w) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(), body: Center(child: Text(_error!)));
    if (_plan == null) {
      return const Scaffold(body: Center(child: Text('Saved plan not found.')));
    }

    final plan = _plan!;
    final title = _planTitle();
    final isActive = _isActiveInCurrentWeek;

    bool isDay = _isDayPlan;

    // day/week content
    dynamic dayData;
    Map? weekDays;
    if (isDay) {
      dayData = plan['day'] ?? (plan['days'] is Map ? (plan['days'] as Map).values.first : null);
    } else {
      weekDays = (plan['days'] is Map) ? (plan['days'] as Map) : null;
    }

    final currentWeekLabel = isActive ? 'Used in current week' : 'Not used in current week';
    final recurringLabel = isDay
        ? (_recurringEnabled ? 'Recurring day plan' : 'One-off day plan')
        : (_isRecurringTemplate ? 'Recurring week template' : (_recurringEnabled ? 'Recurring (not template)' : 'One-off week plan'));

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deletePlan),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(16),
              border: isActive ? Border.all(color: const Color(0xFF32998D), width: 2) : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      isActive ? 'Currently Active' : 'Not Active',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isActive ? const Color(0xFF32998D) : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$currentWeekLabel • $recurringLabel',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withOpacity(0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
                ElevatedButton(
                  onPressed: isActive ? null : _usePlan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF32998D),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor: const Color(0xFF32998D),
                    elevation: isActive ? 0 : 2,
                  ),
                  child: Text(isActive ? 'ACTIVE' : 'ACTIVATE'),
                )
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ✅ Recurring controls
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Recurring', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const SizedBox(height: 10),

              if (isDay) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Make this plan recurring', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Choose which weekdays it repeats on.'),
                  value: _recurringEnabled,
                  onChanged: (v) async {
                    final currentDays = _readRecurringWeekdays();
                    final fallback = currentDays.isNotEmpty ? currentDays : <int>[DateTime.now().weekday];
                    await _setRecurringDayPlan(enabled: v, weekdays: v ? fallback : <int>[]);
                  },
                ),
                if (_recurringEnabled) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (i) {
                      final w = i + 1;
                      final selected = _readRecurringWeekdays().contains(w);
                      return InkWell(
                        onTap: () async {
                          final current = _readRecurringWeekdays().toSet();
                          if (selected) {
                            current.remove(w);
                          } else {
                            current.add(w);
                          }
                          await _setRecurringDayPlan(enabled: true, weekdays: current.toList());
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF044246) : const Color(0xFFF3F6F6),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: selected ? const Color(0xFF044246) : Colors.black.withOpacity(0.10),
                            ),
                          ),
                          child: Text(
                            _weekdayLabel(w),
                            style: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF044246),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This plan will be suggested/applied on these days when the week is empty.',
                    style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w600),
                  ),
                ],
              ] else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use as recurring week template', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('This week plan becomes the default template for future weeks.'),
                  value: _isRecurringTemplate,
                  onChanged: (v) async => _setRecurringWeekTemplate(enabled: v),
                ),
              ],
            ]),
          ),

          const SizedBox(height: 20),

          // Content
          if (isDay) ...[
            if (dayData is Map)
              _buildDaySection("Plan Items", dayData)
            else
              const Center(child: Text("No meals found in this plan.")),
          ] else ...[
            if (weekDays is Map) ...[
              Builder(builder: (ctx) {
                final keys = weekDays!.keys.toList()..sort();
                return Column(
                  children: keys.map((k) {
                    String label = "Day $k";
                    final dt = MealPlanKeys.parseDayKey(k.toString());
                    if (dt != null) {
                      label = "${dt.day}/${dt.month} (${_weekdayLabel(dt.weekday)})";
                    } else if (int.tryParse(k.toString()) != null) {
                      label = "Day ${int.parse(k.toString()) + 1}";
                    }

                    final val = weekDays![k];
                    if (val is! Map) return const SizedBox.shrink();
                    return _buildDaySection(label, val);
                  }).toList(),
                );
              }),
            ] else ...[
              const Center(child: Text("No meals found in this plan.")),
            ]
          ],
        ],
      ),
    );
  }
}

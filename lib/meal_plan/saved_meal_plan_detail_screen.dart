import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_repository.dart';
import 'core/meal_plan_keys.dart';

class SavedMealPlanDetailScreen extends StatefulWidget {
  final String savedPlanId;

  const SavedMealPlanDetailScreen({
    super.key,
    required this.savedPlanId,
  });

  @override
  State<SavedMealPlanDetailScreen> createState() =>
      _SavedMealPlanDetailScreenState();
}

class _SavedMealPlanDetailScreenState extends State<SavedMealPlanDetailScreen> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>> _recipes = [];

  String? _activeSavedMealPlanId;
  Map<String, dynamic>? _currentActiveWeekConfig;

  // ✅ live listener so title updates immediately
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _planSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _planSub?.cancel();
    super.dispose();
  }

  String? _uid() => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _savedPlanRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedMealPlans')
        .doc(widget.savedPlanId);
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

      setState(() {
        _plan = data;
      });
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

      // ✅ Start live listener immediately (so title updates)
      _startSavedPlanListener(uid);

      // 1) Load saved plan once (for initial render)
      final savedSnap =
          await _savedPlanRef(uid).get(const GetOptions(source: Source.serverAndCache));
      final data = savedSnap.data();
      if (data == null) throw Exception('Saved plan not found.');

      // 2) Load user profile (active plan id)
      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userSnap.data() ?? {};
      final activeId = userData['activeSavedMealPlanId']?.toString();

      // 3) Load current active schedule (week config)
      final currentWeekId = MealPlanKeys.currentWeekId();
      final weekSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('mealPlansWeeks')
          .doc(currentWeekId)
          .get();
      final weekConfig = weekSnap.data()?['config'] as Map<String, dynamic>?;

      // 4) Load recipes
      List<Map<String, dynamic>> recipes = [];
      try {
        recipes = await RecipeRepository.ensureRecipesLoaded();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _plan = data;
        _recipes = recipes;
        _activeSavedMealPlanId = activeId;
        _currentActiveWeekConfig = weekConfig;
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

  bool get _isActive {
    if (_activeSavedMealPlanId == widget.savedPlanId) return true;
    if (_currentActiveWeekConfig != null) {
      final sourceId = _currentActiveWeekConfig!['sourcePlanId'];
      if (sourceId.toString() == widget.savedPlanId) return true;
    }
    return false;
  }

  String _planTitle() {
    final s = (_plan?['title'] ?? '').toString().trim();
    return s.isNotEmpty ? s : 'Meal plan';
  }

  // ----------------------------
  // ✅ DATA NORMALIZATION (YOUR EXISTING FIX)
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

  Future<void> _usePlan() async {
    if (_isActive) return;

    final plan = _plan!;
    Map<String, dynamic>? dayData;
    Map<String, dynamic>? daysData;
    bool isDayPlan = false;

    if (plan['day'] is Map) {
      isDayPlan = true;
      dayData = Map<String, dynamic>.from(plan['day']);
    } else if (plan['days'] is Map) {
      final map = plan['days'] as Map<String, dynamic>;
      if (map.length == 1) {
        isDayPlan = true;
        dayData = Map<String, dynamic>.from(map.values.first);
      } else {
        daysData = map;
      }
    }

    if (isDayPlan && dayData != null) {
      if (dayData.containsKey('day') && dayData['day'] is Map) {
        dayData = Map<String, dynamic>.from(dayData['day']);
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Activate Plan?'),
        content: Text(
          isDayPlan
              ? "This will replace your meal plan for TODAY."
              : "This will replace your current weekly schedule.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activate'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final uid = _uid();
      if (uid == null) throw Exception('Not logged in');

      final currentWeekId = MealPlanKeys.currentWeekId();
      final batch = FirebaseFirestore.instance.batch();

      final weekRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('mealPlansWeeks')
          .doc(currentWeekId);

      final todayKey = MealPlanKeys.todayKey();
      final targetDateKeys = MealPlanKeys.weekDayKeys(currentWeekId);

      if (isDayPlan && dayData != null) {
        final safeDayData = _normalizeForActivation(dayData);

        batch.set(
          weekRef,
          {
            'uid': uid,
            'weekId': currentWeekId,
            'days': {todayKey: safeDayData},
            'config': {
              'sourcePlanId': widget.savedPlanId,
              'updatedAt': FieldValue.serverTimestamp(),
              'daysToPlan': 1,
              'startDate': todayKey,
            }
          },
          SetOptions(merge: true),
        );
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

        batch.set(
          weekRef,
          {
            'uid': uid,
            'weekId': currentWeekId,
            'days': remapped,
            'config': {
              'sourcePlanId': widget.savedPlanId,
              'updatedAt': FieldValue.serverTimestamp(),
              'daysToPlan': 7,
              'startDate': targetDateKeys.first,
            }
          },
          SetOptions(merge: true),
        );
      }

      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      batch.set(
        userRef,
        {'activeSavedMealPlanId': widget.savedPlanId},
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;

      setState(() {
        _activeSavedMealPlanId = widget.savedPlanId;
        _currentActiveWeekConfig = {'sourcePlanId': widget.savedPlanId};
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Plan Activated!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// ✅ FULL DELETE (prevents ghost plans):
  /// - delete savedMealPlans/{id}
  /// - if active: clear users.activeSavedMealPlanId
  /// - if current week points at it: detach config.sourcePlanId
  /// - clear schedule days (today only for day-plan; whole week for week-plan)
  /// - pop back to root (Home)
  Future<void> _deletePlan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Plan?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
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

    // Determine day vs week using loaded plan (fallback to week if unknown)
    final plan = _plan;
    bool isDayPlan = false;
    if (plan != null) {
      if (plan['day'] is Map) {
        isDayPlan = true;
      } else if (plan['days'] is Map) {
        final map = plan['days'] as Map;
        if (map.length == 1) isDayPlan = true;
      }
    }

    try {
      // stop listener so it doesn't flash "not found" mid-delete
      _planSub?.cancel();
      _planSub = null;

      final batch = fs.batch();

      final savedRef = fs
          .collection('users')
          .doc(uid)
          .collection('savedMealPlans')
          .doc(widget.savedPlanId);

      final userRef = fs.collection('users').doc(uid);

      final weekRef = fs
          .collection('users')
          .doc(uid)
          .collection('mealPlansWeeks')
          .doc(currentWeekId);

      // 1) Delete the saved plan doc
      batch.delete(savedRef);

      // 2) If user points to it as active, clear pointer
      if ((_activeSavedMealPlanId ?? '') == widget.savedPlanId) {
        batch.set(
          userRef,
          {'activeSavedMealPlanId': FieldValue.delete()},
          SetOptions(merge: true),
        );
      }

      // 3) If week config points to it, detach + clear schedule
      final weekSourceId = _currentActiveWeekConfig?['sourcePlanId']?.toString();
      if ((weekSourceId ?? '') == widget.savedPlanId) {
        if (isDayPlan) {
          // Clear only today (day plan)
          batch.set(
            weekRef,
            {
              'config': {'sourcePlanId': FieldValue.delete()},
              'days': {todayKey: FieldValue.delete()},
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } else {
          // Clear whole week plan
          batch.set(
            weekRef,
            {
              'config': FieldValue.delete(),
              'days': <String, dynamic>{},
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }

      await batch.commit();

      if (!mounted) return;

      // ✅ go back to home so hub refreshes cleanly
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      // reattach listener on failure
      final uid2 = _uid();
      if (uid2 != null) _startSavedPlanListener(uid2);

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // ----------------------------
  // Widget Builders
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
              image: img != null
                  ? DecorationImage(image: NetworkImage(img), fit: BoxFit.cover)
                  : null,
            ),
            child: img == null
                ? const Icon(Icons.restaurant, size: 20, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  slotName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
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
            child: Text(
              label,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ...slots.map((s) => _buildSlot(s, data[s])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(_error!)));
    }
    if (_plan == null) {
      return const Scaffold(
        body: Center(child: Text('Saved plan not found.')),
      );
    }

    final plan = _plan!;
    final title = _planTitle();
    final isActive = _isActive;

    bool isDay = false;
    if (plan['day'] is Map) {
      isDay = true;
    } else if (plan['days'] is Map) {
      final map = plan['days'] as Map;
      if (map.length == 1) isDay = true;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deletePlan,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(16),
              border: isActive
                  ? Border.all(color: const Color(0xFF32998D), width: 2)
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isActive ? 'Currently Active' : 'Not Active',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? const Color(0xFF32998D)
                          : Colors.grey[700],
                    ),
                  ),
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
          const SizedBox(height: 20),
          Builder(builder: (ctx) {
            if (isDay) {
              final dayData = plan['day'] ?? (plan['days'] as Map?)?.values.first;
              if (dayData is! Map) {
                return const Center(child: Text("No meals found in this plan."));
              }
              return _buildDaySection("Plan Items", dayData);
            } else {
              final days = plan['days'];
              if (days is! Map) {
                return const Center(child: Text("No meals found in this plan."));
              }

              final keys = days.keys.toList()..sort();
              return Column(
                children: keys.map((k) {
                  String label = "Day $k";
                  final dt = MealPlanKeys.parseDayKey(k.toString());
                  if (dt != null) {
                    label = "${dt.day}/${dt.month} (${_dayName(dt.weekday)})";
                  } else if (int.tryParse(k.toString()) != null) {
                    label = "Day ${int.parse(k.toString()) + 1}";
                  }

                  return _buildDaySection(label, days[k]);
                }).toList(),
              );
            }
          })
        ],
      ),
    );
  }

  String _dayName(int w) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];
}

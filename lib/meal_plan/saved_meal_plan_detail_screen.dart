import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_detail_screen.dart';
import '../recipes/recipe_repository.dart';

import 'core/meal_plan_keys.dart';
import 'core/meal_plan_slots.dart';

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

  Map<String, dynamic>? _plan; // saved plan doc data
  List<Map<String, dynamic>> _recipes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DocumentReference<Map<String, dynamic>>? _savedDoc() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .collection('savedMealPlans')
        .doc(widget.savedPlanId);
  }

  DocumentReference<Map<String, dynamic>>? _activeWeekDoc(String weekId) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .collection('mealPlansWeeks')
        .doc(weekId);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final doc = _savedDoc();
      if (doc == null) {
        setState(() {
          _error = 'Not logged in.';
          _loading = false;
        });
        return;
      }

      final snap = await doc.get();
      final data = snap.data();
      if (data == null) {
        setState(() {
          _error = 'Saved plan not found.';
          _loading = false;
        });
        return;
      }

      // Load recipes for title/thumb lookup
      List<Map<String, dynamic>> recipes;
      try {
        recipes = await RecipeRepository.ensureRecipesLoaded();
      } catch (_) {
        recipes = [];
      }

      if (!mounted) return;
      setState(() {
        _plan = data;
        _recipes = recipes;
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

  int? _recipeIdFrom(Map<String, dynamic> r) {
    final raw = r['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return int.tryParse(raw?.toString() ?? '');
  }

  Map<String, dynamic>? _byId(int? id) {
    if (id == null) return null;
    for (final r in _recipes) {
      final rid = _recipeIdFrom(r);
      if (rid == id) return r;
    }
    return null;
  }

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && (t['rendered'] is String)) {
      final s = (t['rendered'] as String).trim();
      if (s.isNotEmpty) return s;
    }
    return 'Untitled';
  }

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.trim().isNotEmpty) return url.trim();
    }
    return null;
  }

  String _prettyDayKey(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return dayKey;

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    final weekday = weekdays[dt.weekday - 1];
    final mon = months[dt.month - 1];
    return '$weekday, ${dt.day} $mon';
  }

  // Saved plan entry parsing (kept flexible)
  bool _entryIsRecipe(dynamic entry) {
    if (entry is Map) {
      final kind = entry['kind']?.toString();
      return kind == 'recipe' || entry.containsKey('recipeId');
    }
    return false;
  }

  int? _entryRecipeId(dynamic entry) {
    if (entry is! Map) return null;
    final raw = entry['recipeId'] ?? entry['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  String? _entryNoteText(dynamic entry) {
    if (entry is! Map) return null;
    final kind = entry['kind']?.toString();
    if (kind == 'note') {
      final t = entry['text'] ?? entry['note'] ?? entry['value'];
      final s = (t ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }
    final t = entry['text'];
    final s = (t ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  // ----------------------------
  // USE (apply saved -> active plan)
  // Day plan: replace today only
  // Week plan: replace from today -> end of week (maps saved days in order)
  // ----------------------------

  Future<bool> _confirmUse() async {
    final plan = _plan ?? {};
    final type = (plan['type'] ?? 'week').toString(); // 'week' | 'day'

    final msg = type == 'day'
        ? "This will replace today's meal plan."
        : "This will replace your meal plan for the rest of this week (starting today).";

    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Use this plan?'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Use plan'),
              ),
            ],
          ),
        )) ??
        false;
  }

  Map<String, dynamic> _remapSavedWeekDaysFromToday(Map savedDays) {
    final todayKey = MealPlanKeys.todayKey();
    final currentWeekId = MealPlanKeys.currentWeekId();

    final targetKeys = MealPlanKeys.weekDayKeys(currentWeekId);
    final startIndex = targetKeys.indexOf(todayKey);
    final start = startIndex >= 0 ? startIndex : (DateTime.now().weekday - 1);

    final sourceKeys = savedDays.keys.map((k) => k.toString()).toList()..sort();

    final out = <String, dynamic>{};

    int src = 0;
    for (int i = start; i < targetKeys.length; i++) {
      if (src >= sourceKeys.length) break;

      final srcKey = sourceKeys[src];
      final srcDay = savedDays[srcKey];

      if (srcDay is Map) {
        out[targetKeys[i]] = srcDay;
      }

      src += 1;
    }

    return out;
  }

  Future<void> _usePlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final plan = _plan;
    if (plan == null) return;

    final ok = await _confirmUse();
    if (!ok) return;

    final type = (plan['type'] ?? 'week').toString(); // 'week' | 'day'
    final currentWeekId = MealPlanKeys.currentWeekId();
    final activeDoc = _activeWeekDoc(currentWeekId);
    if (activeDoc == null) return;

    try {
      final batch = FirebaseFirestore.instance.batch();

      if (type == 'day') {
        // ✅ Replace TODAY only
        final todayKey = MealPlanKeys.todayKey();
        final day = plan['day'];

        if (day is Map) {
          batch.set(
            activeDoc,
            {
              'days': {todayKey: day},
              'appliedFromSavedPlanId': widget.savedPlanId,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      } else {
        // ✅ Replace from TODAY -> end of week
        final days = plan['days'];
        if (days is Map) {
          final remapped = _remapSavedWeekDaysFromToday(days);

          batch.set(
            activeDoc,
            {
              'days': remapped,
              'appliedFromSavedPlanId': widget.savedPlanId,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan applied.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not apply plan: $e')),
      );
    }
  }

  // ---- DELETE ----

  Future<bool> _confirmDelete() async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete saved plan?'),
            content: const Text('This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<void> _deletePlan() async {
    final doc = _savedDoc();
    if (doc == null) return;

    final ok = await _confirmDelete();
    if (!ok) return;

    try {
      await doc.delete();

      if (!mounted) return;
      Navigator.of(context).pop(); // back to list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved plan deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  // ---- UI render helpers ----

  Widget _thumb(String? url) {
    const size = 44.0;

    if (url == null || url.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Icon(Icons.image, size: 20),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: const Icon(Icons.broken_image, size: 20),
        ),
      ),
    );
  }

  Widget _slotTile({
    required String slot,
    required dynamic entry,
  }) {
    final label = slot.toUpperCase();

    if (_entryIsRecipe(entry)) {
      final rid = _entryRecipeId(entry);
      final r = _byId(rid);
      final title = (r == null) ? 'Recipe #$rid' : _titleOf(r);
      final thumb = (r == null) ? null : _thumbOf(r);

      return ListTile(
        leading: _thumb(thumb),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: rid == null
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: rid)),
                );
              },
      );
    }

    final note = _entryNoteText(entry);
    if (note != null && note.isNotEmpty) {
      return ListTile(
        leading: const Icon(Icons.sticky_note_2_outlined),
        title: Text(note, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(label),
      );
    }

    return ListTile(
      leading: const Icon(Icons.remove_circle_outline),
      title: const Text('Not set'),
      subtitle: Text(label),
    );
  }

  Widget _daySection({
    required String title,
    required Map day,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const Divider(height: 1),
            for (final slot in MealPlanSlots.order)
              _slotTile(
                slot: slot,
                entry: day[slot],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const Scaffold(
        body: Center(child: Text('Log in to view saved meal plans')),
      );
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved plan')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $_error'),
        ),
      );
    }

    final plan = _plan ?? {};
    final title = (plan['title'] ?? '').toString().trim();
    final type = (plan['type'] ?? 'week').toString(); // 'week' | 'day'

    return Scaffold(
      appBar: AppBar(
        title: Text(title.isNotEmpty ? title : 'Saved plan'),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _deletePlan,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  type == 'day' ? 'Saved day plan' : 'Saved week plan',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _usePlan,
                icon: const Icon(Icons.play_arrow),
                label: const Text('USE'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (type == 'week') ...[
            Builder(builder: (_) {
              final days = plan['days'];
              if (days is! Map) {
                return const Text('No days found in this saved plan.');
              }

              final keys = days.keys.map((k) => k.toString()).toList()..sort();

              return Column(
                children: [
                  for (final dayKey in keys)
                    if (days[dayKey] is Map)
                      _daySection(
                        title: _prettyDayKey(dayKey),
                        day: days[dayKey] as Map,
                      ),
                ],
              );
            }),
          ] else ...[
            Builder(builder: (_) {
              final day = plan['day'];
              if (day is! Map) {
                return const Text('No day data found in this saved plan.');
              }
              final dayKey =
                  (plan['dayKey'] ?? MealPlanKeys.todayKey()).toString();
              return _daySection(
                title: _prettyDayKey(dayKey),
                day: day,
              );
            }),
          ],
        ],
      ),
    );
  }
}

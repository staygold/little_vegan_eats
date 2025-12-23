import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../recipes/recipe_detail_screen.dart';
import '../recipes/recipe_repository.dart';

// ✅ SAME weekId logic as meal plan
import '../meal_plan/core/meal_plan_keys.dart';

// ✅ Centralised review prompt
import '../meal_plan/core/meal_plan_review_service.dart';

// ✅ NEW: use the centralised meal plan repo + controller to auto-populate
import '../meal_plan/core/meal_plan_repository.dart';
import '../meal_plan/core/meal_plan_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = true;

  MealPlanController? _mealCtrl;
  bool _bootstrappedWeek = false;

  @override
  void initState() {
    super.initState();
    _loadRecipesAndBootstrap();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await MealPlanReviewService.checkAndPromptIfNeeded(context);
    });
  }

  @override
  void dispose() {
    // Clean up controller stream
    _mealCtrl?.stop();
    _mealCtrl = null;
    super.dispose();
  }

  // ---------- DATE HELPERS ----------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _todayKey() => _dateKey(_dateOnly(DateTime.now()));

  // ✅ MUST match MealPlanController/MealPlanKeys logic
  String _weekId() => MealPlanKeys.currentWeekId();

  // ---------- RECIPES ----------

  Future<void> _loadRecipesAndBootstrap() async {
    try {
      _recipes = await RecipeRepository.ensureRecipesLoaded();
    } catch (_) {
      _recipes = [];
    } finally {
      if (mounted) setState(() => _recipesLoading = false);
    }

    // After recipes are loaded, bootstrap the Firestore meal plan if needed
    await _bootstrapMealPlanIfNeeded();
  }

  Future<void> _bootstrapMealPlanIfNeeded() async {
    if (!mounted) return;
    if (_bootstrappedWeek) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_recipes.isEmpty) return;

    // Create controller once and keep it alive while Home is alive
    _mealCtrl ??= MealPlanController(
      auth: FirebaseAuth.instance,
      repo: MealPlanRepository(FirebaseFirestore.instance),
      initialWeekId: _weekId(),
    );

    // Keep controller subscribed (not strictly required for bootstrapping,
    // but useful if anything else updates week data)
    _mealCtrl!.start();

    // Ensure we only attempt once per Home lifetime
    _bootstrappedWeek = true;

    try {
      // This will:
      // - ensure week doc exists
      // - load current week data
      // - write missing slots to Firestore (upsertDays)
      await _mealCtrl!.ensurePlanPopulated(recipes: _recipes);
    } catch (_) {
      // Silent fail: Home will still render empty state if no plan exists
    }
  }

  int? _recipeIdFromAny(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return int.tryParse('${raw ?? ''}');
  }

  Map<String, dynamic>? _byId(int? id) {
    if (id == null) return null;
    for (final r in _recipes) {
      final rid = _recipeIdFromAny(r['id']);
      if (rid == id) return r;
    }
    return null;
  }

  String _titleOf(Map<String, dynamic> r) {
    final t = r['title'];
    if (t is Map && t['rendered'] is String) {
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

  // ---------- ENTRY PARSING ----------

  Map<String, dynamic>? _parseEntry(dynamic raw) {
    // Legacy: int/num recipeId
    if (raw is int) return {'type': 'recipe', 'recipeId': raw};
    if (raw is num) return {'type': 'recipe', 'recipeId': raw.toInt()};

    // New: map
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final type = (m['type'] ?? '').toString();

      if (type == 'note') {
        final text = (m['text'] ?? '').toString().trim();
        if (text.isEmpty) return null;
        return {'type': 'note', 'text': text};
      }

      if (type == 'recipe') {
        final rid = _recipeIdFromAny(m['recipeId']);
        if (rid == null) return null;
        return {'type': 'recipe', 'recipeId': rid};
      }
    }

    // Sometimes strings sneak in
    if (raw is String) {
      final id = int.tryParse(raw.trim());
      if (id != null) return {'type': 'recipe', 'recipeId': id};
    }

    return null;
  }

  int? _entryRecipeId(Map<String, dynamic>? e) {
    if (e == null) return null;
    if (e['type'] != 'recipe') return null;
    return _recipeIdFromAny(e['recipeId']);
  }

  String? _entryNoteText(Map<String, dynamic>? e) {
    if (e == null) return null;
    if (e['type'] != 'note') return null;
    final t = (e['text'] ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  // ---------- FIRESTORE STREAM ----------

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _weekStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPlansWeeks')
        .doc(_weekId())
        .snapshots();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final stream = _weekStream();

    if (_recipesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (stream == null) {
      return const Center(child: Text('Log in to see your meal plan'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snap.data?.data() ?? <String, dynamic>{};
        final days = data['days'];
        final todayKey = _todayKey();

        final Map<String, dynamic> todayRaw =
            (days is Map && days[todayKey] is Map)
                ? Map<String, dynamic>.from(days[todayKey] as Map)
                : <String, dynamic>{};

        final entries = <MapEntry<String, Map<String, dynamic>>>[];
        for (final e in todayRaw.entries) {
          final parsed = _parseEntry(e.value);
          if (parsed == null) continue;
          entries.add(MapEntry(e.key.toString(), parsed));
        }

        const slotOrder = ['breakfast', 'snack1', 'lunch', 'snack2', 'dinner'];
        entries.sort((a, b) {
          final ia = slotOrder.indexOf(a.key);
          final ib = slotOrder.indexOf(b.key);
          return (ia == -1 ? 999 : ia).compareTo(ib == -1 ? 999 : ib);
        });

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              "Today's Meals",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),

            if (entries.isEmpty) ...[
              const Text("No meals planned for today yet."),
            ] else ...[
              ...entries.map((e) {
                final slot = e.key;
                final entry = e.value;

                final note = _entryNoteText(entry);
                if (note != null) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.sticky_note_2_outlined),
                      title: Text(
                        note,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(slot.toUpperCase()),
                    ),
                  );
                }

                final rid = _entryRecipeId(entry);
                final r = _byId(rid);

                if (r == null) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.restaurant_menu),
                      title: const Text('Recipe not found'),
                      subtitle: Text(slot.toUpperCase()),
                    ),
                  );
                }

                final title = _titleOf(r);
                final thumb = _thumbOf(r);

                return Card(
                  child: ListTile(
                    leading: thumb == null
                        ? const Icon(Icons.restaurant_menu)
                        : Image.network(
                            thumb,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.restaurant_menu),
                          ),
                    title: Text(title),
                    subtitle: Text(slot.toUpperCase()),
                    onTap: rid == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RecipeDetailScreen(id: rid),
                              ),
                            ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 16),

            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pushNamed('/meal-plan'),
                child: const Text('CUSTOMISE MEAL PLAN'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pushNamed('/meal-plan'),
                child: const Text('VIEW FULL WEEK'),
              ),
            ),
          ],
        );
      },
    );
  }
}

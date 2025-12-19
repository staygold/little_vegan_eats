import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../recipes/recipe_detail_screen.dart';
import '../recipes/recipe_repository.dart'; // ✅ single source of truth

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecipes();
  }

  // ---------- DATE HELPERS ----------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _todayKey() => _dateKey(_dateOnly(DateTime.now()));

  // IMPORTANT: must match MealPlanScreen forward-week doc id
  String _weekId() => _todayKey();

  // ---------- RECIPES ----------

  Future<void> _loadRecipes() async {
    try {
      _recipes = await RecipeRepository.ensureRecipesLoaded();
    } catch (_) {
      // Keep _recipes empty; UI will show "No recipes yet"
    } finally {
      if (mounted) setState(() => _recipesLoading = false);
    }
  }

  Map<String, dynamic>? _byId(int? id) {
    if (id == null) return null;
    for (final r in _recipes) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  String _titleOf(Map<String, dynamic> r) =>
      (r['title']?['rendered'] as String?)?.trim().isNotEmpty == true
          ? (r['title']['rendered'] as String)
          : 'Untitled';

  String? _thumbOf(Map<String, dynamic> r) {
    final recipe = r['recipe'];
    if (recipe is Map<String, dynamic>) {
      final url = recipe['image_url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
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

    if (_recipes.isEmpty) {
      // If recipes haven’t loaded/cached yet, we cannot resolve IDs to titles.
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Today's Meals",
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Recipes are still loading. Try opening Recipes once, or check your connection.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pushNamed('/meal-plan'),
              child: const Text('VIEW FULL WEEK'),
            ),
          ),
        ],
      );
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

        final data = snap.data?.data() ?? {};
        final days = data['days'];

        Map<String, int?> todayMeals = {};
        final todayKey = _todayKey();

        if (days is Map && days[todayKey] is Map) {
          final raw = Map<String, dynamic>.from(days[todayKey] as Map);
          todayMeals = raw.map((k, v) => MapEntry(k.toString(), v as int?));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              "Today's Meals",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),

            if (todayMeals.isEmpty) ...[
              const Text("No meals planned for today yet."),
            ] else ...[
              ...todayMeals.entries.map((e) {
                final r = _byId(e.value);
                if (r == null) return const SizedBox();

                final title = _titleOf(r);
                final thumb = _thumbOf(r);
                final id = r['id'] as int?;

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
                    subtitle: Text(e.key.toUpperCase()),
                    onTap: id == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RecipeDetailScreen(id: id),
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
                child: const Text('VIEW FULL WEEK'),
              ),
            ),
          ],
        );
      },
    );
  }
}

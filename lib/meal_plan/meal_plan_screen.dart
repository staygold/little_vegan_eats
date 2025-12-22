import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_detail_screen.dart';
import '../recipes/recipe_repository.dart';

enum MealPlanViewMode { today, week }

class MealPlanScreen extends StatefulWidget {
  /// If provided, we load that specific saved week docId.
  final String? weekId;

  /// If provided (YYYY-MM-DD), we show only that day in Today mode.
  final String? focusDayKey;

  const MealPlanScreen({
    super.key,
    this.weekId,
    this.focusDayKey,
  });

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late MealPlanViewMode _mode;

  // Loaded recipes (for title + thumb + detail nav)
  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = true;

  /// Draft edits, stored per dayKey -> slot -> recipeId
  final Map<String, Map<String, int>> _draft = {};

  /// Slots (match your existing system)
  static const List<String> _slotOrder = [
    'breakfast',
    'snack1',
    'lunch',
    'snack2',
    'dinner',
  ];

  @override
  void initState() {
    super.initState();

    // Saved week -> week mode
    if (widget.weekId != null && widget.weekId!.trim().isNotEmpty) {
      _mode = MealPlanViewMode.week;
    }
    // Focus day -> today mode
    else if (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty) {
      _mode = MealPlanViewMode.today;
    } else {
      _mode = MealPlanViewMode.week;
    }

    _loadRecipes();
  }

  // ---------------------------
  // Recipes
  // ---------------------------
  Future<void> _loadRecipes() async {
    try {
      _recipes = await RecipeRepository.ensureRecipesLoaded();
    } catch (_) {
      _recipes = [];
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

  // ---------------------------
  // Date helpers
  // ---------------------------
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _todayKey() => _dayKey(_dateOnly(DateTime.now()));

  /// IMPORTANT: matches your HomeScreen behaviour (doc id == today's date key)
  String _defaultWeekId() => _todayKey();

  String formatDayKeyPretty(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) return dayKey;

    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return dayKey;

    final dt = DateTime(y, m, d);

    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final weekday = weekdays[dt.weekday - 1];
    final mon = months[dt.month - 1];
    return '$weekday, ${dt.day} $mon';
  }

  String _weekdayLetter(DateTime dt) {
    // S M T W T F S
    switch (dt.weekday) {
      case DateTime.monday:
        return 'M';
      case DateTime.tuesday:
        return 'T';
      case DateTime.wednesday:
        return 'W';
      case DateTime.thursday:
        return 'T';
      case DateTime.friday:
        return 'F';
      case DateTime.saturday:
        return 'S';
      case DateTime.sunday:
        return 'S';
      default:
        return '';
    }
  }

  DateTime? _parseDayKey(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  // ---------------------------
  // Firestore
  // ---------------------------
  DocumentReference<Map<String, dynamic>>? _weekDoc(String weekId) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    // IMPORTANT: matches HomeScreen
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mealPlansWeeks')
        .doc(weekId);
  }

  // weekData['days'][dayKey] => map(slot -> recipeId)
  Map<String, dynamic>? _dayMapFromWeek(Map<String, dynamic> weekData, String dayKey) {
    final days = weekData['days'];
    if (days is Map) {
      final raw = days[dayKey];
      if (raw is Map) return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  int? _firestoreSlotId(Map<String, dynamic> weekData, String dayKey, String slot) {
    final day = _dayMapFromWeek(weekData, dayKey);
    if (day == null) return null;
    final v = day[slot];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  int? _draftValue(String dayKey, String slot) => _draft[dayKey]?[slot];

  void _setDraft(String dayKey, String slot, int recipeId) {
    final dayDraft = _draft.putIfAbsent(dayKey, () => {});
    dayDraft[slot] = recipeId;
    setState(() {});
  }

  bool _dayHasDraftChanges(Map<String, dynamic> weekData, String dayKey) {
    final d = _draft[dayKey];
    if (d == null || d.isEmpty) return false;

    for (final entry in d.entries) {
      final slot = entry.key;
      final draftId = entry.value;
      final currentId = _firestoreSlotId(weekData, dayKey, slot);
      if (currentId != draftId) return true;
    }
    return false;
  }

  Future<void> _saveDay({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> weekData,
    required String dayKey,
  }) async {
    final dayDraft = _draft[dayKey];
    if (dayDraft == null || dayDraft.isEmpty) return;

    // Build updated day map (merge existing + draft)
    final existing = _dayMapFromWeek(weekData, dayKey) ?? {};
    final updated = <String, dynamic>{...existing};

    for (final e in dayDraft.entries) {
      updated[e.key] = e.value;
    }

    // Write only that day: days.{dayKey} = updated
    await docRef.set({
      'days': {dayKey: updated},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Clear draft for that day
    _draft.remove(dayKey);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${formatDayKeyPretty(dayKey)}')),
      );
    }
  }

  // ---------------------------
  // Auto-change (↻)
  // ---------------------------
  int? _autoPickDifferentId({required int? currentId}) {
    if (_recipes.isEmpty) return null;

    final ids = <int>[];
    for (final r in _recipes) {
      final id = r['id'];
      if (id is int) ids.add(id);
    }
    if (ids.isEmpty) return null;
    if (ids.length == 1) return ids.first;

    final idx = currentId == null ? -1 : ids.indexOf(currentId);
    final start = idx < 0 ? 0 : (idx + 1) % ids.length;

    for (int step = 0; step < ids.length; step++) {
      final candidate = ids[(start + step) % ids.length];
      if (candidate != currentId) return candidate;
    }

    return null;
  }

  Future<void> _autoChangeSlot({
    required Map<String, dynamic> weekData,
    required String dayKey,
    required String slot,
  }) async {
    final currentEffective =
        _draftValue(dayKey, slot) ?? _firestoreSlotId(weekData, dayKey, slot);

    final nextId = _autoPickDifferentId(currentId: currentEffective);
    if (nextId == null) return;

    _setDraft(dayKey, slot, nextId);
  }

  // ---------------------------
  // Week day keys for tabs
  // ---------------------------
  List<String> _weekDayKeys(Map<String, dynamic> weekData, String resolvedWeekId) {
    // Prefer whatever is in Firestore
    final days = weekData['days'];
    if (days is Map) {
      final keys = days.keys.map((k) => k.toString()).toList()..sort();
      if (keys.isNotEmpty) return keys.take(7).toList();
    }

    // Fallback: generate 7 days from resolvedWeekId (doc id is todayKey)
    final start = _parseDayKey(resolvedWeekId) ?? _dateOnly(DateTime.now());
    return List.generate(7, (i) => _dayKey(start.add(Duration(days: i))));
  }

  // ---------------------------
  // UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Log in to view your meal plan')),
      );
    }

    if (_recipesLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final now = DateTime.now();
    final resolvedWeekId = (widget.weekId != null && widget.weekId!.trim().isNotEmpty)
        ? widget.weekId!.trim()
        : _defaultWeekId();

    final docRef = _weekDoc(resolvedWeekId);
    if (docRef == null) {
      return const Scaffold(
        body: Center(child: Text('Could not load meal plans')),
      );
    }

    final focusDayKey = (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty)
        ? widget.focusDayKey!.trim()
        : _todayKey();

    return Scaffold(
      appBar: AppBar(
        title: Text(_mode == MealPlanViewMode.today ? "Today's meal plan" : "This week's meal plan"),
        actions: [
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today),
            onPressed: () => setState(() => _mode = MealPlanViewMode.today),
          ),
          IconButton(
            tooltip: 'This week',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => setState(() => _mode = MealPlanViewMode.week),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
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

          final weekData = snap.data?.data();
          if (weekData == null) {
            return const Center(child: Text('No meal plan found for this week yet.'));
          }

          if (_mode == MealPlanViewMode.today) {
            return _DayView(
              title: "Today",
              prettyDate: formatDayKeyPretty(focusDayKey),
              dayKey: focusDayKey,
              weekData: weekData,
              resolvedWeekId: resolvedWeekId,
              docRef: docRef,
              recipes: _recipes,
              slotOrder: _slotOrder,
              byId: _byId,
              titleOf: _titleOf,
              thumbOf: _thumbOf,
              effectiveIdFor: (dayKey, slot) =>
                  _draftValue(dayKey, slot) ?? _firestoreSlotId(weekData, dayKey, slot),
              onChange: (slot) => _autoChangeSlot(weekData: weekData, dayKey: focusDayKey, slot: slot),
              canSave: _dayHasDraftChanges(weekData, focusDayKey),
              onSave: () => _saveDay(docRef: docRef, weekData: weekData, dayKey: focusDayKey),
              onViewWeek: () => setState(() => _mode = MealPlanViewMode.week),
            );
          }

          final dayKeys = _weekDayKeys(weekData, resolvedWeekId);
          final initialIndex = () {
            final idx = dayKeys.indexOf(focusDayKey);
            return idx >= 0 ? idx : 0;
          }();

          return DefaultTabController(
            length: dayKeys.length,
            initialIndex: initialIndex.clamp(0, dayKeys.length - 1),
            child: Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: TabBar(
                    isScrollable: false,
                    tabs: [
                      for (final k in dayKeys)
                        Tab(
                          text: _weekdayLetter(_parseDayKey(k) ?? now),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final dayKey in dayKeys)
                        _DayView(
                          title: "Day",
                          prettyDate: formatDayKeyPretty(dayKey),
                          dayKey: dayKey,
                          weekData: weekData,
                          resolvedWeekId: resolvedWeekId,
                          docRef: docRef,
                          recipes: _recipes,
                          slotOrder: _slotOrder,
                          byId: _byId,
                          titleOf: _titleOf,
                          thumbOf: _thumbOf,
                          effectiveIdFor: (dk, slot) =>
                              _draftValue(dk, slot) ?? _firestoreSlotId(weekData, dk, slot),
                          onChange: (slot) => _autoChangeSlot(weekData: weekData, dayKey: dayKey, slot: slot),
                          canSave: _dayHasDraftChanges(weekData, dayKey),
                          onSave: () => _saveDay(docRef: docRef, weekData: weekData, dayKey: dayKey),
                          onViewWeek: null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------
// Day view (used for Today + each Week tab)
// ----------------------------------------------------
class _DayView extends StatelessWidget {
  final String title;
  final String prettyDate;
  final String dayKey;

  final Map<String, dynamic> weekData;
  final String resolvedWeekId;
  final DocumentReference<Map<String, dynamic>> docRef;

  final List<Map<String, dynamic>> recipes;
  final List<String> slotOrder;

  final Map<String, dynamic>? Function(int? id) byId;
  final String Function(Map<String, dynamic> r) titleOf;
  final String? Function(Map<String, dynamic> r) thumbOf;

  final int? Function(String dayKey, String slot) effectiveIdFor;

  final void Function(String slot) onChange;
  final bool canSave;
  final Future<void> Function() onSave;

  final VoidCallback? onViewWeek;

  const _DayView({
    required this.title,
    required this.prettyDate,
    required this.dayKey,
    required this.weekData,
    required this.resolvedWeekId,
    required this.docRef,
    required this.recipes,
    required this.slotOrder,
    required this.byId,
    required this.titleOf,
    required this.thumbOf,
    required this.effectiveIdFor,
    required this.onChange,
    required this.canSave,
    required this.onSave,
    required this.onViewWeek,
  });

  String _slotLabel(String slot) => slot.toUpperCase();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          prettyDate,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),

        for (final slot in slotOrder) ...[
          _MealSlotCard(
            slotLabel: _slotLabel(slot),
            recipeId: effectiveIdFor(dayKey, slot),
            byId: byId,
            titleOf: titleOf,
            thumbOf: thumbOf,
            onTapRecipe: (id) {
              if (id == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: id)),
              );
            },
            onChange: () => onChange(slot),
          ),
          const SizedBox(height: 12),
        ],

        const SizedBox(height: 8),

        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: canSave ? () => onSave() : null,
            child: const Text('SAVE DAY'),
          ),
        ),

        if (onViewWeek != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: onViewWeek,
              child: const Text('VIEW FULL WEEK'),
            ),
          ),
        ],
      ],
    );
  }
}

class _MealSlotCard extends StatelessWidget {
  final String slotLabel;
  final int? recipeId;

  final Map<String, dynamic>? Function(int? id) byId;
  final String Function(Map<String, dynamic> r) titleOf;
  final String? Function(Map<String, dynamic> r) thumbOf;

  final void Function(int? id) onTapRecipe;
  final VoidCallback onChange;

  const _MealSlotCard({
    required this.slotLabel,
    required this.recipeId,
    required this.byId,
    required this.titleOf,
    required this.thumbOf,
    required this.onTapRecipe,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final r = byId(recipeId);
    final title = r == null ? 'Not set' : titleOf(r);
    final thumb = r == null ? null : thumbOf(r);

    return Card(
      child: ListTile(
        leading: _Thumb(url: thumb),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(slotLabel),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Change',
          onPressed: onChange,
        ),
        onTap: () => onTapRecipe(recipeId),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? url;
  const _Thumb({this.url});

  @override
  Widget build(BuildContext context) {
    final u = url;
    const size = 56.0;

    if (u == null || u.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.image, size: 22),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: size,
            height: size,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image, size: 22),
          );
        },
      ),
    );
  }
}

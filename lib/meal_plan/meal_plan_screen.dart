import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/recipe_detail_screen.dart';
import '../recipes/recipe_repository.dart';

import 'core/allergy_profile.dart';
import 'core/meal_plan_controller.dart';
import 'core/meal_plan_keys.dart';
import 'core/meal_plan_repository.dart';
import 'core/meal_plan_slots.dart';

enum MealPlanViewMode { today, week }

class MealPlanScreen extends StatefulWidget {
  final String? weekId;
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

  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = true;

  late final MealPlanController _ctrl;

  @override
  void initState() {
    super.initState();

    // Mode
    if (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty) {
      _mode = MealPlanViewMode.today;
    } else {
      _mode = MealPlanViewMode.week;
    }

    // Week
    final resolvedWeekId =
        (widget.weekId != null && widget.weekId!.trim().isNotEmpty)
            ? widget.weekId!.trim()
            : MealPlanKeys.currentWeekId();

    _ctrl = MealPlanController(
      auth: FirebaseAuth.instance,
      repo: MealPlanRepository(FirebaseFirestore.instance),
      initialWeekId: resolvedWeekId,
    );

    _ctrl.start();
    _ctrl.ensureWeek();

    // IMPORTANT: run in sequence so populate sees correct allergy sets
    () async {
      await _loadAllergies();
      await _loadRecipes();
    }();
  }

  @override
  void dispose() {
    _ctrl.stop();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllergies() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final sets = AllergyProfile.buildFromUserDoc(snap.data());

      _ctrl.setAllergySets(
        excludedAllergens: sets.excludedAllergens,
        childAllergens: sets.childAllergens,
      );
    } catch (_) {
      // fail open
      _ctrl.setAllergySets(excludedAllergens: {}, childAllergens: {});
    }
  }

  Future<void> _loadRecipes() async {
    try {
      _recipes = await RecipeRepository.ensureRecipesLoaded();
    } catch (_) {
      _recipes = [];
    } finally {
      if (mounted) setState(() => _recipesLoading = false);
    }

    if (_recipes.isNotEmpty && FirebaseAuth.instance.currentUser != null) {
      await _ctrl.ensurePlanPopulated(recipes: _recipes);
    }
  }

  // ---------- helpers ----------

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

  List<int> _availableSafeRecipeIds() {
    final ids = <int>[];
    for (final r in _recipes) {
      if (!_ctrl.recipeAllowed(r)) continue;
      final rid = _recipeIdFrom(r);
      if (rid != null) ids.add(rid);
    }
    return ids;
  }

  String formatDayKeyPretty(String dayKey) {
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

  String _weekdayLetter(DateTime dt) {
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

  Future<void> _chooseRecipe({
    required String dayKey,
    required String slot,
  }) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChooseRecipeSheet(
        recipes: _recipes,
        titleOf: _titleOf,
        thumbOf: _thumbOf,
        isAllowed: _ctrl.recipeAllowed,
        idOf: _recipeIdFrom,
      ),
    );

    if (picked != null) {
      _ctrl.setDraftRecipe(dayKey, slot, picked, source: 'manual');
    }
  }

  Future<void> _addOrEditNote({
    required String dayKey,
    required String slot,
    String? initial,
  }) async {
    final textCtrl = TextEditingController(text: initial ?? '');

    final result = await showDialog<_NoteResult>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "e.g. Out for dinner / Visiting family",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _NoteResult.cancel()),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(_NoteResult.save(textCtrl.text)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (result == null || result.kind == _NoteResultKind.cancel) return;

    final text = (result.text ?? '').trim();
    if (text.isEmpty) return;

    _ctrl.setDraftNote(dayKey, slot, text);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Log in to view your meal plan')),
      );
    }

    if (_recipesLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final focusDayKey =
        (widget.focusDayKey != null && widget.focusDayKey!.trim().isNotEmpty)
            ? widget.focusDayKey!.trim()
            : MealPlanKeys.todayKey();

    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(_mode == MealPlanViewMode.today
            ? "Today's meal plan"
            : "Next 7 days"),
        actions: [
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today),
            onPressed: () => setState(() => _mode = MealPlanViewMode.today),
          ),
          IconButton(
            tooltip: 'Next 7 days',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => setState(() => _mode = MealPlanViewMode.week),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final data = _ctrl.weekData;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          Widget buildDay(String dayKey, {VoidCallback? onViewWeek}) {
            return _DayView(
              prettyDate: formatDayKeyPretty(dayKey),
              dayKey: dayKey,
              slotOrder: MealPlanSlots.order,
              effectiveEntryFor: (dk, slot) => _ctrl.effectiveEntry(dk, slot),
              isRecipe: _ctrl.entryIsRecipe,
              recipeIdOf: _ctrl.entryRecipeId,
              noteTextOf: _ctrl.entryNoteText,
              byId: _byId,
              titleOf: _titleOf,
              thumbOf: _thumbOf,
              onInspire: (slot) {
                final ids = _availableSafeRecipeIds();
                final currentEntry = _ctrl.effectiveEntry(dayKey, slot);
                final currentId = _ctrl.entryRecipeId(currentEntry);
                final next = _ctrl.pickDifferentId(
                  availableIds: ids,
                  currentId: currentId,
                );
                if (next != null) {
                  _ctrl.setDraftRecipe(dayKey, slot, next, source: 'auto');
                }
              },
              onChoose: (slot) => _chooseRecipe(dayKey: dayKey, slot: slot),
              onNote: (slot) {
                final current = _ctrl.effectiveEntry(dayKey, slot);
                final initial = _ctrl.entryNoteText(current);
                _addOrEditNote(dayKey: dayKey, slot: slot, initial: initial);
              },
              canSave: _ctrl.hasDraftChanges(dayKey),
              onSave: () async {
  await _ctrl.saveDay(dayKey);

  if (!mounted) return; // ✅ State-mounted, not builder context

  ScaffoldMessenger.of(this.context).showSnackBar(
    SnackBar(content: Text('Saved ${formatDayKeyPretty(dayKey)}')),
  );
},
              onViewWeek: onViewWeek,
            );
          }

          if (_mode == MealPlanViewMode.today) {
            return buildDay(
              focusDayKey,
              onViewWeek: () => setState(() => _mode = MealPlanViewMode.week),
            );
          }

          final dayKeys = MealPlanKeys.weekDayKeys(_ctrl.weekId);
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
                        Tab(text: _weekdayLetter(MealPlanKeys.parseDayKey(k) ?? now)),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final dayKey in dayKeys) buildDay(dayKey),
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
// Day view
// ----------------------------------------------------
class _DayView extends StatelessWidget {
  final String prettyDate;
  final String dayKey;

  final List<String> slotOrder;

  final Map<String, dynamic>? Function(String dayKey, String slot)
      effectiveEntryFor;
  final bool Function(Map<String, dynamic>? e) isRecipe;
  final int? Function(Map<String, dynamic>? e) recipeIdOf;
  final String? Function(Map<String, dynamic>? e) noteTextOf;

  final Map<String, dynamic>? Function(int? id) byId;
  final String Function(Map<String, dynamic> r) titleOf;
  final String? Function(Map<String, dynamic> r) thumbOf;

  final void Function(String slot) onInspire;
  final void Function(String slot) onChoose;
  final void Function(String slot) onNote;

  final bool canSave;
  final Future<void> Function() onSave;

  final VoidCallback? onViewWeek;

  const _DayView({
    required this.prettyDate,
    required this.dayKey,
    required this.slotOrder,
    required this.effectiveEntryFor,
    required this.isRecipe,
    required this.recipeIdOf,
    required this.noteTextOf,
    required this.byId,
    required this.titleOf,
    required this.thumbOf,
    required this.onInspire,
    required this.onChoose,
    required this.onNote,
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
        Text(prettyDate, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        for (final slot in slotOrder) ...[
          _MealSlotCard(
            slotLabel: _slotLabel(slot),
            entry: effectiveEntryFor(dayKey, slot),
            isRecipe: isRecipe,
            recipeIdOf: recipeIdOf,
            noteTextOf: noteTextOf,
            byId: byId,
            titleOf: titleOf,
            thumbOf: thumbOf,
            onTapRecipe: (id) {
              if (id == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RecipeDetailScreen(id: id)),
              );
            },
            onInspire: () => onInspire(slot),
            onChoose: () => onChoose(slot),
            onNote: () => onNote(slot),
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
              child: const Text('VIEW NEXT 7 DAYS'),
            ),
          ),
        ],
      ],
    );
  }
}

class _MealSlotCard extends StatelessWidget {
  final String slotLabel;
  final Map<String, dynamic>? entry;

  final bool Function(Map<String, dynamic>? e) isRecipe;
  final int? Function(Map<String, dynamic>? e) recipeIdOf;
  final String? Function(Map<String, dynamic>? e) noteTextOf;

  final Map<String, dynamic>? Function(int? id) byId;
  final String Function(Map<String, dynamic> r) titleOf;
  final String? Function(Map<String, dynamic> r) thumbOf;

  final void Function(int? id) onTapRecipe;

  final VoidCallback onInspire;
  final VoidCallback onChoose;
  final VoidCallback onNote;

  const _MealSlotCard({
    required this.slotLabel,
    required this.entry,
    required this.isRecipe,
    required this.recipeIdOf,
    required this.noteTextOf,
    required this.byId,
    required this.titleOf,
    required this.thumbOf,
    required this.onTapRecipe,
    required this.onInspire,
    required this.onChoose,
    required this.onNote,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;

    // Note entry
    final noteText = noteTextOf(e);
    if (noteText != null && noteText.trim().isNotEmpty && !isRecipe(e)) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: Text(noteText,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(slotLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Clear note (add a recipe)',
                icon: const Icon(Icons.close),
                onPressed: onInspire,
              ),
              IconButton(
                tooltip: 'Edit note',
                icon: const Icon(Icons.edit_note),
                onPressed: onNote,
              ),
            ],
          ),
          onTap: onNote,
        ),
      );
    }

    // Recipe entry (or unset)
    final rid = recipeIdOf(e);
    final r = byId(rid);

    final title = r == null ? 'Not set' : titleOf(r);
    final thumb = r == null ? null : thumbOf(r);

    return Card(
      child: ListTile(
        leading: _Thumb(url: thumb),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(slotLabel),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Inspire',
              onPressed: onInspire,
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Choose recipe',
              onPressed: onChoose,
            ),
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: 'Add note',
              onPressed: onNote,
            ),
          ],
        ),
        onTap: () => onTapRecipe(rid),
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

// ----------------------------------------------------
// Choose Recipe Sheet
// ----------------------------------------------------
class _ChooseRecipeSheet extends StatefulWidget {
  final List<Map<String, dynamic>> recipes;
  final String Function(Map<String, dynamic>) titleOf;
  final String? Function(Map<String, dynamic>) thumbOf;
  final int? Function(Map<String, dynamic>) idOf;

  /// If provided, we disable recipes that fail profile exclusions.
  final bool Function(Map<String, dynamic>)? isAllowed;

  const _ChooseRecipeSheet({
    required this.recipes,
    required this.titleOf,
    required this.thumbOf,
    required this.idOf,
    this.isAllowed,
  });

  @override
  State<_ChooseRecipeSheet> createState() => _ChooseRecipeSheetState();
}

class _ChooseRecipeSheetState extends State<_ChooseRecipeSheet> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.recipes.where((r) {
      if (_q.trim().isEmpty) return true;
      final t = widget.titleOf(r).toLowerCase();
      return t.contains(_q.toLowerCase());
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search recipes',
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final id = widget.idOf(r);
                  final title = widget.titleOf(r);
                  final thumb = widget.thumbOf(r);

                  final allowed =
                      widget.isAllowed == null ? true : widget.isAllowed!(r);

                  return ListTile(
                    enabled: allowed && id != null,
                    leading: thumb == null
                        ? const Icon(Icons.restaurant_menu)
                        : Image.network(
                            thumb,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.restaurant_menu),
                          ),
                    title: Text(title),
                    subtitle:
                        allowed ? null : const Text('Excluded by allergies'),
                    onTap: (!allowed || id == null)
                        ? null
                        : () => Navigator.of(context).pop(id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------
// Dialog result helper
// ----------------------------------------------------
enum _NoteResultKind { cancel, save }

class _NoteResult {
  final _NoteResultKind kind;
  final String? text;

  const _NoteResult._(this.kind, this.text);

  const _NoteResult.cancel() : this._(_NoteResultKind.cancel, null);
  _NoteResult.save(String text) : this._(_NoteResultKind.save, text);
}

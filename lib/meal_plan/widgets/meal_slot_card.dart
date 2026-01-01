// lib/meal_plan/widgets/meal_slot_card.dart
import 'package:flutter/material.dart';

class MealSlotCard extends StatelessWidget {
  final String slotLabel;
  final Map<String, dynamic>? entry;

  final bool Function(Map<String, dynamic>? e) isRecipe;
  final int? Function(Map<String, dynamic>? e) recipeIdOf;
  final String? Function(Map<String, dynamic>? e) noteTextOf;

  final Map<String, dynamic>? Function(int? id) byId;
  final String Function(Map<String, dynamic> r) titleOf;
  final String? Function(Map<String, dynamic> r) thumbOf;

  /// "safe" | "swap" | "blocked"
  final String Function(Map<String, dynamic> recipe) statusTextOf;

  // ⭐ favorites indicator
  final bool Function(int? recipeId) isFavorited;

  final void Function(int? id) onTapRecipe;

  final VoidCallback onInspire;
  final VoidCallback onChoose;
  final VoidCallback onNote;
  final VoidCallback onClear;

  const MealSlotCard({
    super.key,
    required this.slotLabel,
    required this.entry,
    required this.isRecipe,
    required this.recipeIdOf,
    required this.noteTextOf,
    required this.byId,
    required this.titleOf,
    required this.thumbOf,
    required this.statusTextOf,
    required this.isFavorited,
    required this.onTapRecipe,
    required this.onInspire,
    required this.onChoose,
    required this.onNote,
    required this.onClear,
  });

  Widget _withFavBadge(BuildContext context, Widget base, bool show) {
    if (!show) return base;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 6,
                  offset: Offset(0, 2),
                  color: Colors.black12,
                ),
              ],
            ),
            child: const Icon(
              Icons.star_rounded,
              size: 16,
              color: Colors.amber,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = entry;

    // Note entry
    final noteText = noteTextOf(e);
    if (noteText != null && noteText.trim().isNotEmpty && !isRecipe(e)) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: Text(
            noteText,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          // ✅ removed course/slot label subtitle
          subtitle: null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: onClear,
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

    final fav = isFavorited(rid);

    // No recipe selected
    if (r == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.restaurant_menu),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          // ✅ removed course/slot label subtitle
          subtitle: null,
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
        ),
      );
    }

    final status = statusTextOf(r); // safe | swap | blocked

    if (status == 'blocked') {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: _withFavBadge(
            context,
            const Icon(Icons.warning_amber_rounded),
            fav,
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          // ✅ removed slot label from subtitle string
          subtitle: const Text('Not suitable for current allergies'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Inspire (safe only)',
                onPressed: onInspire,
              ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Choose recipe',
                onPressed: onChoose,
              ),
            ],
          ),
          onTap: () => onTapRecipe(rid),
        ),
      );
    }

    if (status == 'swap') {
      return Card(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: ListTile(
          leading: _withFavBadge(
            context,
            const Icon(Icons.swap_horiz),
            fav,
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          // ✅ removed slot label from subtitle string
          subtitle: const Text('Needs swap to be allergy-safe'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Inspire (safe only)',
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

    // Safe (normal)
    return Card(
      child: ListTile(
        leading: _withFavBadge(context, MealSlotThumb(url: thumb), fav),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        // ✅ removed course/slot label subtitle
        subtitle: null,
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

class MealSlotThumb extends StatelessWidget {
  final String? url;
  const MealSlotThumb({super.key, this.url});

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
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image, size: 22),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
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

// lib/lists/shopping_list_detail_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'shopping_repo.dart';
import 'shopping_engine.dart';
// ✅ Import the new add sheet
import 'shopping_item_add_sheet.dart'; 

class ShoppingListDetailScreen extends StatefulWidget {
  final String listId;
  final String listName;

  const ShoppingListDetailScreen({
    super.key,
    required this.listId,
    required this.listName,
  });

  @override
  State<ShoppingListDetailScreen> createState() =>
      _ShoppingListDetailScreenState();
}

class _ShoppingListDetailScreenState extends State<ShoppingListDetailScreen> {
  String? _pendingUnitSystem; // metric|us
  bool _savingPrefs = false;

  Future<void> _setPrefs({
    String? unitSystem,
  }) async {
    final repo = ShoppingRepo.instance;

    setState(() {
      _savingPrefs = true;
      if (unitSystem != null) _pendingUnitSystem = unitSystem;
    });

    try {
      await repo.setListPrefs(
        listId: widget.listId,
        unitSystem: unitSystem,
      );
    } catch (e) {
      setState(() {
        if (unitSystem != null) _pendingUnitSystem = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn’t update preferences: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Recipe Management UI
  // ---------------------------------------------------------------------------

  void _showRecipes(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> allItems) {
    // 1. Extract unique recipes from item sources
    final uniqueRecipes = <int, String>{};

    for (final doc in allItems) {
      final data = doc.data();
      final sources = data['sources'];
      if (sources is List) {
        for (final s in sources) {
          if (s is Map) {
            final rid = int.tryParse(s['recipeId']?.toString() ?? '');
            final title =
                (s['recipeTitle'] ?? '').toString().trim();
            
            // Only add if we have a valid ID and it's not empty
            if (rid != null && rid > 0) {
              uniqueRecipes[rid] = title.isNotEmpty ? title : 'Recipe #$rid';
            }
          }
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final recipeList = uniqueRecipes.entries.toList();
        // Sort alphabetically by title
        recipeList.sort((a, b) => a.value.compareTo(b.value));

        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant_menu, color: Colors.black87),
                      const SizedBox(width: 12),
                      const Text(
                        'Included Recipes',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${recipeList.length}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                Expanded(
                  child: recipeList.isEmpty
                      ? Center(
                          child: Text(
                            'No recipes linked to this list yet.',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: recipeList.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final entry = recipeList[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                entry.value,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Colors.red),
                                tooltip: 'Remove recipe',
                                onPressed: () => _confirmRemoveRecipe(
                                    ctx, entry.key, entry.value),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmRemoveRecipe(
      BuildContext dialogContext, int recipeId, String title) async {
    final confirm = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Recipe?'),
        content: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'This will remove '),
              TextSpan(
                text: title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(
                  text:
                      ' and reduce ingredient quantities accordingly.\n\nItems exclusive to this recipe will be deleted.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) Navigator.pop(dialogContext);

      try {
        await ShoppingRepo.instance.removeRecipe(
          listId: widget.listId,
          recipeId: recipeId,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed "$title"')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing recipe: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final repo = ShoppingRepo.instance;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.listDocStream(widget.listId),
      builder: (context, listSnap) {
        if (listSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.listName)),
            body: Center(child: Text('Error: ${listSnap.error}')),
          );
        }

        if (!listSnap.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.listName)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final listData = listSnap.data?.data() ?? const <String, dynamic>{};
        final fsUnitSystem = _unitSystemFromAny(listData['unitSystem']);
        final unitSystem = _pendingUnitSystem ?? fsUnitSystem;

        if (_pendingUnitSystem != null && _pendingUnitSystem == fsUnitSystem) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _pendingUnitSystem = null);
          });
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: repo.itemsStream(widget.listId),
          builder: (context, itemsSnap) {
            final docs = itemsSnap.data?.docs ?? [];
            final isLoading = itemsSnap.connectionState == ConnectionState.waiting;

            return Scaffold(
              appBar: AppBar(
                title: Text(widget.listName),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.menu_book_rounded),
                    tooltip: 'Managed Recipes',
                    onPressed: (docs.isEmpty || isLoading)
                        ? null
                        : () => _showRecipes(docs),
                  ),
                ],
              ),
              // ✅ NEW: Add Button for Manual Entry
              floatingActionButton: FloatingActionButton(
                onPressed: () => ShoppingItemAddSheet.show(context, widget.listId),
                backgroundColor: Colors.black,
                child: const Icon(Icons.add, color: Colors.white),
              ),
              body: Column(
                children: [
                  _TopControls(
                    unitSystem: unitSystem,
                    disabled: _savingPrefs,
                    onChangeUnit: (u) => _setPrefs(unitSystem: u),
                  ),
                  Expanded(
                    child: _buildItemsList(
                      docs: docs,
                      isLoading: isLoading,
                      error: itemsSnap.error,
                      unitSystem: unitSystem,
                      repo: repo,
                      isCache: itemsSnap.data?.metadata.isFromCache == true ||
                               itemsSnap.data?.metadata.hasPendingWrites == true,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildItemsList({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required bool isLoading,
    required Object? error,
    required String unitSystem,
    required ShoppingRepo repo,
    required bool isCache,
  }) {
    if (isLoading && docs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Couldn’t load items.\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (docs.isEmpty) {
      return const Center(child: Text('No items yet'));
    }

    // Sort: unchecked first, then A-Z
    final sorted = [...docs];
    sorted.sort((a, b) {
      final ac = (a.data()['checked'] ?? false) == true;
      final bc = (b.data()['checked'] ?? false) == true;
      if (ac != bc) return ac ? 1 : -1;

      final an = (a.data()['nameLower'] ?? a.data()['name'] ?? '').toString();
      final bn = (b.data()['nameLower'] ?? b.data()['name'] ?? '').toString();
      return an.compareTo(bn);
    });

    // Group by section
    final groups = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    
    for (final d in sorted) {
      final data = d.data();
      // Use standard logic (since you are recreating lists to fix old data)
      final section = ShoppingEngine.sectionForItem(data) ?? 'Other';
      groups.putIfAbsent(section, () => []).add(d);
    }

    final groupKeys = groups.keys.toList();
    groupKeys.sort((a, b) {
      // Updated Sort Order
      const order = [
        'Fresh',
        'Pantry',
        'Chilled & Frozen',
        'Other'
      ];
      final ia = order.indexOf(a);
      final ib = order.indexOf(b);
      
      if (ia != -1 || ib != -1) {
        return (ia == -1 ? 999 : ia).compareTo(ib == -1 ? 999 : ib);
      }
      return a.compareTo(b);
    });

    int totalRows() {
      var count = 0;
      for (final k in groupKeys) {
        final items = groups[k] ?? [];
        if (k.trim().isNotEmpty) count += 1; // Header
        count += items.length;
      }
      return count;
    }

    return Column(
      children: [
        if (isCache)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: Colors.black.withOpacity(0.04),
            child: Text(
              'Syncing changes...',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black.withOpacity(0.65),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80), // Extra bottom pad for FAB
            itemCount: totalRows(),
            itemBuilder: (context, index) {
              var cursor = 0;

              for (final k in groupKeys) {
                final items = groups[k] ?? [];

                if (k.trim().isNotEmpty) {
                  if (index == cursor) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 8),
                      child: Text(
                        k.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.black.withOpacity(0.65),
                          letterSpacing: 0.6,
                        ),
                      ),
                    );
                  }
                  cursor += 1;
                }

                if (index < cursor + items.length) {
                  final d = items[index - cursor];
                  return _ItemRow(
                    doc: d,
                    unitSystem: unitSystem,
                    onToggle: (checked) => repo.toggleItem(
                      listId: widget.listId,
                      itemId: d.id,
                      checked: checked,
                    ),
                    onRemove: () => _confirmRemoveItem(d, repo),
                  );
                }

                cursor += items.length;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRemoveItem(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    ShoppingRepo repo,
  ) async {
    final data = d.data();
    final name = (data['name'] ?? '').toString().trim();
    final textFallback = (data['text'] ?? '').toString().trim();
    final displayName = name.isNotEmpty
        ? name
        : (textFallback.isNotEmpty ? textFallback : '(Item)');

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove item?'),
            content: Text('Remove "$displayName"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    await repo.deleteItem(listId: widget.listId, itemId: d.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Item removed')),
    );
  }
}

class _TopControls extends StatelessWidget {
  final String unitSystem; // metric|us
  final bool disabled;
  final ValueChanged<String> onChangeUnit;

  const _TopControls({
    required this.unitSystem,
    required this.onChangeUnit,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip({
      required bool selected,
      required String label,
      required VoidCallback onTap,
    }) {
      return Opacity(
        opacity: disabled ? 0.55 : 1,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.black.withOpacity(0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.black.withOpacity(0.10)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: Colors.black.withOpacity(0.75),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Colors.black.withOpacity(0.08))),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip(
            selected: unitSystem == 'metric',
            label: 'Metric',
            onTap: () => onChangeUnit('metric'),
          ),
          chip(
            selected: unitSystem == 'us',
            label: 'US',
            onTap: () => onChangeUnit('us'),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String unitSystem;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  const _ItemRow({
    required this.doc,
    required this.unitSystem,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();

    final name = (data['name'] ?? '').toString().trim();
    final textFallback = (data['text'] ?? '').toString().trim();
    final displayName =
        name.isNotEmpty ? name : (textFallback.isNotEmpty ? textFallback : '(Item)');

    final checked = (data['checked'] ?? false) == true;

    final subtitle = ShoppingEngine.buildSecondaryLine(
      data,
      unitSystem: unitSystem,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: CheckboxListTile(
              value: checked,
              onChanged: (v) => onToggle(v ?? false),
              title: Text(
                displayName,
                style: TextStyle(
                  decoration: checked ? TextDecoration.lineThrough : null,
                  color: checked ? Colors.black.withOpacity(0.5) : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: (subtitle == null || subtitle.trim().isEmpty)
                  ? null
                  : Text(
                      subtitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withOpacity(0.55),
                      ),
                    ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Remove item',
            icon: Icon(Icons.close_rounded,
                color: Colors.black.withOpacity(0.55)),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

String _unitSystemFromAny(dynamic raw) {
  if (raw is String) {
    final s = raw.trim().toLowerCase();
    if (s == 'us' || s == 'imperial') return 'us';
    return 'metric';
  }
  if (raw is num) {
    return (raw.toInt() == 2) ? 'us' : 'metric';
  }
  return 'metric';
}
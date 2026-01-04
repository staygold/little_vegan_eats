// lib/lists/lists_hub_screen.dart
import 'dart:ui' show FontVariation;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'shopping_repo.dart';
import 'shopping_list_detail_screen.dart';

class ListsHubScreen extends StatefulWidget {
  const ListsHubScreen({super.key});

  @override
  State<ListsHubScreen> createState() => _ListsHubScreenState();
}

class _ListsHubScreenState extends State<ListsHubScreen> {
  final _repo = ShoppingRepo.instance;

  static const Color _panelBg = Color(0xFFECF3F4);

  // ✅ Rounded top corners for the inner panel (same vibe as meal plan hub)
  static const BorderRadius _topRadius = BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(20),
  );

  TextStyle _hubTitleStyle(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 1.0,
      height: 1.0,
    );
  }

  Future<void> _createListDialog() async {
    final ctrl = TextEditingController();

    final name = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create shopping list'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'List name',
            hintText: 'e.g. Weekly shop',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return;

    try {
      await _repo.createList(trimmed);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create list: $e')),
      );
    }
  }

  Future<void> _confirmDeleteList({
    required String listId,
    required String listName,
  }) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete list?'),
            content: Text('Delete "$listName" and all items inside it?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    try {
      await _repo.deleteList(listId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('List deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete list: $e')),
      );
    }
  }

  Widget _listCard({
    required String title,
    required VoidCallback onTap,
    required String listId,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chevron_right),
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  _confirmDeleteList(listId: listId, listName: title);
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete'),
                ),
              ],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No shopping lists yet',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text('Create one to start adding items.'),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _createListDialog,
                child: const Text('Create your first list'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = _hubTitleStyle(context);

    // ✅ Outer wrapper background band (same concept as meal plan hub)
    final topBandColor = AppColors.brandDark;

    return Scaffold(
      backgroundColor: _panelBg,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _repo.listsStream(),
        builder: (context, snap) {
          // We keep the same “grey rounded panel” shell even while loading/error
          Widget innerContent;

          if (snap.connectionState == ConnectionState.waiting) {
            innerContent = const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Center(child: CircularProgressIndicator()),
            );
          } else if (snap.hasError) {
            innerContent = Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Could not load lists:\n${snap.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          } else {
            final docs = snap.data?.docs ?? [];

            if (docs.isEmpty) {
              innerContent = _emptyState();
            } else {
              innerContent = Column(
                children: [
                  const SizedBox(height: 10),
                  for (final d in docs)
                    Builder(
                      builder: (_) {
                        final data = d.data();
                        final name = (data['name'] ?? '').toString().trim();
                        final displayName = name.isEmpty ? 'Untitled list' : name;

                        return _listCard(
                          title: displayName,
                          listId: d.id,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ShoppingListDetailScreen(
                                  listId: d.id,
                                  listName: displayName,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  const SizedBox(height: 12),
                ],
              );
            }
          }

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // ✅ Top band + rounded grey panel
              Container(
                color: topBandColor,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 12,
                ),
                child: Material(
                  color: _panelBg,
                  shape: const RoundedRectangleBorder(borderRadius: _topRadius),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ✅ Header row (matches meal plan hub pattern)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 8, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('SHOPPING LISTS', style: titleStyle),
                            ),
                            IconButton(
                              tooltip: 'Create list',
                              icon: const Icon(Icons.add),
                              onPressed: _createListDialog,
                            ),
                          ],
                        ),
                      ),

                      // ✅ Content
                      innerContent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// lib/lists/shopping_list_picker_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'shopping_repo.dart';
import 'shopping_list_detail_screen.dart';

class ShoppingListPickerSheet {
  ShoppingListPickerSheet._();

  static Future<void> open(
    BuildContext context, {
    required int recipeId,
    required String recipeTitle,
    required List<ShoppingIngredient> ingredients,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _Sheet(
        recipeId: recipeId,
        recipeTitle: recipeTitle,
        ingredients: ingredients,
      ),
    );
  }
}

class _Sheet extends StatefulWidget {
  final int recipeId;
  final String recipeTitle;
  final List<ShoppingIngredient> ingredients;

  const _Sheet({
    required this.recipeId,
    required this.recipeTitle,
    required this.ingredients,
  });

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  final _repo = ShoppingRepo.instance;

  bool _creating = false;
  bool _adding = false;

  final _nameCtrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _createAndAdd() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _creating = true);
    try {
      final ref = await _repo.createList(name);

      await _repo.addIngredients(
        listId: ref.id,
        ingredients: widget.ingredients,
        recipeId: widget.recipeId,
        recipeTitle: widget.recipeTitle,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // close sheet

      // Go straight into the list
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShoppingListDetailScreen(
            listId: ref.id,
            listName: name,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn’t create list: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _addToExisting({
    required String listId,
    required String listName,
  }) async {
    if (_adding) return;

    setState(() => _adding = true);
    try {
      await _repo.addIngredients(
        listId: listId,
        ingredients: widget.ingredients,
        recipeId: widget.recipeId,
        recipeTitle: widget.recipeTitle,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // close sheet

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to "$listName"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn’t add items: $e')),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomPad),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // grab handle
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
            ),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Add to shopping list',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Colors.black.withOpacity(0.85),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: Colors.black.withOpacity(0.65)),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Create new list
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withOpacity(0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create new list',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.black.withOpacity(0.80),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameCtrl,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _createAndAdd(),
                    decoration: InputDecoration(
                      hintText: 'e.g. Weekly shop',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.black.withOpacity(0.10)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.black.withOpacity(0.10)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.black.withOpacity(0.22), width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      onPressed: _creating ? null : _createAndAdd,
                      child: _creating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create & add'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Existing lists
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your lists',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.black.withOpacity(0.80),
                ),
              ),
            ),
            const SizedBox(height: 8),

            Flexible(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _repo.listsStream(),
                builder: (context, snap) {
                  final docs = snap.data?.docs ?? const [];

                  if (snap.connectionState == ConnectionState.waiting && docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text('Couldn’t load lists: ${snap.error}'),
                    );
                  }

                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'No lists yet. Create one above.',
                        style: TextStyle(color: Colors.black.withOpacity(0.65)),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.black.withOpacity(0.06)),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final data = d.data();
                      final name = (data['name'] ?? 'Shopping List').toString();

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          widget.recipeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.black.withOpacity(0.55)),
                        ),
                        trailing: _adding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_rounded),
                        onTap: () => _addToExisting(listId: d.id, listName: name),
                      );
                    },
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

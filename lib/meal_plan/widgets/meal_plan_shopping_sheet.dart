// lib/meal_plan/widgets/meal_plan_shopping_sheet.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../lists/shopping_repo.dart';
import '../../recipes/recipe_repository.dart';
import '../core/meal_plan_keys.dart';
import '../core/meal_plan_slots.dart';

class MealPlanShoppingSheet extends StatefulWidget {
  final Map<String, dynamic> planData; // 'type': 'week' or 'day'
  final Map<int, String> knownTitles;  // Pass titles to load instantly

  const MealPlanShoppingSheet({
    super.key,
    required this.planData,
    this.knownTitles = const {},
  });

  static Future<void> show(
    BuildContext context, 
    Map<String, dynamic> planData,
    Map<int, String> knownTitles,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MealPlanShoppingSheet(
        planData: planData,
        knownTitles: knownTitles,
      ),
    );
  }

  @override
  State<MealPlanShoppingSheet> createState() => _MealPlanShoppingSheetState();
}

class _MealPlanShoppingSheetState extends State<MealPlanShoppingSheet> {
  // Step 0 = Select Meals, Step 1 = Select List
  int _step = 0;
  final PageController _pageCtrl = PageController();

  // Selection State
  final Set<String> _selectedKeys = {};
  final Map<String, int> _slotToRecipeId = {};
  late Map<int, String> _titles;

  // List Picker State
  final _listNameCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titles = Map.from(widget.knownTitles);
    _parsePlan();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _listNameCtrl.dispose();
    super.dispose();
  }

  void _parsePlan() {
    final type = widget.planData['type'] ?? 'week';
    
    void processDay(String dayKey, Map dayData) {
      for (final slot in MealPlanSlots.order) {
        final entry = dayData[slot];
        if (entry is Map && (entry['kind'] == 'recipe' || entry.containsKey('recipeId'))) {
          final rawId = entry['recipeId'] ?? entry['id'];
          final rid = int.tryParse(rawId.toString());
          
          if (rid != null) {
            final key = '$dayKey|$slot';
            _slotToRecipeId[key] = rid;
            _selectedKeys.add(key); // Default: Checked
            
            if (!_titles.containsKey(rid)) {
               _titles[rid] = 'Recipe #$rid'; 
            }
          }
        }
      }
    }

    if (type == 'day') {
      final day = widget.planData['day'];
      if (day is Map) processDay('Today', day);
    } else {
      final days = widget.planData['days'];
      if (days is Map) {
        final keys = days.keys.toList()..sort();
        for (final k in keys) {
          if (days[k] is Map) processDay(k.toString(), days[k]);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LOGIC
  // ---------------------------------------------------------------------------

  void _goToStep2() {
    if (_selectedKeys.isEmpty) return;
    setState(() => _step = 1);
    _pageCtrl.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _goBack() {
    setState(() => _step = 0);
    _pageCtrl.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _executeAdd({String? existingListId, String? newListName}) async {
    setState(() => _isLoading = true);

    try {
      String listId = existingListId ?? '';
      
      if (newListName != null && newListName.trim().isNotEmpty) {
        final ref = await ShoppingRepo.instance.createList(newListName.trim());
        listId = ref.id;
      }

      if (listId.isEmpty) throw Exception('No list selected');

      int count = 0;
      
      for (final key in _selectedKeys) {
        final rid = _slotToRecipeId[key];
        if (rid == null) continue;

        // Fetch & Parse (Cached in Repo usually)
        final recipe = await RecipeRepository.getRecipeById(rid);
        final ingredients = _parseWprmIngredients(recipe);
        
        if (ingredients.isEmpty) continue;

        final title = _titles[rid] ?? 'Recipe';

        await ShoppingRepo.instance.addIngredients(
          listId: listId,
          ingredients: ingredients,
          recipeId: rid,
          recipeTitle: title,
        );
        count++;
      }

      if (!mounted) return;
      Navigator.of(context).pop(); 
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $count meals to shopping list')),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Reuse your parsing logic
  List<ShoppingIngredient> _parseWprmIngredients(Map<String, dynamic> recipe) {
    final List<ShoppingIngredient> out = [];
    var root = recipe;
    if (recipe.containsKey('recipe') && recipe['recipe'] is Map) {
      root = recipe['recipe'];
    }

    final rawFlat = root['ingredients_flat'];
    if (rawFlat is List) {
       for (final item in rawFlat) {
         if (item is Map) _parseSingle(item, out);
       }
       return out;
    }

    final rawGroups = root['ingredients'];
    if (rawGroups is List) {
      for (final group in rawGroups) {
        if (group is Map) {
          final items = group['ingredients'];
          if (items is List) {
            for (final item in items) {
               if (item is Map) _parseSingle(item, out);
            }
          }
        }
      }
    }
    return out;
  }

  void _parseSingle(Map item, List<ShoppingIngredient> out) {
    final name = (item['name'] ?? '').toString();
    if (name.isEmpty) return;
    
    final amount = (item['amount'] ?? '').toString();
    final unit = (item['unit'] ?? '').toString();
    final notes = (item['notes'] ?? '').toString();

    out.add(ShoppingIngredient(
      name: name,
      amount: amount,
      unit: unit,
      notes: notes,
      metricAmount: amount, 
      metricUnit: unit,
      usAmount: amount,
      usUnit: unit,
    ));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(0, 12, 0, 0),
      height: MediaQuery.of(context).size.height * 0.80, 
      child: Column(
        children: [
          // --- Grab Handle ---
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
          ),

          // --- Header ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (_step == 1)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _goBack,
                  )
                else
                  const Icon(Icons.shopping_cart_outlined, size: 24),
                
                const SizedBox(width: 12),
                
                Expanded(
                  child: Text(
                    _step == 0 ? "Select Meals" : "Select List", 
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Colors.black.withOpacity(0.85),
                    ),
                  ),
                ),
                
                // Close 'X' Button
                IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.black.withOpacity(0.65)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          
          if (_isLoading) const LinearProgressIndicator(),

          // --- Pages ---
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(), // Disable swipe
              children: [
                _buildStep1SelectMeals(bottomPad),
                _buildStep2SelectList(bottomPad),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 1: Checklist ---
  Widget _buildStep1SelectMeals(double bottomPad) {
    final isDayMode = widget.planData['type'] == 'day';

    // Group keys by Day
    final grouped = <String, List<String>>{};
    for (final key in _slotToRecipeId.keys) {
      final day = key.split('|').first;
      grouped.putIfAbsent(day, () => []).add(key);
    }
    
    final days = grouped.keys.toList()..sort();

    return Column(
      children: [
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(bottom: 80 + bottomPad),
            itemCount: days.length,
            itemBuilder: (ctx, i) {
              final dayKey = days[i];
              final slotKeys = grouped[dayKey]!;
              
              // Sort: Breakfast -> Lunch -> Dinner -> Snacks
              slotKeys.sort((a, b) {
                final sa = a.split('|').last.toLowerCase();
                final sb = b.split('|').last.toLowerCase();
                
                int score(String s) {
                  if (s.contains('breakfast')) return 1;
                  if (s.contains('lunch')) return 2;
                  if (s.contains('dinner')) return 3;
                  if (s.contains('snack')) return 4;
                  return 99;
                }
                final scoreA = score(sa);
                final scoreB = score(sb);
                
                if (scoreA != scoreB) return scoreA.compareTo(scoreB);
                return sa.compareTo(sb); 
              });

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isDayMode)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: const Color(0xFFF5F5F5),
                      child: Text(_prettyDay(dayKey), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    
                  ...slotKeys.map((key) {
                    final slot = key.split('|').last;
                    final rid = _slotToRecipeId[key];
                    final title = _titles[rid] ?? 'Loading...';
                    final isSelected = _selectedKeys.contains(key);

                    return CheckboxListTile(
                      value: isSelected,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        slot.toUpperCase(), 
                        style: TextStyle(
                          fontSize: 11, 
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withOpacity(0.5)
                        )
                      ),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) _selectedKeys.add(key);
                          else _selectedKeys.remove(key);
                        });
                      },
                    );
                  }),
                ],
              );
            },
          ),
        ),
        
        // Footer Button
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _selectedKeys.isEmpty ? null : _goToStep2,
              child: Text('Add ${_selectedKeys.length} items to List'),
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 2: Pick Destination (Restyled to match ShoppingListPickerSheet) ---
  Widget _buildStep2SelectList(double bottomPad) {
    return Column(
      children: [
        const SizedBox(height: 10),
        
        // Create new list container
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
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
                  controller: _listNameCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'e.g. Week 1 Shop',
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
                  onSubmitted: (v) {
                     if (_listNameCtrl.text.trim().isNotEmpty) {
                       _executeAdd(newListName: _listNameCtrl.text.trim());
                     }
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: _isLoading ? null : () {
                      if (_listNameCtrl.text.trim().isNotEmpty) {
                        _executeAdd(newListName: _listNameCtrl.text.trim());
                      }
                    },
                    child: _isLoading 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Create & add'),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // "Your lists" header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Your lists',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black.withOpacity(0.80),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ShoppingRepo.instance.listsStream(),
            builder: (ctx, snap) {
              final docs = snap.data?.docs ?? [];
              
              if (snap.connectionState == ConnectionState.waiting && docs.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('No lists yet. Create one above.', style: TextStyle(color: Colors.black.withOpacity(0.6))),
                );
              }

              return ListView.separated(
                padding: EdgeInsets.fromLTRB(0, 0, 0, 16 + bottomPad),
                itemCount: docs.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.black.withOpacity(0.06)),
                itemBuilder: (ctx, i) {
                  final d = docs[i];
                  final name = d.data()['name'] ?? 'Shopping List';
                  
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      name, 
                      style: const TextStyle(fontWeight: FontWeight.w700)
                    ),
                    trailing: const Icon(Icons.add_rounded),
                    onTap: _isLoading ? null : () => _executeAdd(existingListId: d.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _prettyDay(String dayKey) {
    if (dayKey == 'Today') return 'Today';
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return dayKey;
    const w = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${w[dt.weekday-1]} ${dt.day}';
  }
}
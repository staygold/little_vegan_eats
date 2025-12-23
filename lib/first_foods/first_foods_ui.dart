import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Firestore layout:
/// users/{uid}/firstFoods/{childId}
/// {
///   items: [
///     { id: "banana", name: "Banana", tries: [true,false,false], note: "Loved it", isCustom: false },
///     { id: "other_1703312345123", name: "Chickpea pancake", tries: [...], note: "...", isCustom: true },
///     ...
///   ],
///   updatedAt: serverTimestamp
/// }
///
/// Notes:
/// - Base list is fixed-for-everyone (100 foods list)
/// - Each food can be tried 3 times (tries[0..2])
/// - Note per food
/// - "Other" lets user add custom foods (still 3 tries + note)

class FirstFoodsOverviewTile extends StatelessWidget {
  final String childId;
  final String childName;

  const FirstFoodsOverviewTile({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('firstFoods')
        .doc(childId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        int triedCount = 0;
        final data = snap.data?.data();
        final items = (data?['items'] as List?) ?? [];

        for (final it in items) {
          if (it is! Map) continue;
          final tries = it['tries'];
          if (tries is List && tries.any((x) => x == true)) {
            triedCount += 1;
          }
        }

        // We always present the base goal as 100 (the fixed list)
        const total = 100;

        return Card(
          child: ListTile(
            title: const Text('100 First Foods'),
            subtitle: Text('$triedCount of $total tried'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FirstFoodsScreen(
                    childId: childId,
                    childName: childName,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class FirstFoodsScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const FirstFoodsScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<FirstFoodsScreen> createState() => _FirstFoodsScreenState();
}

class _FirstFoodsScreenState extends State<FirstFoodsScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  DocumentReference<Map<String, dynamic>>? _docRef() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('firstFoods')
        .doc(widget.childId);
  }

  @override
  void initState() {
    super.initState();
    _ensureDoc();
    _searchCtrl.addListener(() {
      final v = _searchCtrl.text.trim().toLowerCase();
      if (v != _q && mounted) setState(() => _q = v);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureDoc() async {
    final ref = _docRef();
    if (ref == null) return;

    final snap = await ref.get();
    if (snap.exists) return;

    final seeded = _firstFoods
        .map((f) => {
              'id': f.id,
              'name': f.name,
              'tries': [false, false, false],
              'note': '',
              'isCustom': false,
            })
        .toList();

    await ref.set({
      'items': seeded,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  int _triedCount(List items) {
    int c = 0;
    for (final it in items) {
      if (it is! Map) continue;
      final tries = it['tries'];
      if (tries is List && tries.any((x) => x == true)) c += 1;
    }
    return c;
  }

  Future<void> _addOtherFood({
    required DocumentReference<Map<String, dynamic>> ref,
  }) async {
    final ctrl = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add a food'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Chickpea pancake',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;

    final newId = 'other_${DateTime.now().millisecondsSinceEpoch}';
    final newItem = {
      'id': newId,
      'name': name.trim(),
      'tries': [false, false, false],
      'note': '',
      'isCustom': true,
    };

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final raw = (data['items'] as List?) ?? [];

      final items = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      items.add(newItem);

      tx.set(
        ref,
        {
          'items': items,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = _docRef();
    if (ref == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} • 100 First Foods'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: ${snap.error}'),
            );
          }

          final data = snap.data?.data() ?? {};
          final items = (data['items'] as List?) ?? [];

          final tried = _triedCount(items);
          const total = 100;

          // Search filter
          final visible = items.where((it) {
            if (_q.isEmpty) return true;
            if (it is! Map) return false;
            final name = (it['name'] ?? '').toString().toLowerCase();
            return name.contains(_q);
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Search foods',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$tried of $total tried',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),

              // ✅ Other (free text)
              Card(
                child: ListTile(
                  title: const Text('Other (add your own)'),
                  subtitle: const Text('Add a custom food'),
                  leading: const Icon(Icons.add),
                  onTap: () async {
                    await _addOtherFood(ref: ref);
                  },
                ),
              ),
              const SizedBox(height: 8),

              ...visible.map((it) {
                if (it is! Map) return const SizedBox.shrink();

                final id = (it['id'] ?? '').toString();
                final name = (it['name'] ?? '').toString();

                final tries = (it['tries'] is List)
                    ? List<bool>.from(it['tries'])
                    : <bool>[false, false, false];

                final triedAny = tries.any((x) => x == true);

                return Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(
                      triedAny
                          ? 'Tried: ${tries.where((x) => x).length}/3'
                          : 'Not tried yet',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => _FoodDetailSheet(
                          childId: widget.childId,
                          foodId: id,
                          initialName: name,
                          initialTries: tries,
                          initialNote: (it['note'] ?? '').toString(),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}

class _FoodDetailSheet extends StatefulWidget {
  final String childId;
  final String foodId;
  final String initialName;
  final List<bool> initialTries;
  final String initialNote;

  const _FoodDetailSheet({
    required this.childId,
    required this.foodId,
    required this.initialName,
    required this.initialTries,
    required this.initialNote,
  });

  @override
  State<_FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends State<_FoodDetailSheet> {
  bool _saving = false;
  late List<bool> _tries;
  late TextEditingController _noteCtrl;

  DocumentReference<Map<String, dynamic>>? _docRef() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('firstFoods')
        .doc(widget.childId);
  }

  @override
  void initState() {
    super.initState();
    _tries = List<bool>.from(widget.initialTries);
    if (_tries.length != 3) _tries = [false, false, false];
    _noteCtrl = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ref = _docRef();
    if (ref == null) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? {};
        final raw = (data['items'] as List?) ?? [];

        final items = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final idx = items.indexWhere(
          (e) => (e['id'] ?? '').toString() == widget.foodId,
        );

        final updatedItem = {
          'id': widget.foodId,
          'name': widget.initialName,
          'tries': _tries,
          'note': _noteCtrl.text.trim(),
          'isCustom': (idx >= 0) ? (items[idx]['isCustom'] == true) : false,
        };

        if (idx >= 0) {
          items[idx] = updatedItem;
        } else {
          items.add(updatedItem);
        }

        tx.set(
          ref,
          {
            'items': items,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.initialName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tried (up to 3 times)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(3, (i) {
              final label = 'Try ${i + 1}';
              return Expanded(
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  value: _tries[i],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _tries[i] = (v == true)),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'e.g. gagged, loved it, try again steamed, etc.',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'SAVING…' : 'SAVE'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Food {
  final String id;
  final String name;
  const _Food(this.id, this.name);
}

/// Fixed-for-everyone 100 foods.
/// Keep IDs stable once users start saving.
///
/// NOTE: your list below is currently 99 items in your paste.
/// Add one more to make it 100 (or keep it and rely on "Other").
/// If you want EXACT 100 fixed foods, add an item here.
const List<_Food> _firstFoods = [
  _Food('avocado', 'Avocado'),
  _Food('banana', 'Banana'),
  _Food('apple_puree', 'Apple (puree)'),
  _Food('pear_puree', 'Pear (puree)'),
  _Food('mango', 'Mango'),
  _Food('blueberries', 'Blueberries'),
  _Food('strawberries', 'Strawberries'),
  _Food('raspberries', 'Raspberries'),
  _Food('blackberries', 'Blackberries'),
  _Food('orange_segments', 'Orange (segments)'),
  _Food('watermelon', 'Watermelon'),
  _Food('kiwi', 'Kiwi'),
  _Food('peach', 'Peach'),
  _Food('plum', 'Plum'),
  _Food('apricot', 'Apricot'),
  _Food('cherries', 'Cherries'),
  _Food('grapes_quartered', 'Grapes (quartered)'),
  _Food('papaya', 'Papaya'),
  _Food('pineapple', 'Pineapple'),
  _Food('pomegranate', 'Pomegranate arils'),
  _Food('cucumber', 'Cucumber'),
  _Food('tomato', 'Tomato'),
  _Food('capsicum', 'Capsicum'),
  _Food('zucchini', 'Zucchini'),
  _Food('pumpkin', 'Pumpkin'),
  _Food('sweet_potato', 'Sweet potato'),
  _Food('potato', 'Potato'),
  _Food('carrot', 'Carrot'),
  _Food('broccoli', 'Broccoli'),
  _Food('cauliflower', 'Cauliflower'),
  _Food('peas', 'Peas'),
  _Food('corn', 'Corn'),
  _Food('spinach', 'Spinach'),
  _Food('kale', 'Kale'),
  _Food('green_beans', 'Green beans'),
  _Food('mushrooms', 'Mushrooms'),
  _Food('onion_cooked', 'Onion (cooked)'),
  _Food('garlic_cooked', 'Garlic (cooked)'),
  _Food('eggplant', 'Eggplant'),
  _Food('beetroot', 'Beetroot'),
  _Food('lentils_red', 'Red lentils'),
  _Food('lentils_brown', 'Brown lentils'),
  _Food('chickpeas', 'Chickpeas'),
  _Food('black_beans', 'Black beans'),
  _Food('kidney_beans', 'Kidney beans'),
  _Food('cannellini', 'Cannellini beans'),
  _Food('edamame', 'Edamame'),
  _Food('tofu', 'Tofu'),
  _Food('tempeh', 'Tempeh'),
  _Food('oats', 'Oats'),
  _Food('rice', 'Rice'),
  _Food('quinoa', 'Quinoa'),
  _Food('pasta', 'Pasta'),
  _Food('bread', 'Bread'),
  _Food('couscous', 'Couscous'),
  _Food('polenta', 'Polenta'),
  _Food('buckwheat', 'Buckwheat'),
  _Food('barley', 'Barley'),
  _Food('chia', 'Chia seeds'),
  _Food('flax', 'Flaxseed'),
  _Food('hemp', 'Hemp seeds'),
  _Food('sunflower_seed', 'Sunflower seeds'),
  _Food('pumpkin_seed', 'Pumpkin seeds'),
  _Food('sesame_seed', 'Sesame seeds'),
  _Food('tahini', 'Tahini'),
  _Food('peanut_butter', 'Peanut butter'),
  _Food('almond_butter', 'Almond butter'),
  _Food('cashew_butter', 'Cashew butter'),
  _Food('walnut', 'Walnut'),
  _Food('hazelnut', 'Hazelnut'),
  _Food('pistachio', 'Pistachio'),
  _Food('coconut', 'Coconut'),
  _Food('soy_yogurt', 'Soy yogurt'),
  _Food('oat_milk', 'Oat milk'),
  _Food('soy_milk', 'Soy milk'),
  _Food('almond_milk', 'Almond milk'),
  _Food('nutritional_yeast', 'Nutritional yeast'),
  _Food('olive_oil', 'Olive oil'),
  _Food('cinnamon', 'Cinnamon'),
  _Food('turmeric', 'Turmeric'),
  _Food('ginger', 'Ginger'),
  _Food('cumin', 'Cumin'),
  _Food('paprika', 'Paprika'),
  _Food('basil', 'Basil'),
  _Food('parsley', 'Parsley'),
  _Food('mint', 'Mint'),
  _Food('lemon', 'Lemon'),
  _Food('lime', 'Lime'),
  _Food('hummus', 'Hummus'),
  _Food('guacamole', 'Guacamole'),
  _Food('tomato_sauce', 'Tomato sauce'),
  _Food('peanut_sauce', 'Peanut sauce'),
  _Food('maple_syrup', 'Maple syrup'),
  _Food('date', 'Date'),
  _Food('prunes', 'Prunes'),
  _Food('figs', 'Figs'),
  _Food('cocoa', 'Cocoa'),
  _Food('vanilla', 'Vanilla'),
  _Food('water', 'Water (sips)'),
];

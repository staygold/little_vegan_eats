// lib/lists/shopping_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'shopping_engine.dart';

/// Structured ingredient (supports both metric + US if you have them from WPRM).
class ShoppingIngredient {
  final String name;

  // Legacy/single representation (still accepted)
  final String amount;
  final String unit;
  final String notes;

  // Dual representation (WPRM is source of truth)
  final String metricAmount;
  final String metricUnit;

  final String usAmount;
  final String usUnit;

  const ShoppingIngredient({
    required this.name,
    this.amount = '',
    this.unit = '',
    this.notes = '',
    this.metricAmount = '',
    this.metricUnit = '',
    this.usAmount = '',
    this.usUnit = '',
  });

  String displayLineMetric() {
    final a = metricAmount.trim();
    final u = metricUnit.trim();
    if (a.isEmpty && u.isEmpty) return displayLineLegacy();
    return _displayLine(amount: a, unit: u);
  }

  String displayLineUs() {
    final a = usAmount.trim();
    final u = usUnit.trim();
    if (a.isEmpty && u.isEmpty) return displayLineLegacy();
    return _displayLine(amount: a, unit: u);
  }

  String displayLineLegacy() =>
      _displayLine(amount: amount.trim(), unit: unit.trim());

  String _displayLine({required String amount, required String unit}) {
    final parts = <String>[];
    if (amount.isNotEmpty) parts.add(amount);
    if (unit.isNotEmpty) parts.add(unit);
    if (name.trim().isNotEmpty) parts.add(name.trim());

    var line = parts.join(' ').trim();
    final nt = notes.trim();
    if (nt.isNotEmpty) line = '$line ($nt)';
    return line.trim();
  }
}

class ShoppingRepo {
  ShoppingRepo._();
  static final instance = ShoppingRepo._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw Exception('Not logged in');
    return u.uid;
  }

  CollectionReference<Map<String, dynamic>> _listsCol() {
    return _db.collection('users').doc(_uid).collection('shoppingLists');
  }

  // Offline-friendly list ordering
  Query<Map<String, dynamic>> listsQuery() {
    return _listsCol().orderBy('updatedAtLocal', descending: true);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> listsStream() {
    return listsQuery().snapshots(includeMetadataChanges: true);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> listDocStream(String listId) {
    return _listsCol().doc(listId).snapshots(includeMetadataChanges: true);
  }

  Future<DocumentReference<Map<String, dynamic>>> createList(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('List name required');

    final now = Timestamp.now();

    return _listsCol().add({
      'name': trimmed,
      'unitSystem': 'metric', // metric|us
      'grouping': 'section',
      'createdAtLocal': now,
      'updatedAtLocal': now,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setListPrefs({
    required String listId,
    String? unitSystem, // metric|us
    String? grouping,
  }) async {
    final now = Timestamp.now();
    final update = <String, dynamic>{
      'updatedAtLocal': now,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (unitSystem != null) update['unitSystem'] = unitSystem;
    if (grouping != null) update['grouping'] = grouping;

    await _listsCol().doc(listId).set(update, SetOptions(merge: true));
  }

  CollectionReference<Map<String, dynamic>> _itemsCol(String listId) {
    return _listsCol().doc(listId).collection('items');
  }

  Query<Map<String, dynamic>> itemsQuery(String listId) {
    return _itemsCol(listId).orderBy('nameLower');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> itemsStream(String listId) {
    return itemsQuery(listId).snapshots(includeMetadataChanges: true);
  }

  Future<void> toggleItem({
    required String listId,
    required String itemId,
    required bool checked,
  }) async {
    final listRef = _listsCol().doc(listId);
    final itemRef = _itemsCol(listId).doc(itemId);
    final now = Timestamp.now();

    final batch = _db.batch();

    batch.set(itemRef, {'checked': checked}, SetOptions(merge: true));

    batch.set(
        listRef,
        {
          'updatedAtLocal': now,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> deleteItem({
    required String listId,
    required String itemId,
  }) async {
    final listRef = _listsCol().doc(listId);
    final now = Timestamp.now();

    final batch = _db.batch();
    batch.delete(_itemsCol(listId).doc(itemId));
    batch.set(
        listRef,
        {
          'updatedAtLocal': now,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> deleteList(String listId) async {
    final listRef = _listsCol().doc(listId);
    final itemsCol = _itemsCol(listId);

    while (true) {
      final snap = await itemsCol.limit(400).get();
      if (snap.docs.isEmpty) break;

      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }

    await listRef.delete();
  }

  // ===========================================================================
  // ADD ITEM (Manual Entry)
  // ===========================================================================

  Future<void> addItem({
    required String listId,
    required String name,
    required String amount,
    required String unit,
    required String section,
  }) async {
    // 1. Structure as ingredient (populate both metric/us so it shows up regardless)
    final ing = ShoppingIngredient(
      name: name,
      amount: amount,
      unit: unit,
      metricAmount: amount,
      metricUnit: unit,
      usAmount: amount,
      usUnit: unit,
    );

    // 2. Add via standard flow
    await addIngredients(
      listId: listId,
      ingredients: [ing],
      recipeId: null,
      recipeTitle: 'Manual',
    );

    // 3. Force override section (in case auto-classifier disagreed)
    final key = ShoppingEngine.normalizeKey(name);
    final itemRef = _itemsCol(listId).doc(key);

    await itemRef.set({
      'section': section,
      // Tag it as manual in sources if not already there
      'sources': FieldValue.arrayUnion([
        {'recipeTitle': 'Manual'}
      ]),
    }, SetOptions(merge: true));
  }

  // ===========================================================================
  // ADD INGREDIENTS (Stores recipe contributions)
  // ===========================================================================

  Future<void> addIngredients({
    required String listId,
    required List<ShoppingIngredient> ingredients,
    int? recipeId,
    String? recipeTitle,
  }) async {
    final cleaned = ingredients
        .map((i) => ShoppingIngredient(
              name: i.name.trim(),
              amount: i.amount.trim(),
              unit: i.unit.trim(),
              notes: i.notes.trim(),
              metricAmount: i.metricAmount.trim(),
              metricUnit: i.metricUnit.trim(),
              usAmount: i.usAmount.trim(),
              usUnit: i.usUnit.trim(),
            ))
        .where((i) => i.name.isNotEmpty)
        .toList();

    if (cleaned.isEmpty) return;

    final listRef = _listsCol().doc(listId);
    final itemsCol = _itemsCol(listId);
    final now = Timestamp.now();

    final Map<String, _Agg> agg = {};

    for (final ing in cleaned) {
      final key = ShoppingEngine.normalizeKey(ing.name);
      final canonical = ShoppingEngine.canonicalDisplayName(ing.name);
      final nameForDisplay =
          canonical.trim().isEmpty ? ing.name.trim() : canonical.trim();

      final entry =
          agg.putIfAbsent(key, () => _Agg(key: key, name: nameForDisplay));

      // Display examples
      final exMetric = ing.displayLineMetric();
      final exUs = ing.displayLineUs();
      final exLegacy = ing.displayLineLegacy();

      if (ing.metricAmount.isNotEmpty || ing.metricUnit.isNotEmpty) {
        entry.examplesMetric.add(exMetric);
      } else {
        entry.examples.add(exLegacy);
      }

      if (ing.usAmount.isNotEmpty || ing.usUnit.isNotEmpty) {
        entry.examplesUs.add(exUs);
      }

      // Section hint
      entry.section ??= ShoppingEngine.classifySection(
        canonicalNameLower: ing.name.toLowerCase(),
        unit: (ing.metricUnit.isNotEmpty ? ing.metricUnit : ing.unit),
      );

      // SUM metric (and track batch contribution)
      _trySumSameUnit(
        amount: ing.metricAmount.isNotEmpty ? ing.metricAmount : ing.amount,
        unit: ing.metricUnit.isNotEmpty ? ing.metricUnit : ing.unit,
        intoQty: (qty, normUnit) {
          entry.sumQtyMetric = (entry.sumQtyMetric ?? 0) + qty;
          entry.sumUnitMetric ??= normUnit;
          // Track for this batch
          entry.batchContribMetric = (entry.batchContribMetric ?? 0) + qty;
        },
      );

      // SUM us (and track batch contribution)
      _trySumSameUnit(
        amount: ing.usAmount,
        unit: ing.usUnit,
        intoQty: (qty, normUnit) {
          entry.sumQtyUs = (entry.sumQtyUs ?? 0) + qty;
          entry.sumUnitUs ??= normUnit;
          // Track for this batch
          entry.batchContribUs = (entry.batchContribUs ?? 0) + qty;
        },
      );

      entry.usedCount = (entry.usedCount ?? 0) + 1;
    }

    final keys = agg.keys.toList();
    if (keys.isEmpty) return;

    await _db.runTransaction((tx) async {
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> existing = {};

      // read existing items
      for (final k in keys) {
        existing[k] = await tx.get(itemsCol.doc(k));
      }

      tx.set(
          listRef,
          {
            'updatedAtLocal': now,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      for (final entry in agg.values) {
        final ref = itemsCol.doc(entry.key);
        final snap = existing[entry.key];

        // Prepare source object with contributions
        final newSource = <String, dynamic>{
          'recipeId': recipeId,
          'recipeTitle': (recipeTitle ?? '').trim(),
        };

        if (entry.batchContribMetric != null && entry.batchContribMetric! > 0) {
          newSource['contribMetric'] = entry.batchContribMetric;
          newSource['contribUnitMetric'] = entry.sumUnitMetric;
        }
        if (entry.batchContribUs != null && entry.batchContribUs! > 0) {
          newSource['contribUs'] = entry.batchContribUs;
          newSource['contribUnitUs'] = entry.sumUnitUs;
        }

        if (snap == null || !snap.exists) {
          // --- NEW ITEM ---
          final initialSources = <Map<String, dynamic>>[];
          if (recipeId != null || (recipeTitle ?? '').isNotEmpty) {
            initialSources.add(newSource);
          }

          tx.set(
              ref,
              {
                'key': entry.key,
                'name': entry.name,
                'nameLower': entry.name.toLowerCase(),
                'checked': false,
                'section': entry.section,
                'examples': _dedupeTake(entry.examples, 8),
                'examplesMetric': _dedupeTake(entry.examplesMetric, 8),
                'examplesUs': _dedupeTake(entry.examplesUs, 8),
                'sources': initialSources,
                'sumQtyMetric': entry.sumQtyMetric,
                'sumUnitMetric': entry.sumUnitMetric,
                'sumQtyUs': entry.sumQtyUs,
                'sumUnitUs': entry.sumUnitUs,
                'usedCount': entry.usedCount ?? 1,
                'addedAtLocal': now,
                'addedAt': FieldValue.serverTimestamp(),
                'updatedAtLocal': now,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
          continue;
        }

        // --- MERGE ---
        final data = snap.data() ?? <String, dynamic>{};
        final existingChecked = (data['checked'] ?? false) == true;

        final mergedExamples = _dedupeTake(
            [..._stringList(data['examples']), ...entry.examples], 8);
        final mergedExamplesMetric = _dedupeTake(
            [..._stringList(data['examplesMetric']), ...entry.examplesMetric],
            8);
        final mergedExamplesUs = _dedupeTake(
            [..._stringList(data['examplesUs']), ...entry.examplesUs], 8);

        // Merge sources
        final currentSources = _mapList(data['sources']);
        if (recipeId != null || (recipeTitle ?? '').isNotEmpty) {
          currentSources.add(newSource);
        }
        // Keep last 20 sources max
        final mergedSources = currentSources.length > 20
            ? currentSources.sublist(currentSources.length - 20)
            : currentSources;

        final nextUsed =
            (_asInt(data['usedCount']) ?? 0) + (entry.usedCount ?? 0);

        // Merge sums
        final nextMetric = _mergeSumSameUnit(
          existingQty: _asDouble(data['sumQtyMetric']),
          existingUnit: (data['sumUnitMetric'] ?? '').toString(),
          addQty: entry.sumQtyMetric,
          addUnit: entry.sumUnitMetric,
        );

        final nextUs = _mergeSumSameUnit(
          existingQty: _asDouble(data['sumQtyUs']),
          existingUnit: (data['sumUnitUs'] ?? '').toString(),
          addQty: entry.sumQtyUs,
          addUnit: entry.sumUnitUs,
        );

        tx.set(
            ref,
            {
              'checked': existingChecked,
              'name': (data['name'] ?? '').toString().trim().isNotEmpty
                  ? data['name']
                  : entry.name,
              'nameLower':
                  ((data['nameLower'] ?? '').toString().trim().isNotEmpty
                          ? data['nameLower']
                          : entry.name.toLowerCase())
                      .toString(),
              'section': (data['section'] ?? '').toString().trim().isNotEmpty
                  ? data['section']
                  : entry.section,
              'examples': mergedExamples,
              'examplesMetric': mergedExamplesMetric,
              'examplesUs': mergedExamplesUs,
              'sources': mergedSources,
              'sumQtyMetric': nextMetric.qty,
              'sumUnitMetric': nextMetric.unit,
              'sumQtyUs': nextUs.qty,
              'sumUnitUs': nextUs.unit,
              'usedCount': nextUsed,
              'updatedAtLocal': now,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
    });
  }

  // ===========================================================================
  // REMOVE RECIPE (Subtracts contributions)
  // ===========================================================================

  Future<void> removeRecipe({
    required String listId,
    required int recipeId,
  }) async {
    final itemsCol = _itemsCol(listId);
    final listRef = _listsCol().doc(listId);

    final snapshot = await itemsCol.get();
    final batch = _db.batch();
    var touched = false;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final sources = _mapList(data['sources']);

      // Find sources belonging to this recipe
      final sourcesToRemove = sources.where((s) {
        final rId = _asInt(s['recipeId']);
        return rId == recipeId;
      }).toList();

      if (sourcesToRemove.isEmpty) continue;

      touched = true;

      // Calculate how much to subtract
      double subMetric = 0;
      double subUs = 0;

      for (final s in sourcesToRemove) {
        subMetric += _asDouble(s['contribMetric']) ?? 0;
        subUs += _asDouble(s['contribUs']) ?? 0;
      }

      // Remove from sources list
      sources.removeWhere((s) => _asInt(s['recipeId']) == recipeId);

      // Check if item should be deleted
      if (sources.isEmpty) {
        batch.delete(doc.reference);
        continue;
      }

      // Otherwise, update quantity
      double? currentMetric = _asDouble(data['sumQtyMetric']);
      double? currentUs = _asDouble(data['sumQtyUs']);

      if (currentMetric != null) {
        currentMetric = (currentMetric - subMetric);
        if (currentMetric <= 0) currentMetric = null;
      }

      if (currentUs != null) {
        currentUs = (currentUs - subUs);
        if (currentUs <= 0) currentUs = null;
      }

      final newUsedCount = (_asInt(data['usedCount']) ?? 1) - 1;

      batch.update(doc.reference, {
        'sources': sources,
        'sumQtyMetric': currentMetric,
        'sumQtyUs': currentUs,
        'usedCount': newUsedCount < 0 ? 0 : newUsedCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (touched) {
      batch.set(
          listRef,
          {
            'updatedAtLocal': Timestamp.now(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      await batch.commit();
    }
  }

  // Old callers (string lines)
  Future<void> addItems({
    required String listId,
    required List<String> ingredients,
    int? recipeId,
    String? recipeTitle,
  }) async {
    final cleaned =
        ingredients.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (cleaned.isEmpty) return;

    final structured =
        cleaned.map((line) => ShoppingIngredient(name: line)).toList();

    return addIngredients(
      listId: listId,
      ingredients: structured,
      recipeId: recipeId,
      recipeTitle: recipeTitle,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _trySumSameUnit({
    required String amount,
    required String unit,
    required void Function(double qty, String normalizedUnit) intoQty,
  }) {
    final amt = ShoppingEngine.parseAmountToDouble(amount);
    final u = ShoppingEngine.normalizeUnit(unit);

    if (amt == null || amt <= 0) return;
    if (u.isEmpty) return;

    final isCooking = ShoppingEngine.isNonSummableCookingMeasure(u);
    final summable = ShoppingEngine.isSummableUnit(u);
    if (isCooking || !summable) return;

    intoQty(amt, u);
  }

  static List<String> _dedupeTake(List<String> items, int max) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in items) {
      final t = s.toString().trim();
      if (t.isEmpty) continue;
      if (seen.contains(t)) continue;
      seen.add(t);
      out.add(t);
      if (out.length >= max) break;
    }
    return out;
  }

  static List<String> _stringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  static List<Map<String, dynamic>> _mapList(dynamic v) {
    if (v is List) {
      return v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return const [];
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = (v ?? '').toString().trim();
    return int.tryParse(s);
  }

  static double? _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    final s = (v ?? '').toString().trim();
    return double.tryParse(s);
  }

  static ({double? qty, String? unit}) _mergeSumSameUnit({
    required double? existingQty,
    required String existingUnit,
    required double? addQty,
    required String? addUnit,
  }) {
    final exU = existingUnit.trim();
    final addU = (addUnit ?? '').trim();

    if (addQty == null || addQty <= 0 || addU.isEmpty) {
      return (qty: existingQty, unit: exU.isEmpty ? null : exU);
    }

    if (existingQty == null || existingQty <= 0 || exU.isEmpty) {
      return (qty: addQty, unit: addU);
    }

    if (exU == addU) {
      return (qty: existingQty + addQty, unit: exU);
    }

    return (qty: existingQty, unit: exU);
  }
}

class _Agg {
  final String key;
  String name;
  String? section;

  double? sumQtyMetric;
  String? sumUnitMetric;
  double? sumQtyUs;
  String? sumUnitUs;

  // Track current batch contribution
  double? batchContribMetric;
  double? batchContribUs;

  int? usedCount;

  final List<String> examples = [];
  final List<String> examplesMetric = [];
  final List<String> examplesUs = [];

  _Agg({required this.key, required this.name});
}
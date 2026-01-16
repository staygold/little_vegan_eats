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

  // ---------------------------------------------------------------------------
  // LIST CREATION (CAPPED: L01..L20)
  // ---------------------------------------------------------------------------

  static const List<String> _listSlots = [
    'L01', 'L02', 'L03', 'L04', 'L05',
    'L06', 'L07', 'L08', 'L09', 'L10',
    'L11', 'L12', 'L13', 'L14', 'L15',
    'L16', 'L17', 'L18', 'L19', 'L20',
  ];

  /// Create a new list using the first free slot docId (L01..L20).
  /// Rules must allow only these IDs (enforced cap).
  Future<DocumentReference<Map<String, dynamic>>> createList(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('List name required');

    final now = Timestamp.now();

    final slotId = await _findFreeListSlotId();
    if (slotId == null) {
      throw Exception(
        'You already have 20 shopping lists. Delete one to create another.',
      );
    }

    final ref = _listsCol().doc(slotId);

    await ref.set({
      'name': trimmed,
      'unitSystem': 'metric', // metric|us
      'grouping': 'section',
      'createdAtLocal': now,
      'updatedAtLocal': now,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return ref;
  }

  /// Returns the first available slot id (L01..L20), or null if full.
  /// Uses server to avoid offline "looks empty" creation.
  Future<String?> _findFreeListSlotId() async {
    final snap = await _listsCol().get(const GetOptions(source: Source.server));
    final used = snap.docs.map((d) => d.id).toSet();

    for (final slot in _listSlots) {
      if (!used.contains(slot)) return slot;
    }
    return null;
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
      SetOptions(merge: true),
    );

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
      SetOptions(merge: true),
    );
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

    await itemRef.set(
      {
        'section': section,
        // Tag it as manual in sources if not already there
        'sources': FieldValue.arrayUnion([
          {'recipeTitle': 'Manual'}
        ]),
      },
      SetOptions(merge: true),
    );
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
      // ✅ EXCLUDE plain water from shopping lists (tap/filtered/boiling/etc.)
      // Keeps "coconut water", "sparkling water", etc. (engine handles that)
      if (ShoppingEngine.shouldExcludeFromShoppingName(ing.name)) {
        continue;
      }

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
          entry.batchContribMetric = (entry.batchContribMetric ?? 0) + qty;
          entry.hasBatchMetric = true;
        },
      );

      // SUM us (and track batch contribution)
      _trySumSameUnit(
        amount: ing.usAmount,
        unit: ing.usUnit,
        intoQty: (qty, normUnit) {
          entry.sumQtyUs = (entry.sumQtyUs ?? 0) + qty;
          entry.sumUnitUs ??= normUnit;
          entry.batchContribUs = (entry.batchContribUs ?? 0) + qty;
          entry.hasBatchUs = true;
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
        SetOptions(merge: true),
      );

      for (final entry in agg.values) {
        final ref = itemsCol.doc(entry.key);
        final snap = existing[entry.key];

        // Base source object (we'll attach contrib ONLY if it merged)
        Map<String, dynamic> makeSource({
          required bool includeMetric,
          required bool includeUs,
          required String? metricUnit,
          required String? usUnit,
        }) {
          final s = <String, dynamic>{
            'recipeId': recipeId,
            'recipeTitle': (recipeTitle ?? '').trim(),
          };

          if (includeMetric &&
              entry.batchContribMetric != null &&
              entry.batchContribMetric! > 0 &&
              (metricUnit ?? '').trim().isNotEmpty) {
            s['contribMetric'] = entry.batchContribMetric;
            s['contribUnitMetric'] = metricUnit!.trim();
          }

          if (includeUs &&
              entry.batchContribUs != null &&
              entry.batchContribUs! > 0 &&
              (usUnit ?? '').trim().isNotEmpty) {
            s['contribUs'] = entry.batchContribUs;
            s['contribUnitUs'] = usUnit!.trim();
          }

          return s;
        }

        if (snap == null || !snap.exists) {
          // --- NEW ITEM ---
          final initialSources = <Map<String, dynamic>>[];
          if (recipeId != null || (recipeTitle ?? '').isNotEmpty) {
            // New item always "merges" because it's establishing sums
            initialSources.add(makeSource(
              includeMetric: entry.hasBatchMetric,
              includeUs: entry.hasBatchUs,
              metricUnit: entry.sumUnitMetric,
              usUnit: entry.sumUnitUs,
            ));
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
            SetOptions(merge: true),
          );
          continue;
        }

        // --- MERGE ---
        final data = snap.data() ?? <String, dynamic>{};
        final existingChecked = (data['checked'] ?? false) == true;

        final mergedExamples =
            _dedupeTake([..._stringList(data['examples']), ...entry.examples], 8);
        final mergedExamplesMetric = _dedupeTake(
          [..._stringList(data['examplesMetric']), ...entry.examplesMetric],
          8,
        );
        final mergedExamplesUs = _dedupeTake(
          [..._stringList(data['examplesUs']), ...entry.examplesUs],
          8,
        );

        // Decide if metric/us sums can merge into existing totals
        final exQtyMetric = _asDouble(data['sumQtyMetric']);
        final exUnitMetric = (data['sumUnitMetric'] ?? '').toString().trim();
        final addUnitMetric = (entry.sumUnitMetric ?? '').trim();

        final canMergeMetric = entry.hasBatchMetric &&
            entry.sumQtyMetric != null &&
            entry.sumQtyMetric! > 0 &&
            addUnitMetric.isNotEmpty &&
            (exQtyMetric == null ||
                exQtyMetric <= 0 ||
                exUnitMetric.isEmpty ||
                exUnitMetric == addUnitMetric);

        final exQtyUs = _asDouble(data['sumQtyUs']);
        final exUnitUs = (data['sumUnitUs'] ?? '').toString().trim();
        final addUnitUs = (entry.sumUnitUs ?? '').trim();

        final canMergeUs = entry.hasBatchUs &&
            entry.sumQtyUs != null &&
            entry.sumQtyUs! > 0 &&
            addUnitUs.isNotEmpty &&
            (exQtyUs == null ||
                exQtyUs <= 0 ||
                exUnitUs.isEmpty ||
                exUnitUs == addUnitUs);

        // Merge sources
        final currentSources = _mapList(data['sources']);
        if (recipeId != null || (recipeTitle ?? '').isNotEmpty) {
          // ✅ Only store contrib fields that actually merged into sums
          currentSources.add(makeSource(
            includeMetric: canMergeMetric,
            includeUs: canMergeUs,
            metricUnit: addUnitMetric,
            usUnit: addUnitUs,
          ));
        }

        // Keep last 20 sources max
        final mergedSources = currentSources.length > 20
            ? currentSources.sublist(currentSources.length - 20)
            : currentSources;

        final nextUsed =
            (_asInt(data['usedCount']) ?? 0) + (entry.usedCount ?? 0);

        // Merge sums
        final nextMetric = _mergeSumSameUnit(
          existingQty: exQtyMetric,
          existingUnit: exUnitMetric,
          addQty: canMergeMetric ? entry.sumQtyMetric : null,
          addUnit: canMergeMetric ? addUnitMetric : null,
        );

        final nextUs = _mergeSumSameUnit(
          existingQty: exQtyUs,
          existingUnit: exUnitUs,
          addQty: canMergeUs ? entry.sumQtyUs : null,
          addUnit: canMergeUs ? addUnitUs : null,
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
          SetOptions(merge: true),
        );
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

      // Remove from sources list
      sources.removeWhere((s) => _asInt(s['recipeId']) == recipeId);

      // If no sources left, delete item
      if (sources.isEmpty) {
        batch.delete(doc.reference);
        continue;
      }

      // Otherwise subtract sums safely (unit-guard per-source)
      double? currentMetric = _asDouble(data['sumQtyMetric']);
      final currentMetricUnit = (data['sumUnitMetric'] ?? '').toString().trim();

      double? currentUs = _asDouble(data['sumQtyUs']);
      final currentUsUnit = (data['sumUnitUs'] ?? '').toString().trim();

      for (final s in sourcesToRemove) {
        final subM = _asDouble(s['contribMetric']) ?? 0;
        final subMU = (s['contribUnitMetric'] ?? '').toString().trim();
        if (currentMetric != null && currentMetric > 0 && subM > 0) {
          if (_sameNormalizedUnit(currentMetricUnit, subMU)) {
            currentMetric = currentMetric - subM;
            if (currentMetric <= 0) currentMetric = null;
          }
        }

        final subU = _asDouble(s['contribUs']) ?? 0;
        final subUU = (s['contribUnitUs'] ?? '').toString().trim();
        if (currentUs != null && currentUs > 0 && subU > 0) {
          if (_sameNormalizedUnit(currentUsUnit, subUU)) {
            currentUs = currentUs - subU;
            if (currentUs <= 0) currentUs = null;
          }
        }
      }

      // ✅ usedCount should drop by number of removed contributions
      final removedCount = sourcesToRemove.length;
      final newUsedCount = (_asInt(data['usedCount']) ?? 1) - removedCount;

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
        SetOptions(merge: true),
      );

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

  bool _sameNormalizedUnit(String a, String b) {
    final ua = ShoppingEngine.normalizeUnit(a);
    final ub = ShoppingEngine.normalizeUnit(b);
    if (ua.isEmpty || ub.isEmpty) return false;
    return ua == ub;
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
      return v
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
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

    // Unit mismatch: do not merge
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

  // Whether we had a summable batch contribution (before checking merge vs existing)
  bool hasBatchMetric = false;
  bool hasBatchUs = false;

  int? usedCount;

  final List<String> examples = [];
  final List<String> examplesMetric = [];
  final List<String> examplesUs = [];

  _Agg({required this.key, required this.name});
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/allergy_keys.dart';
import '../meal_plan/core/meal_plan_review_service.dart';
import '../first_foods/first_foods_ui.dart';

class ChildProfileScreen extends StatefulWidget {
  final int? childIndex; // null = create
  const ChildProfileScreen({super.key, this.childIndex});

  @override
  State<ChildProfileScreen> createState() => _ChildProfileScreenState();
}

class _ChildProfileScreenState extends State<ChildProfileScreen> {
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();

  bool _hasAllergies = false;
  final List<String> _selectedAllergies = [];

  Map<String, dynamic>? _loadedSnapshot;

  // ✅ prevents StreamBuilder → postFrame → setState loops
  String? _lastHydratedFingerprint;

  static const List<String> _allergyOptions = [
    'soy',
    'peanut',
    'tree_nut',
    'sesame',
    'gluten',
    'coconut',
    'seed',
  ];

  bool get _isCreate => widget.childIndex == null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  String _fingerprintOf(Map<String, dynamic> child) {
    final name = (child['name'] ?? '').toString().trim();
    final dob = (child['dob'] ?? '').toString().trim();
    final has = child['hasAllergies'] == true;

    final raw = child['allergies'];
    final allergies = <String>[];
    if (raw is List) {
      for (final a in raw) {
        final k = AllergyKeys.normalize(a.toString());
        if (k != null) allergies.add(k);
      }
      allergies.sort();
    }
    if (!has) allergies.clear();

    // ✅ include childKey so hydration is stable across migrations
    final ck = (child['childKey'] ?? '').toString().trim();

    return '$name|$dob|$has|${allergies.join(",")}|$ck';
  }

  void _applyToForm(Map<String, dynamic> child) {
    _loadedSnapshot = Map<String, dynamic>.from(child);

    _nameCtrl.text = (child['name'] ?? '').toString();
    _dobCtrl.text = (child['dob'] ?? '').toString();

    _hasAllergies = child['hasAllergies'] == true;

    _selectedAllergies.clear();
    final raw = child['allergies'];
    if (raw is List) {
      for (final a in raw) {
        final k = AllergyKeys.normalize(a.toString());
        if (k != null) _selectedAllergies.add(k);
      }
      _selectedAllergies.sort();
    }

    if (!_hasAllergies) _selectedAllergies.clear();
  }

  List<String> _canonicalizeAllergies() {
    if (!_hasAllergies) return <String>[];

    return _selectedAllergies
        .map((a) => AllergyKeys.normalize(a))
        .whereType<String>()
        .where(AllergyKeys.supported.contains)
        .toSet()
        .toList()
      ..sort();
  }

  /// ✅ Stable childKey for firstFoods + any per-child data
  /// - If creating: generate now
  /// - If editing and missing: generate and persist on save
  String _ensureChildKeyFromExisting(Map<String, dynamic> child) {
    final existing = (child['childKey'] ?? '').toString().trim();
    if (existing.isNotEmpty) return existing;
    return FirebaseFirestore.instance.collection('_').doc().id;
  }

  Future<void> _save(List children, Map<String, dynamic> currentChild) async {
    final doc = _userDoc();
    if (doc == null) return;

    final name = _nameCtrl.text.trim();
    final dob = _dobCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }

    // ---- allergy change detection (same as before) ----
    final prevHas = _loadedSnapshot?['hasAllergies'] == true;
    final prevRaw = _loadedSnapshot?['allergies'];
    final prevAllergies = <String>[];

    if (prevRaw is List) {
      for (final a in prevRaw) {
        final k = AllergyKeys.normalize(a.toString());
        if (k != null) prevAllergies.add(k);
      }
      prevAllergies.sort();
    }
    if (!prevHas) prevAllergies.clear();

    final newAllergies = _canonicalizeAllergies();

    final didChangeAllergies =
        prevHas != _hasAllergies ||
            prevAllergies.join(',') != newAllergies.join(',');

    // ✅ stable key (important)
    final childKey = _isCreate
        ? FirebaseFirestore.instance.collection('_').doc().id
        : _ensureChildKeyFromExisting(currentChild);

    final updated = {
      // ✅ persist childKey
      'childKey': childKey,
      'name': name,
      'dob': dob,
      'hasAllergies': _hasAllergies,
      'allergies': newAllergies,
    };

    setState(() => _saving = true);
    try {
      if (_isCreate) {
        final next = List.from(children)..add(updated);
        await doc.set({
          'children': next,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final idx = widget.childIndex!;
        if (idx < 0 || idx >= children.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Child not found')),
          );
          return;
        }
        children[idx] = updated;
        await doc.set({
          'children': children,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (didChangeAllergies) {
        await MealPlanReviewService.markNeedsReview(changedForLabel: name);
      }

      if (!mounted) return;

      Navigator.of(context).pop({
        'didChangeAllergies': didChangeAllergies,
        'changedForLabel': name,
        'isCreate': _isCreate,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(List children, Map<String, dynamic> currentChild) async {
    final doc = _userDoc();
    if (doc == null) return;

    final idx = widget.childIndex!;
    if (idx < 0 || idx >= children.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Child not found')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete child?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // ✅ delete firstFoods doc for this child (by childKey)
    final childKey = (currentChild['childKey'] ?? '').toString().trim();
    if (childKey.isNotEmpty) {
      try {
        await doc.collection('firstFoods').doc(childKey).delete();
      } catch (_) {
        // ignore (doc might not exist)
      }
    }

    children.removeAt(idx);

    setState(() => _saving = true);
    try {
      await doc.set({
        'children': children,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.of(context).pop({
        'deleted': true,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _userDoc();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? 'Add Child' : 'Child Profile'),
      ),
      body: doc == null
          ? const Center(child: Text('Not logged in'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: doc.snapshots(),
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

                final data = snap.data?.data() ?? {};
                final children = (data['children'] as List?) ?? [];

                Map<String, dynamic> child;
                if (_isCreate) {
                  child = {
                    // ⚠️ do NOT generate childKey here, only on Save
                    'name': '',
                    'dob': '',
                    'hasAllergies': false,
                    'allergies': <String>[],
                  };
                } else {
                  final idx = widget.childIndex!;
                  if (idx < 0 || idx >= children.length) {
                    return const Center(child: Text('Child not found'));
                  }
                  final raw = children[idx];
                  if (raw is! Map) {
                    return const Center(child: Text('Invalid record'));
                  }
                  child = Map<String, dynamic>.from(raw);
                }

                final fp = _fingerprintOf(child);
                if (fp != _lastHydratedFingerprint) {
                  _lastHydratedFingerprint = fp;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _applyToForm(child));
                  });
                }

                // ✅ stable id for First Foods (only if exists)
                final childKey = (child['childKey'] ?? '').toString().trim();

                final childName = (_nameCtrl.text.trim().isEmpty)
                    ? (child['name'] ?? 'Child').toString()
                    : _nameCtrl.text.trim();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dobCtrl,
                      decoration: const InputDecoration(
                        labelText: 'DOB',
                        hintText: 'e.g. 2021-06-14 or 14/06/2021',
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Has allergies'),
                      value: _hasAllergies,
                      onChanged: _saving
                          ? null
                          : (v) {
                              setState(() {
                                _hasAllergies = v;
                                if (!v) _selectedAllergies.clear();
                              });
                            },
                    ),
                    if (_hasAllergies) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Allergies',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ..._allergyOptions.map((a) {
                        final selected = _selectedAllergies.contains(a);
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(AllergyKeys.label(a)),
                          value: selected,
                          onChanged: _saving
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      if (!selected) _selectedAllergies.add(a);
                                    } else {
                                      _selectedAllergies.remove(a);
                                    }
                                    _selectedAllergies.sort();
                                  });
                                },
                        );
                      }),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _saving ? null : () => _save(children, child),
                        child: Text(
                          _saving ? 'SAVING…' : (_isCreate ? 'ADD' : 'SAVE'),
                        ),
                      ),
                    ),

                    // ✅ moved under "Save"
                    // ✅ use childKey (stable) instead of child_{index}
                    if (!_isCreate) ...[
                      const SizedBox(height: 12),
                      if (childKey.isNotEmpty)
                        FirstFoodsOverviewTile(
                          childId: childKey,
                          childName: childName,
                        )
                      else
                        const Text(
                          'Save once to set up First Foods tracking.',
                        ),
                    ],

                    if (!_isCreate) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed:
                              _saving ? null : () => _delete(children, child),
                          child: const Text('DELETE CHILD'),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../recipes/allergy_keys.dart';
import '../meal_plan/core/meal_plan_review_service.dart'; // ✅ NEW

class AdultProfileScreen extends StatefulWidget {
  final int adultIndex;
  const AdultProfileScreen({super.key, required this.adultIndex});

  @override
  State<AdultProfileScreen> createState() => _AdultProfileScreenState();
}

class _AdultProfileScreenState extends State<AdultProfileScreen> {
  bool _saving = false;

  final _nameCtrl = TextEditingController();

  bool _hasAllergies = false;
  final List<String> _selectedAllergies = [];

  Map<String, dynamic>? _loadedSnapshot;

  static const List<String> _allergyOptions = [
    'soy',
    'peanut',
    'tree_nut',
    'sesame',
    'gluten',
    'coconut',
    'seed',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  void _applyToForm(Map<String, dynamic> adult) {
    _loadedSnapshot = Map<String, dynamic>.from(adult);

    _nameCtrl.text = (adult['name'] ?? '').toString();
    _hasAllergies = adult['hasAllergies'] == true;

    _selectedAllergies.clear();
    final raw = adult['allergies'];
    if (raw is List) {
      for (final a in raw) {
        final key = AllergyKeys.normalize(a.toString());
        if (key != null) _selectedAllergies.add(key);
      }
      _selectedAllergies.sort();
    }

    if (!_hasAllergies) _selectedAllergies.clear();
  }

  Future<void> _save(List adults) async {
  final doc = _userDoc();
  if (doc == null) return;

  final name = _nameCtrl.text.trim();
  if (name.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Name is required')),
    );
    return;
  }

  if (widget.adultIndex < 0 || widget.adultIndex >= adults.length) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Person not found')),
    );
    return;
  }

  // ---- capture previous allergy state (from loaded snapshot) ----
  final prevHas = _loadedSnapshot?['hasAllergies'] == true;
  final prevListRaw = _loadedSnapshot?['allergies'];
  final prevAllergies = <String>[];
  if (prevListRaw is List) {
    for (final a in prevListRaw) {
      final k = AllergyKeys.normalize(a.toString());
      if (k != null) prevAllergies.add(k);
    }
    prevAllergies.sort();
  }
  if (!prevHas) prevAllergies.clear();

  // ---- compute new allergy state ----
  final canonicalAllergies = _hasAllergies
      ? (({
          for (final a in _selectedAllergies) (AllergyKeys.normalize(a) ?? a)
        }).where(AllergyKeys.supported.contains).toList()
        ..sort())
      : <String>[];

  final didChangeAllergies =
      (prevHas != _hasAllergies) || (prevAllergies.join(',') != canonicalAllergies.join(','));

  // ---- write to Firestore ----
  adults[widget.adultIndex] = {
    'name': name,
    'hasAllergies': _hasAllergies,
    'allergies': canonicalAllergies,
  };

  setState(() => _saving = true);
  try {
    await doc.set({
      'adults': adults,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // ✅ if allergies changed, flag + prompt
    if (didChangeAllergies) {
      await MealPlanReviewService.markNeedsReview(changedForLabel: name);
      if (!mounted) return;
      await MealPlanReviewService.checkAndPromptIfNeeded(context);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save: $e')),
    );
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}



  Future<void> _delete(List adults) async {
    final doc = _userDoc();
    if (doc == null) return;

    if (widget.adultIndex == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can’t delete this person.")),
      );
      return;
    }

    if (widget.adultIndex < 0 || widget.adultIndex >= adults.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Person not found')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete person?'),
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

    adults.removeAt(widget.adultIndex);

    setState(() => _saving = true);
    try {
      await doc.set({
        'adults': adults,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop();
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
      body: (doc == null)
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
                final adults = (data['adults'] as List?) ?? [];

                if (widget.adultIndex < 0 ||
                    widget.adultIndex >= adults.length) {
                  return const Center(child: Text('Person not found'));
                }

                final raw = adults[widget.adultIndex];
                if (raw is! Map) {
                  return const Center(child: Text('Invalid record'));
                }

                final adult = Map<String, dynamic>.from(raw);

                // Keep form in sync with Firestore
                final snapshotString = adult.toString();
                final prevString = _loadedSnapshot?.toString();
                if (snapshotString != prevString) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _applyToForm(adult);
                    setState(() {});
                  });
                }

                final name = _nameCtrl.text.trim();
                final canSave = !_saving && name.isNotEmpty;

                return Scaffold(
                  appBar: AppBar(
                    title: Text(name.isEmpty ? 'Edit person' : name),
                    actions: [
                      TextButton(
                        onPressed: canSave ? () => _save(adults) : null,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
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
                        }).toList(),
                      ],

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: canSave ? () => _save(adults) : null,
                          child: Text(_saving ? 'SAVING…' : 'SAVE'),
                        ),
                      ),

                      if (widget.adultIndex != 0) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _saving ? null : () => _delete(adults),
                            child: const Text('DELETE'),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

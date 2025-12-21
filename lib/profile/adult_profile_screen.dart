import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../recipes/allergy_keys.dart';

class AdultProfileScreen extends StatefulWidget {
  final int adultIndex; // index into users/{uid}.adults array (0 = Adult 1)
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
    _hasAllergies = (adult['hasAllergies'] == true);

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
        const SnackBar(content: Text('Adult not found')),
      );
      return;
    }

    final canonicalAllergies = _hasAllergies
        ? (({
            for (final a in _selectedAllergies)
              (AllergyKeys.normalize(a) ?? a)
          }).where(AllergyKeys.supported.contains).toList()
          ..sort())
        : <String>[];

    final updated = <String, dynamic>{
      'name': name,
      'hasAllergies': _hasAllergies,
      'allergies': canonicalAllergies,
    };

    adults[widget.adultIndex] = updated;

    setState(() => _saving = true);
    try {
      await doc.set({
        'adults': adults,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adult saved')),
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
        const SnackBar(content: Text("You can’t delete Adult 1 (account owner).")),
      );
      return;
    }

    if (widget.adultIndex < 0 || widget.adultIndex >= adults.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adult not found')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete adult?'),
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
      appBar: AppBar(
        title: Text(widget.adultIndex == 0 ? 'Adult 1 (You)' : 'Adult ${widget.adultIndex + 1}'),
      ),
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

                if (widget.adultIndex < 0 || widget.adultIndex >= adults.length) {
                  return const Center(child: Text('Adult not found'));
                }

                final raw = adults[widget.adultIndex];
                if (raw is! Map) return const Center(child: Text('Invalid adult record'));

                final adult = Map<String, dynamic>.from(raw);

                final snapshotString = adult.toString();
                final prevString = _loadedSnapshot?.toString();
                if (prevString != snapshotString) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _applyToForm(adult);
                    setState(() {});
                  });
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
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
                      Text('Allergies', style: Theme.of(context).textTheme.titleMedium),
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
                        onPressed: _saving ? null : () => _save(adults),
                        child: Text(_saving ? 'SAVING...' : 'SAVE'),
                      ),
                    ),

                    if (widget.adultIndex != 0) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => _delete(adults),
                          child: const Text('DELETE ADULT'),
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

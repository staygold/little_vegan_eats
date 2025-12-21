import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../recipes/allergy_keys.dart';

class ChildProfileScreen extends StatefulWidget {
  final int? childIndex; // null => create mode
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

  Map<String, dynamic>? _loadedChildSnapshot;

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

  void _applyChildToForm(Map<String, dynamic> child) {
    _loadedChildSnapshot = Map<String, dynamic>.from(child);

    _nameCtrl.text = (child['name'] ?? '').toString();
    _dobCtrl.text = (child['dob'] ?? '').toString();

    _hasAllergies = (child['hasAllergies'] == true);

    _selectedAllergies.clear();
    final raw = child['allergies'];
    if (raw is List) {
      for (final a in raw) {
        final key = AllergyKeys.normalize(a.toString());
        if (key != null) _selectedAllergies.add(key);
      }
      _selectedAllergies.sort();
    }

    // If switch is OFF, make sure allergies list is empty
    if (!_hasAllergies) _selectedAllergies.clear();
  }

  List<String> _canonicalizeSelectedAllergies() {
    if (!_hasAllergies) return <String>[];

    final set = <String>{};
    for (final a in _selectedAllergies) {
      final k = AllergyKeys.normalize(a) ?? a;
      if (AllergyKeys.supported.contains(k)) set.add(k);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _saveChild(List children) async {
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

    final updated = <String, dynamic>{
      'name': name,
      'dob': dob,
      'hasAllergies': _hasAllergies,
      'allergies': _canonicalizeSelectedAllergies(),
    };

    setState(() => _saving = true);

    try {
      if (_isCreate) {
        final next = List.from(children);
        next.add(updated);

        await doc.set({
          'children': next,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Child added')),
        );
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

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Child saved')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteChild(List children) async {
    final doc = _userDoc();
    if (doc == null) return;

    if (_isCreate) return;

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

    children.removeAt(idx);

    setState(() => _saving = true);
    try {
      await doc.set({
        'children': children,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop(); // back to Profile screen
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
      appBar: AppBar(title: Text(_isCreate ? 'Add Child' : 'Child Profile')),
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
                final children = (data['children'] as List?) ?? [];

                Map<String, dynamic> child;

                if (_isCreate) {
                  // Create mode: start blank, and ONLY apply once
                  child = {
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
                    return const Center(child: Text('Invalid child record'));
                  }
                  child = Map<String, dynamic>.from(raw);
                }

                // Only push values into controllers if changed / first load
                // In create mode, only do this ONCE (prevents stomping user input)
                final snapshotString = child.toString();
                final prevString = _loadedChildSnapshot?.toString();
                final shouldApply = prevString != snapshotString &&
                    (!_isCreate || _loadedChildSnapshot == null);

                if (shouldApply) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _applyChildToForm(child);
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dobCtrl,
                      decoration: const InputDecoration(
                        labelText: 'DOB',
                        hintText: 'e.g. 2021-06-14 or 14/06/2021',
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
                      Text('Allergies',
                          style: Theme.of(context).textTheme.titleMedium),
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
                        onPressed: _saving ? null : () => _saveChild(children),
                        child: Text(_saving ? 'SAVING...' : (_isCreate ? 'ADD' : 'SAVE')),
                      ),
                    ),
                    if (!_isCreate) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => _deleteChild(children),
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

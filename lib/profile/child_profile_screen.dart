// lib/profile/child_profile_screen.dart
import 'dart:ui' show FontVariation;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';
import '../theme/app_theme.dart';
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
  // ============================================================
  // STYLE
  // ============================================================
  static const Color _pageBg = Color(0xFFECF3F4);
  static const Color _cardBg = Colors.white;

  static const double _radius = 12;

  // Allergy selector panel + rows (match AdultProfileScreen)
  static const double _allergyPanelRadius = 18;
  static const double _allergyRowRadius = 14;
  static const double _allergyRowHeight = 62;
  static const double _allergyRowBorderWidth = 2;

  static const EdgeInsets _pagePad = EdgeInsets.fromLTRB(16, 12, 16, 16);

  static TextStyle _labelStyle(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: AppColors.brandDark.withOpacity(0.75),
      fontWeight: FontWeight.w800,
      fontVariations: const [FontVariation('wght', 800)],
      letterSpacing: 0.8,
      height: 1.0,
    );
  }

  static const TextStyle _fieldText = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 16,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    letterSpacing: 0.2,
    height: 1.2,
    color: AppColors.brandDark,
  );

  static const TextStyle _btnText = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 14,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    letterSpacing: 0.9,
    height: 1.0,
  );

  static const List<String> _allergyOptions = [
    'soy',
    'peanut',
    'tree_nut',
    'sesame',
    'gluten',
    'coconut',
    'seed',
  ];

  // ============================================================
  // STATE
  // ============================================================
  bool _saving = false;

  final _nameCtrl = TextEditingController();

  int? _dobMonth; // 1-12
  int? _dobYear; // yyyy

  bool _hasAllergies = false;
  final List<String> _selectedAllergies = [];

  Map<String, dynamic>? _loadedSnapshot;
  String? _lastHydratedFingerprint;

  bool get _isCreate => widget.childIndex == null;

  // Prevent any post-pop hydration + controller writes
  bool _closing = false;

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

  // ------------------------------------------------------------
  // DOB helpers (new + legacy)
  // ------------------------------------------------------------
  String _dobFingerprint(Map<String, dynamic> child) {
    final m = child['dobMonth'];
    final y = child['dobYear'];
    if (m is int && y is int) return '$y-${m.toString().padLeft(2, '0')}';
    return (child['dob'] ?? '').toString().trim();
  }

  void _hydrateDobFields(Map<String, dynamic> child) {
    final m = child['dobMonth'];
    final y = child['dobYear'];

    if (m is int && y is int && m >= 1 && m <= 12) {
      _dobMonth = m;
      _dobYear = y;
      return;
    }

    final raw = child['dob'];
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    if (raw is DateTime) dt = raw;

    if (dt == null && raw is String && raw.trim().isNotEmpty) {
      final s = raw.trim();

      if (s.contains('-')) {
        final parts = s.split('-');
        final yy = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
        final mm = parts.length > 1 ? int.tryParse(parts[1]) : null;
        if (yy != null && mm != null && mm >= 1 && mm <= 12) {
          _dobYear = yy;
          _dobMonth = mm;
          return;
        }
      }

      if (s.contains('/')) {
        final parts = s.split('/');
        if (parts.length == 2) {
          final mm = int.tryParse(parts[0]);
          final yy = int.tryParse(parts[1]);
          if (yy != null && mm != null && mm >= 1 && mm <= 12) {
            _dobYear = yy;
            _dobMonth = mm;
            return;
          }
        }
        if (parts.length == 3) {
          final mm = int.tryParse(parts[1]);
          final yy = int.tryParse(parts[2]);
          if (yy != null && mm != null && mm >= 1 && mm <= 12) {
            _dobYear = yy;
            _dobMonth = mm;
            return;
          }
        }
      }
    }

    if (dt != null) {
      _dobYear = dt.year;
      _dobMonth = dt.month;
    }
  }

  String _dobLabel() {
    if (_dobMonth == null || _dobYear == null) return 'Select month and year';
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${names[_dobMonth! - 1]} $_dobYear';
  }

  List<DropdownMenuItem<int>> _monthItems() {
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return List.generate(12, (i) {
      final m = i + 1;
      return DropdownMenuItem<int>(value: m, child: Text(names[i]));
    });
  }

  List<DropdownMenuItem<int>> _yearItems() {
    final now = DateTime.now();
    final maxY = now.year;
    final minY = now.year - 18;
    return [
      for (int y = maxY; y >= minY; y--)
        DropdownMenuItem<int>(value: y, child: Text('$y'))
    ];
  }

  // ------------------------------------------------------------
  // Fingerprint / hydration
  // ------------------------------------------------------------
  String _fingerprintOf(Map<String, dynamic> child) {
    final name = (child['name'] ?? '').toString().trim();
    final dob = _dobFingerprint(child);
    final has = child['hasAllergies'] == true;

    final allergies = _readAllergyList(child['allergies']);
    if (!has) allergies.clear();

    final ck = (child['childKey'] ?? '').toString().trim();
    return '$name|$dob|$has|${allergies.join(",")}|$ck';
  }

  List<String> _readAllergyList(dynamic raw) {
    final out = <String>[];
    if (raw is List) {
      for (final a in raw) {
        final k = AllergyKeys.normalize(a.toString());
        if (k != null && AllergyKeys.supported.contains(k)) out.add(k);
      }
    }
    out.sort();
    return out;
  }

  void _applyToForm(Map<String, dynamic> child) {
    _loadedSnapshot = Map<String, dynamic>.from(child);

    if (!_closing) {
      _nameCtrl.text = (child['name'] ?? '').toString();
    }

    _hydrateDobFields(child);

    _hasAllergies = child['hasAllergies'] == true;

    _selectedAllergies
      ..clear()
      ..addAll(_readAllergyList(child['allergies']));
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

  String _ensureChildKeyFromExisting(Map<String, dynamic> child) {
    final existing = (child['childKey'] ?? '').toString().trim();
    if (existing.isNotEmpty) return existing;
    return FirebaseFirestore.instance.collection('_').doc().id;
  }

  // ------------------------------------------------------------
  // Save / delete
  // ------------------------------------------------------------
  Future<void> _save(List children, Map<String, dynamic> currentChild) async {
    final doc = _userDoc();
    if (doc == null) return;

    final name = _nameCtrl.text.trim();
    final m = _dobMonth;
    final y = _dobYear;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    if (m == null || y == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Birth month and year are required')),
      );
      return;
    }

    // previous allergy state
    final prevHas = _loadedSnapshot?['hasAllergies'] == true;
    final prevAllergies = _readAllergyList(_loadedSnapshot?['allergies']);
    if (!prevHas) prevAllergies.clear();

    // new allergy state
    final newAllergies = _canonicalizeAllergies();
    final didChangeAllergies =
        prevHas != _hasAllergies || prevAllergies.join(',') != newAllergies.join(',');

    final childKey = _isCreate
        ? FirebaseFirestore.instance.collection('_').doc().id
        : _ensureChildKeyFromExisting(currentChild);

    // ✅ CRITICAL: NO FieldValue.delete() inside children[] items.
    // We simply stop writing legacy 'dob'. Old values can remain.
    final updated = <String, dynamic>{
      'childKey': childKey,
      'name': name,
      'dobMonth': m,
      'dobYear': y,
      'hasAllergies': _hasAllergies,
      'allergies': newAllergies,
    };

    if (!mounted) return;
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
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Child not found')),
          );
          return;
        }
        final next = List.from(children);
        next[idx] = updated;

        await doc.set({
          'children': next,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (didChangeAllergies) {
        await MealPlanReviewService.markNeedsReview(changedForLabel: name);
      }

      _closing = true;

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

    final childKey = (currentChild['childKey'] ?? '').toString().trim();
    if (childKey.isNotEmpty) {
      try {
        await doc.collection('firstFoods').doc(childKey).delete();
      } catch (_) {}
    }

    final next = List.from(children);
    next.removeAt(idx);

    setState(() => _saving = true);
    try {
      await doc.set({
        'children': next,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _closing = true;

      if (!mounted) return;
      Navigator.of(context).pop({'deleted': true});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------
  // UI bits
  // ------------------------------------------------------------
  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: child,
    );
  }

  Widget _nameField(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: AppColors.brandDark.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              style: _fieldText,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: 'Enter name',
              ),
            ),
          ),
          Icon(Icons.edit, size: 18, color: AppColors.brandDark.withOpacity(0.75)),
        ],
      ),
    );
  }

  Widget _dobField(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: AppColors.brandDark.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dobLabel(),
              style: _fieldText.copyWith(
                color: (_dobMonth == null || _dobYear == null)
                    ? AppColors.brandDark.withOpacity(0.45)
                    : AppColors.brandDark,
              ),
            ),
          ),
          Icon(Icons.edit, size: 18, color: AppColors.brandDark.withOpacity(0.75)),
        ],
      ),
    );
  }

  Future<void> _openDobPicker(BuildContext context) async {
    if (_saving) return;

    int? tempMonth = _dobMonth;
    int? tempYear = _dobYear;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'BIRTH MONTH & YEAR',
                      style: _btnText.copyWith(
                        fontSize: 18,
                        letterSpacing: 0.8,
                        color: AppColors.brandDark,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Month'),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: tempMonth,
                                isExpanded: true,
                                hint: const Text('Select month'),
                                items: _monthItems(),
                                onChanged: (v) => setSheetState(() => tempMonth = v),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Year'),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: tempYear,
                                isExpanded: true,
                                hint: const Text('Select year'),
                                items: _yearItems(),
                                onChanged: (v) => setSheetState(() => tempYear = v),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (!mounted) return;
                          setState(() {
                            _dobMonth = tempMonth;
                            _dobYear = tempYear;
                          });
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_radius),
                          ),
                        ),
                        child: Text('DONE', style: _btnText.copyWith(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // HAS ALLERGIES row outside the panel
  Widget _hasAllergiesRow(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('HAS ALLERGIES', style: _labelStyle(context))),
        Switch(
          value: _hasAllergies,
          activeColor: AppColors.brandDark,
          onChanged: _saving
              ? null
              : (v) {
                  setState(() {
                    _hasAllergies = v;
                    if (!v) _selectedAllergies.clear();
                  });
                },
        ),
      ],
    );
  }

  // Allergy selector panel only when toggled on
  Widget _allergyPanel(BuildContext context) {
    if (!_hasAllergies) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_allergyPanelRadius),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _allergyOptions.length; i++) ...[
            _allergyRow(context, _allergyOptions[i]),
            if (i != _allergyOptions.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _allergyRow(BuildContext context, String key) {
    final selected = _selectedAllergies.contains(key);
    final label = AllergyKeys.label(key).toUpperCase();

    final borderColor = AppColors.brandDark.withOpacity(0.18);
    final radius = BorderRadius.circular(_allergyRowRadius);

    return Material(
      color: selected ? AppColors.brandDark : Colors.white,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: _saving
            ? null
            : () {
                setState(() {
                  if (selected) {
                    _selectedAllergies.remove(key);
                  } else {
                    _selectedAllergies.add(key);
                    _selectedAllergies.sort();
                  }
                });
              },
        child: Container(
          height: _allergyRowHeight,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: selected
                ? null
                : Border.all(
                    color: borderColor,
                    width: _allergyRowBorderWidth,
                  ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _btnText.copyWith(
                    fontSize: 18,
                    letterSpacing: 1.2,
                    color: selected ? Colors.white : AppColors.brandDark,
                  ),
                ),
              ),
              if (selected) const Icon(Icons.close, size: 22, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigSaveButton({required VoidCallback onTap, required bool enabled}) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_saving || !enabled) ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
        child: Text(
          _saving ? 'SAVING…' : 'SAVE',
          style: _btnText.copyWith(color: Colors.white),
        ),
      ),
    );
  }

  Widget _bigDeleteButton({required VoidCallback onTap}) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _saving ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brandDark,
          side: BorderSide(
            color: AppColors.brandDark.withOpacity(0.25),
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
        child: Text(
          'DELETE CHILD',
          style: _btnText.copyWith(color: AppColors.brandDark),
        ),
      ),
    );
  }

  String _headerTitleFromName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'CHILD';
    return n.split(RegExp(r'\s+')).first.toUpperCase();
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final doc = _userDoc();

    if (doc == null) {
      return const Scaffold(
        backgroundColor: _pageBg,
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: _pageBg,
      body: Column(
        children: [
          SubHeaderBar(title: _headerTitleFromName(_nameCtrl.text)),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: doc.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Padding(
                    padding: _pagePad,
                    child: Text('Firestore error: ${snap.error}'),
                  );
                }

                final data = snap.data?.data() ?? {};
                final children = (data['children'] as List?) ?? [];

                Map<String, dynamic> child;
                if (_isCreate) {
                  // Create mode: do not hydrate from Firestore
                  child = {
                    'name': _nameCtrl.text,
                    'dobMonth': _dobMonth,
                    'dobYear': _dobYear,
                    'hasAllergies': _hasAllergies,
                    'allergies': List<String>.from(_selectedAllergies),
                  };
                } else {
                  final idx = widget.childIndex!;
                  if (idx < 0 || idx >= children.length) {
                    return const Center(child: Text('Child not found'));
                  }
                  final raw = children[idx];
                  if (raw is! Map) return const Center(child: Text('Invalid record'));
                  child = Map<String, dynamic>.from(raw);
                }

                // Hydrate only in edit mode
                if (!_isCreate && !_saving && !_closing) {
                  final fp = _fingerprintOf(child);
                  if (fp != _lastHydratedFingerprint) {
                    _lastHydratedFingerprint = fp;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || _closing) return;
                      _applyToForm(child);
                      setState(() {});
                    });
                  }
                }

                final childKey = (child['childKey'] ?? '').toString().trim();
                final childName = (_nameCtrl.text.trim().isEmpty)
                    ? (child['name'] ?? 'Child').toString()
                    : _nameCtrl.text.trim();

                final canSave =
                    _nameCtrl.text.trim().isNotEmpty && _dobMonth != null && _dobYear != null;

                return ListView(
                  padding: _pagePad,
                  children: [
                    _card(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('FIRST NAME', style: _labelStyle(context)),
                          const SizedBox(height: 10),
                          _nameField(context),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _openDobPicker(context),
                      child: _card(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BIRTH MONTH & YEAR', style: _labelStyle(context)),
                            const SizedBox(height: 10),
                            _dobField(context),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _hasAllergiesRow(context),
                    ),
                    const SizedBox(height: 12),
                    _allergyPanel(context),
                    const SizedBox(height: 22),
                    _bigSaveButton(
                      enabled: canSave,
                      onTap: () => _save(children, child),
                    ),

                    // First Foods tile under Save (only when editing)
                    if (!_isCreate) ...[
                      const SizedBox(height: 12),
                      if (childKey.isNotEmpty)
                        FirstFoodsOverviewTile(
                          childId: childKey,
                          childName: childName,
                        )
                      else
                        Text(
                          'Save once to set up First Foods tracking.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.brandDark.withOpacity(0.75),
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                        ),
                      const SizedBox(height: 12),
                      _bigDeleteButton(onTap: () => _delete(children, child)),
                    ],

                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// lib/profile/adult_profile_screen.dart
import 'dart:ui' show FontVariation;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';
import '../theme/app_theme.dart';
import '../recipes/allergy_keys.dart';
import '../meal_plan/core/meal_plan_review_service.dart';

class AdultProfileScreen extends StatefulWidget {
  final int adultIndex; // 0..n-1 (record must already exist)
  const AdultProfileScreen({super.key, required this.adultIndex});

  @override
  State<AdultProfileScreen> createState() => _AdultProfileScreenState();
}

class _AdultProfileScreenState extends State<AdultProfileScreen> {
  // ============================================================
  // ✅ STYLE KEYS (keep consistent with ProfileScreen)
  // ============================================================
  static const Color _pageBg = Color(0xFFECF3F4);
  static const Color _cardBg = Colors.white;

  static const double _radius = 12;

  // Allergy selector panel + rows (matches your mock)
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

  bool _hasAllergies = false;
  final List<String> _selectedAllergies = [];

  Map<String, dynamic>? _loadedSnapshot;
  String? _lastHydratedFingerprint;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() {
      if (!mounted) return;
      setState(() {}); // updates header title live
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

  // ============================================================
  // HYDRATION (no setState loops)
  // ============================================================
  String _fingerprintOf(Map<String, dynamic> adult) {
    final name = (adult['name'] ?? '').toString().trim();
    final has = adult['hasAllergies'] == true;

    final raw = adult['allergies'];
    final list = <String>[];
    if (raw is List) {
      for (final a in raw) {
        final k = AllergyKeys.normalize(a.toString());
        if (k != null) list.add(k);
      }
    }
    list.sort();
    if (!has) list.clear();

    return '$name|$has|${list.join(",")}';
  }

  void _applyToForm(Map<String, dynamic> adult) {
    _loadedSnapshot = Map<String, dynamic>.from(adult);

    _nameCtrl.text = (adult['name'] ?? '').toString();

    _hasAllergies = adult['hasAllergies'] == true;

    _selectedAllergies
      ..clear()
      ..addAll(_readAllergyList(adult['allergies']));
    if (!_hasAllergies) _selectedAllergies.clear();
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

  // ============================================================
  // SAVE / DELETE
  // ============================================================
  Future<void> _save(List adults, Map<String, dynamic> currentAdult) async {
    final doc = _userDoc();
    if (doc == null) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }

    final idx = widget.adultIndex;
    if (idx < 0 || idx >= adults.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Person not found')),
      );
      return;
    }

    // previous allergy state
    final prevHas = _loadedSnapshot?['hasAllergies'] == true;
    final prevAllergies = _readAllergyList(_loadedSnapshot?['allergies']);

    // new allergy state
    final newAllergies = _canonicalizeAllergies();
    final didChangeAllergies =
        prevHas != _hasAllergies || prevAllergies.join(',') != newAllergies.join(',');

    adults[idx] = {
      'name': name,
      'hasAllergies': _hasAllergies,
      'allergies': newAllergies,
    };

    setState(() => _saving = true);
    try {
      await doc.set({
        'adults': adults,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (didChangeAllergies) {
        await MealPlanReviewService.markNeedsReview(changedForLabel: name);
      }

      if (!mounted) return;
      Navigator.of(context).pop({
        'didChangeAllergies': didChangeAllergies,
        'changedForLabel': name,
        'isCreate': false,
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

  Future<void> _delete(List adults) async {
    final doc = _userDoc();
    if (doc == null) return;

    if (widget.adultIndex == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can’t delete this person.")),
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

  // ============================================================
  // UI PIECES
  // ============================================================
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
              textInputAction: TextInputAction.done,
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

  // ✅ HAS ALLERGIES row is OUTSIDE the panel (per your note)
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

  // ------------------------------------------------------------
  // ✅ Allergy selector panel (ONE white container only)
  // Shows ONLY when toggle is on.
  // ------------------------------------------------------------
  Widget _allergyPanel(BuildContext context) {
    if (!_hasAllergies) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, // ✅ single white container
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
              if (selected)
                const Icon(Icons.close, size: 22, color: Colors.white),
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
          'DELETE ADULT',
          style: _btnText.copyWith(color: AppColors.brandDark),
        ),
      ),
    );
  }

  String _headerTitleFromName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'ADULT';
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
          // ✅ dynamic title (first name)
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
                final adults = (data['adults'] as List?) ?? [];

                final idx = widget.adultIndex;
                if (idx < 0 || idx >= adults.length) {
                  return const Center(child: Text('Person not found'));
                }

                final raw = adults[idx];
                if (raw is! Map) {
                  return const Center(child: Text('Invalid record'));
                }

                final adult = Map<String, dynamic>.from(raw);
                final fp = _fingerprintOf(adult);

                if (fp != _lastHydratedFingerprint) {
                  _lastHydratedFingerprint = fp;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _applyToForm(adult));
                  });
                }

                final name = _nameCtrl.text.trim();
                final canSave = name.isNotEmpty;

                return ListView(
                  padding: _pagePad,
                  children: [
                    // ✅ no "ADD AN ADULT" heading

                    // Name field card stays (your desktop screenshot has it)
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

                    const SizedBox(height: 18),

                    // ✅ HAS ALLERGIES outside the panel
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _hasAllergiesRow(context),
                    ),

                    const SizedBox(height: 12),

                    // ✅ panel only appears when toggled on
                    _allergyPanel(context),

                    const SizedBox(height: 22),

                    _bigSaveButton(
                      enabled: canSave,
                      onTap: () => _save(adults, adult),
                    ),

                    if (widget.adultIndex != 0) ...[
                      const SizedBox(height: 12),
                      _bigDeleteButton(onTap: () => _delete(adults)),
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

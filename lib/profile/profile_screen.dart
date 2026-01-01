// lib/profile/profile_screen.dart
import 'dart:ui' show FontVariation;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../meal_plan/core/meal_plan_review_service.dart';
import '../theme/app_theme.dart';
import 'adult_profile_screen.dart';
import 'child_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _ensuredAdult1 = false;
  bool _hydratingChildKeys = false;

  // ✅ Change this if your welcome route isn't "/"
  static const String _welcomeRoute = '/';

  void _goToWelcome() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      _welcomeRoute,
      (route) => false,
    );
  }

  // --------------------------------------------------
  // Ensure Adult 1 from onboarding parentName
  // --------------------------------------------------
  Future<void> _ensureAdult1(
    DocumentReference<Map<String, dynamic>> docRef,
    Map<String, dynamic> data,
  ) async {
    if (_ensuredAdult1) return;

    final adults = (data['adults'] as List?) ?? [];
    if (adults.isNotEmpty) {
      _ensuredAdult1 = true;
      return;
    }

    final parentName = (data['parentName'] is String)
        ? (data['parentName'] as String).trim()
        : '';

    if (parentName.isEmpty) {
      _ensuredAdult1 = true;
      return;
    }

    try {
      await docRef.set({
        'adults': [
          {
            'name': parentName,
            'hasAllergies': false,
            'allergies': <String>[],
          }
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore
    } finally {
      _ensuredAdult1 = true;
    }
  }

  // --------------------------------------------------
  // Ensure every child has a stable childKey (auto-migrate)
  // --------------------------------------------------
  Future<void> _ensureChildKeys(
    DocumentReference<Map<String, dynamic>> docRef,
    List children,
  ) async {
    if (_hydratingChildKeys) return;

    bool needsWrite = false;
    final updated = children.map((c) {
      if (c is! Map) return c;

      final map = Map<String, dynamic>.from(c);
      final key = (map['childKey'] ?? '').toString().trim();
      if (key.isEmpty) {
        // unique id without any deps
        final newKey = FirebaseFirestore.instance.collection('_').doc().id;
        map['childKey'] = newKey;
        needsWrite = true;
      }
      return map;
    }).toList();

    if (!needsWrite) return;

    _hydratingChildKeys = true;
    try {
      await docRef.set({
        'children': updated,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore; we'll try again next render if needed
    } finally {
      _hydratingChildKeys = false;
    }
  }

  // --------------------------------------------------
  // Review prompt helper (runs from Profile context)
  // --------------------------------------------------
  Future<void> _handleReturnFromProfileEditor(dynamic res) async {
    if (!mounted) return;
    if (res is! Map) return;

    final didChangeAllergies = res['didChangeAllergies'] == true;

    if (didChangeAllergies) {
      await MealPlanReviewService.checkAndPromptIfNeeded(context);
    }

    if (res['deleted'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleted')),
      );
      return;
    }

    if (res.containsKey('isCreate')) {
      final isCreate = res['isCreate'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCreate ? 'Added' : 'Saved')),
      );
    }
  }

  // --------------------------------------------------
  // Add Adult (NO POPUP): create record, go to form
  // --------------------------------------------------
  Future<void> _addAdult(
    DocumentReference<Map<String, dynamic>> docRef,
    List adults,
  ) async {
    final updated = [...adults];
    updated.add({
      'name': '',
      'hasAllergies': false,
      'allergies': <String>[],
    });

    await docRef.set({
      'adults': updated,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    final res = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdultProfileScreen(adultIndex: updated.length - 1),
      ),
    );

    await _handleReturnFromProfileEditor(res);
  }

  // --------------------------------------------------
  // Add Child (NO POPUP): create record, go to form
  // --------------------------------------------------
  Future<void> _addChild(
    DocumentReference<Map<String, dynamic>> docRef,
    List children,
  ) async {
    final updated = [...children];

    // ✅ stable key for first foods + any child-specific data
    final childKey = FirebaseFirestore.instance.collection('_').doc().id;

    updated.add({
      'childKey': childKey,
      'name': '',
      'dob': '',
      'hasAllergies': false,
      'allergies': <String>[],
    });

    await docRef.set({
      'children': updated,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    final res = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildProfileScreen(childIndex: updated.length - 1),
      ),
    );

    await _handleReturnFromProfileEditor(res);
  }

  // --------------------------------------------------
  // UI helpers
  // --------------------------------------------------
  String _firstNameFromAdults(List adults) {
    for (final a in adults) {
      if (a is Map && a['name'] is String) {
        final name = (a['name'] as String).trim();
        if (name.isEmpty) continue;
        return name.split(RegExp(r'\s+')).first;
      }
    }
    return '';
  }

  String _initialFor(String name) {
    final n = name.trim();
    if (n.isEmpty) return '?';
    return n[0].toUpperCase();
  }

  List<String> _readStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  String _prettyAllergy(String key) {
    final k = key.trim();
    if (k.isEmpty) return '';
    return k
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _allergiesLine(Map person) {
    final has = person['hasAllergies'] == true;
    if (!has) return 'No allergies selected';

    final list = _readStringList(person['allergies'])
        .map(_prettyAllergy)
        .where((s) => s.isNotEmpty)
        .toList();

    if (list.isEmpty) return 'Allergies selected';

    if (list.length <= 3) return 'Allergies: ${list.join(', ')}';
    return 'Allergies: ${list.take(3).join(', ')} +${list.length - 3}';
  }

  Widget _memberRowCard({
    required BuildContext context,
    required String name,
    required String subtitleLine1,
    Widget? subtitleLine2,
    required VoidCallback onTap,
    required double tileHeight, // ✅ allow different sizes
  }) {
    final theme = Theme.of(context);

    final titleStyle =
        (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 0.6,
      height: 1.0,
    );

    final subStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: AppColors.brandDark.withOpacity(0.75),
      fontWeight: FontWeight.w600,
      height: 1.1,
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: tileHeight,
          child: Row(
            children: [
              Container(
                width: 84,
                height: double.infinity,
                color: const Color(0xFFE3ECEC),
                alignment: Alignment.center,
                child: Text(
                  _initialFor(name),
                  style: (theme.textTheme.headlineSmall ?? const TextStyle())
                      .copyWith(
                    color: AppColors.brandDark,
                    fontWeight: FontWeight.w900,
                    fontVariations: const [FontVariation('wght', 900)],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 2,
                        width: double.infinity,
                        color: AppColors.brandDark.withOpacity(0.12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitleLine1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subStyle,
                      ),
                      if (subtitleLine2 != null) ...[
                        const SizedBox(height: 6),
                        DefaultTextStyle(
                          style: subStyle.copyWith(
                            color: AppColors.brandDark.withOpacity(0.85),
                          ),
                          child: subtitleLine2,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigFilledButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _bigOutlineButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brandDark,
          side:
              BorderSide(color: AppColors.brandDark.withOpacity(0.35), width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  TextStyle _sectionHeading(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: AppColors.brandDark,
      fontWeight: FontWeight.w900,
      fontVariations: const [FontVariation('wght', 900)],
      letterSpacing: 0.8,
      height: 1.0,
    );
  }

  // --------------------------------------------------
  // Build
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    const panelBg = Color(0xFFECF3F4);

    const headingToCardsGap = 12.0;
    const cardGap = 12.0;
    const cardsToButtonGap = 12.0;
    const sectionGap = 40.0;

    // ✅ split heights
    const adultTileHeight = 96.0;
    const childTileHeight = 122.0;

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnap.data;

        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _goToWelcome());
          return const SizedBox.shrink();
        }

        final docRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

        return Scaffold(
          backgroundColor: panelBg,
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: docRef.snapshots(),
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

              final data = snap.data?.data();
              if (data == null) {
                return const Center(child: Text('Profile not ready yet'));
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                _ensureAdult1(docRef, data);
              });

              final adults = (data['adults'] as List?) ?? [];
              final children = (data['children'] as List?) ?? [];

              // ✅ auto-migrate missing childKey fields
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _ensureChildKeys(docRef, children);
              });

              final headerName = _firstNameFromAdults(adults);
              final email = (user.email ?? '').trim();

              final visibleAdults = adults
                  .where((a) =>
                      a is Map &&
                      (a['name'] ?? '').toString().trim().isNotEmpty)
                  .cast<dynamic>()
                  .toList();

              final visibleChildren = children
                  .where((c) =>
                      c is Map &&
                      (c['name'] ?? '').toString().trim().isNotEmpty)
                  .cast<dynamic>()
                  .toList();

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  // ---------------- Header ----------------
                  Container(
                    color: AppColors.brandDark,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (headerName.isEmpty ? 'PROFILE' : headerName)
                                  .toUpperCase(),
                              style: (Theme.of(context).textTheme.headlineSmall ??
                                      const TextStyle())
                                  .copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontVariations: const [
                                  FontVariation('wght', 900)
                                ],
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (email.isNotEmpty)
                              Text(
                                email,
                                style: (Theme.of(context).textTheme.titleMedium ??
                                        const TextStyle())
                                    .copyWith(
                                  color: Colors.white.withOpacity(0.75),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 52,
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Account details (TODO)'),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.35),
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'EDIT ACCOUNT DETAILS',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ---------------- Rounded light panel ----------------
                  Container(
                    color: AppColors.brandDark,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: panelBg,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ---------------- Adults ----------------
                          Text('ADULTS', style: _sectionHeading(context)),
                          const SizedBox(height: headingToCardsGap),

                          if (visibleAdults.isNotEmpty)
                            ...List.generate(visibleAdults.length, (idx) {
                              final raw = visibleAdults[idx] as Map;
                              final name = (raw['name'] ?? '').toString().trim();
                              final i = adults.indexOf(raw);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: cardGap),
                                child: _memberRowCard(
                                  context: context,
                                  name: name,
                                  subtitleLine1: _allergiesLine(raw),
                                  tileHeight: adultTileHeight,
                                  onTap: () async {
                                    final res = await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            AdultProfileScreen(adultIndex: i),
                                      ),
                                    );
                                    await _handleReturnFromProfileEditor(res);
                                  },
                                ),
                              );
                            })
                          else
                            Padding(
                              padding: const EdgeInsets.only(bottom: cardGap),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('No adults added yet.'),
                                ),
                              ),
                            ),

                          const SizedBox(height: cardsToButtonGap),
                          _bigFilledButton(
                            label: 'ADD AN ADULT',
                            onTap: () => _addAdult(docRef, adults),
                          ),

                          const SizedBox(height: sectionGap),

                          // ---------------- Children ----------------
                          Text('CHILDREN', style: _sectionHeading(context)),
                          const SizedBox(height: headingToCardsGap),

                          if (visibleChildren.isNotEmpty)
                            ...List.generate(visibleChildren.length, (idx) {
                              final raw = visibleChildren[idx] as Map;
                              final name = (raw['name'] ?? '').toString().trim();
                              final i = children.indexOf(raw);

                              // ✅ stable ID for first foods
                              final childKey =
                                  (raw['childKey'] ?? '').toString().trim();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: cardGap),
                                child: _memberRowCard(
                                  context: context,
                                  name: name,
                                  subtitleLine1: _allergiesLine(raw),
                                  tileHeight: childTileHeight,
                                  subtitleLine2: (childKey.isEmpty)
                                      ? const Text('0 / 100 foods tried')
                                      : FirstFoodsProgressInline(
                                          childId: childKey, // ✅ stable
                                          baseTotal: 100,
                                        ),
                                  onTap: () async {
                                    final res = await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ChildProfileScreen(childIndex: i),
                                      ),
                                    );
                                    await _handleReturnFromProfileEditor(res);
                                  },
                                ),
                              );
                            })
                          else
                            Padding(
                              padding: const EdgeInsets.only(bottom: cardGap),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('No children added yet.'),
                                ),
                              ),
                            ),

                          const SizedBox(height: cardsToButtonGap),
                          _bigFilledButton(
                            label: 'ADD A CHILD',
                            onTap: () => _addChild(docRef, children),
                          ),

                          const SizedBox(height: 18),

                          _bigOutlineButton(
                            label: 'SETTINGS',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Settings (TODO)'),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _bigOutlineButton(
                            label: 'SIGN OUT',
                            onTap: () async {
                              await FirebaseAuth.instance.signOut();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Inline progress text for Profile cards:
/// - Counts ANY item with any try == true (base + “Other” custom).
/// - Always displays as “X / 100 foods tried”.
class FirstFoodsProgressInline extends StatelessWidget {
  final String childId;
  final int baseTotal;

  const FirstFoodsProgressInline({
    super.key,
    required this.childId,
    this.baseTotal = 100,
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

        return Text(
          '$triedCount / $baseTotal foods tried',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

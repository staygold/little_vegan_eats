// lib/profile/profile_screen.dart
import 'dart:ui' show FontVariation;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ✅ robust import (won't break when moving files)
import 'package:little_vegan_eats/resources/resources_hub_screen.dart';

import '../meal_plan/core/meal_plan_review_service.dart';
import '../theme/app_theme.dart';
import 'adult_profile_screen.dart';
import 'child_profile_screen.dart';
import 'account_details_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _ensuredAdult1 = false;
  bool _hydratingChildKeys = false;

  // ✅ run ensures once per user-doc load to avoid scroll reset loops
  bool _didInitialEnsure = false;

  final ScrollController _scrollController = ScrollController();

  static const String _welcomeRoute = '/';

  // Email verification UX
  bool _emailVerified = true;
  bool _sendingVerify = false;

  void _goToWelcome() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      _welcomeRoute,
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _syncEmailVerified();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // -----------------------
  // ✅ provider helpers
  // -----------------------
  bool _isPasswordUser(User user) {
    // providerId examples: "password", "google.com", "apple.com"
    return user.providerData.any((p) => p.providerId == 'password');
  }

  // -----------------------
  // ✅ unified read
  // -----------------------
  String _readParentName(Map<String, dynamic> data) {
    final parent = data['parent'];
    if (parent is Map && parent['name'] is String) {
      final n = (parent['name'] as String).trim();
      if (n.isNotEmpty) return n;
    }

    if (data['parentName'] is String) {
      final n = (data['parentName'] as String).trim();
      if (n.isNotEmpty) return n;
    }

    return '';
  }

  Future<void> _syncEmailVerified() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Reload once to get freshest emailVerified value
    try {
      await user.reload();
    } catch (_) {}

    final refreshed = FirebaseAuth.instance.currentUser;
    if (!mounted) return;

    setState(() {
      _emailVerified = (refreshed?.emailVerified ?? true);
    });
  }

  Future<void> _resendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _sendingVerify = true);
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send verification email')),
      );
    } finally {
      if (mounted) setState(() => _sendingVerify = false);
    }
  }

  // --------------------------------------------------
  // Ensure Adult 1 from parent.name (new) + parentName (legacy)
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

    final parentName = _readParentName(data);
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
      // ignore
    } finally {
      _hydratingChildKeys = false;
    }
  }

  // --------------------------------------------------
  // Run all ensure/migration steps ONCE (no build callbacks)
  // --------------------------------------------------
  Future<void> _runInitialEnsures(
    DocumentReference<Map<String, dynamic>> docRef,
    Map<String, dynamic> data,
  ) async {
    if (_didInitialEnsure) return;
    _didInitialEnsure = true;

    await _ensureAdult1(docRef, data);

    final children = (data['children'] as List?) ?? [];
    await _ensureChildKeys(docRef, children);
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
    final childKey = FirebaseFirestore.instance.collection('_').doc().id;

    // ✅ store month/year (null initially), not full DOB
    updated.add({
      'childKey': childKey,
      'name': '',
      'dobMonth': null, // int? 1-12
      'dobYear': null, // int? yyyy
      // legacy field intentionally NOT written
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
    required double tileHeight,
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
                        const SizedBox(height: 12),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          side: BorderSide(
            color: AppColors.brandDark.withOpacity(0.35),
            width: 2,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _emailVerifyBanner(BuildContext context, User user) {
    // ✅ Only show for email/password users who are not verified.
    if (!_isPasswordUser(user)) return const SizedBox.shrink();
    if (_emailVerified) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.mark_email_unread_outlined, color: Colors.white),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Please verify your email to secure your account.\nCheck your inbox, then tap “I’ve verified”.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  TextButton(
                    onPressed: _sendingVerify ? null : _resendVerificationEmail,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    child: _sendingVerify
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Resend'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await _syncEmailVerified();
                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _emailVerified ? 'Email verified' : 'Not verified yet',
                          ),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text("I've verified"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const panelBg = Color(0xFFECF3F4);

    const headingToCardsGap = 12.0;
    const cardGap = 12.0;
    const cardsToButtonGap = 12.0;
    const sectionGap = 40.0;

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

        // Keep local state aligned with auth changes (no setState here)
        _emailVerified = user.emailVerified;

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

              // ✅ run migrations ONCE, not via post-frame callback
              _runInitialEnsures(docRef, data);

              final adults = (data['adults'] as List?) ?? [];
              final children = (data['children'] as List?) ?? [];

              final fromAdults = _firstNameFromAdults(adults);
              final fromParent = _readParentName(data)
                  .split(RegExp(r'\s+'))
                  .where((p) => p.isNotEmpty)
                  .toList();
              final headerName = fromAdults.isNotEmpty
                  ? fromAdults
                  : (fromParent.isNotEmpty ? fromParent.first : '');

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
                controller: _scrollController,
                padding: EdgeInsets.zero,
                children: [
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

                            // ✅ only shows for password users + not verified
                            _emailVerifyBanner(context, user),

                            const SizedBox(height: 16),
                            SizedBox(
                              height: 52,
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AccountDetailsScreen(),
                                    ),
                                  );
                                  await _syncEmailVerified();
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
                          Text('CHILDREN', style: _sectionHeading(context)),
                          const SizedBox(height: headingToCardsGap),
                          if (visibleChildren.isNotEmpty)
                            ...List.generate(visibleChildren.length, (idx) {
                              final raw = visibleChildren[idx] as Map;
                              final name = (raw['name'] ?? '').toString().trim();
                              final i = children.indexOf(raw);

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
                                          childId: childKey,
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
                            label: 'RESOURCES',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ResourcesHubScreen(),
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

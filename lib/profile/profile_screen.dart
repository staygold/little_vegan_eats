import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'adult_profile_screen.dart';
import 'child_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _ensuredAdult1 = false;

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

    final parentName =
        (data['parentName'] is String) ? (data['parentName'] as String).trim() : '';

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
  // Add Adult (NO POPUP): create record, go to form
  // Name is enforced in AdultProfileScreen (cannot save unnamed)
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdultProfileScreen(adultIndex: updated.length - 1),
      ),
    );
  }

  // --------------------------------------------------
  // Add Child (NO POPUP): create record, go to form
  // --------------------------------------------------
  Future<void> _addChild(
    DocumentReference<Map<String, dynamic>> docRef,
    List children,
  ) async {
    final updated = [...children];
    updated.add({
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildProfileScreen(childIndex: updated.length - 1),
      ),
    );
  }

  // --------------------------------------------------
  // UI
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnap.data;

        // ✅ If signed out, immediately go back to Welcome route
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _goToWelcome());
          return const SizedBox.shrink();
        }

        final docRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile'),
            actions: [
              IconButton(
                tooltip: 'Log out',
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  // authStateChanges() will flip to null and redirect
                },
              ),
            ],
          ),
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

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    user.email ?? '',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),

                  // ---------------- Adults ----------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Adults', style: Theme.of(context).textTheme.titleMedium),
                      TextButton.icon(
                        onPressed: () => _addAdult(docRef, adults),
                        icon: const Icon(Icons.add),
                        label: const Text('Add adult'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  ...List.generate(adults.length, (i) {
                    final raw = adults[i];
                    final name = (raw is Map && raw['name'] is String)
                        ? (raw['name'] as String).trim()
                        : '';

                    // ✅ Hide unnamed adults
                    if (name.isEmpty) return const SizedBox.shrink();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text('Tap to view / edit allergies'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AdultProfileScreen(adultIndex: i),
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 16),

                  // ---------------- Children ----------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Children', style: Theme.of(context).textTheme.titleMedium),
                      TextButton.icon(
                        onPressed: () => _addChild(docRef, children),
                        icon: const Icon(Icons.add),
                        label: const Text('Add child'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  ...List.generate(children.length, (i) {
                    final raw = children[i];
                    final name = (raw is Map && raw['name'] is String)
                        ? (raw['name'] as String).trim()
                        : '';

                    // ✅ Hide unnamed children
                    if (name.isEmpty) return const SizedBox.shrink();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text('Tap to view / edit'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChildProfileScreen(childIndex: i),
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      // authStateChanges() will redirect
                    },
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

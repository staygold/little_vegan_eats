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

  Future<void> _ensureAdult1(DocumentReference<Map<String, dynamic>> docRef, User user, Map<String, dynamic> data) async {
    if (_ensuredAdult1) return;

    final adults = (data['adults'] as List?) ?? [];
    if (adults.isNotEmpty) {
      _ensuredAdult1 = true;
      return;
    }

    // Create Adult 1 (You)
    final name = (user.displayName?.trim().isNotEmpty == true) ? user.displayName!.trim() : 'Adult 1';

    try {
      await docRef.set({
        'adults': [
          {
            'name': name,
            'hasAllergies': false,
            'allergies': <String>[],
          }
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore, UI still renders
    } finally {
      _ensuredAdult1 = true;
    }
  }

  Future<void> _addAdult(DocumentReference<Map<String, dynamic>> docRef, List adults) async {
    final updated = [...adults];
    updated.add({
      'name': 'Adult ${updated.length + 1}',
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

  Future<void> _addChild(DocumentReference<Map<String, dynamic>> docRef, List children) async {
    final updated = [...children];
    updated.add({
      'name': 'Child ${updated.length + 1}',
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnap.data;

        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
          return const Scaffold(body: Center(child: Text('Signed out')));
        }

        final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile'),
            actions: [
              IconButton(
                tooltip: 'Log out',
                icon: const Icon(Icons.logout),
                onPressed: () async => FirebaseAuth.instance.signOut(),
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
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'User document not found.\n\nThis usually means onboarding has not completed yet.',
                  ),
                );
              }

              // Ensure Adult 1 exists
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _ensureAdult1(docRef, user, data);
              });

              final adults = (data['adults'] as List?) ?? [];
              final children = (data['children'] as List?) ?? [];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(user.email ?? '(no email)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 24),

                  // -------------------------
                  // Adults
                  // -------------------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Adults (${adults.length})', style: Theme.of(context).textTheme.titleMedium),
                      TextButton.icon(
                        onPressed: () => _addAdult(docRef, adults),
                        icon: const Icon(Icons.add),
                        label: const Text('Add adult'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (adults.isEmpty)
                    const Text('No adults saved yet (Adult 1 will be created automatically).')
                  else
                    ...List.generate(adults.length, (i) {
                      final raw = adults[i];
                      final name = (raw is Map && raw['name'] != null)
                          ? raw['name'].toString()
                          : (i == 0 ? 'Adult 1 (You)' : 'Adult ${i + 1}');

                      final label = (i == 0) ? 'Adult 1 (You)' : 'Adult ${i + 1}';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text('$label • $name', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('Tap to view/edit allergies'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => AdultProfileScreen(adultIndex: i)),
                            );
                          },
                        ),
                      );
                    }),

                  const SizedBox(height: 16),

                  // -------------------------
                  // Children
                  // -------------------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Children (${children.length})', style: Theme.of(context).textTheme.titleMedium),
                      TextButton.icon(
                        onPressed: () => _addChild(docRef, children),
                        icon: const Icon(Icons.add),
                        label: const Text('Add child'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (children.isEmpty)
                    const Text('No children saved.')
                  else
                    ...List.generate(children.length, (i) {
                      final raw = children[i];
                      final name = (raw is Map && raw['name'] != null)
                          ? raw['name'].toString()
                          : 'Child ${i + 1}';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('Tap to view/edit'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ChildProfileScreen(childIndex: i)),
                            );
                          },
                        ),
                      );
                    }),

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                    onPressed: () async => FirebaseAuth.instance.signOut(),
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

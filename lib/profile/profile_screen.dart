import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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

        // User signed out while this screen is visible
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });

          return const Scaffold(
            body: Center(child: Text('Signed out')),
          );
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
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'User document not found.\n\nThis usually means onboarding has not completed yet.',
                  ),
                );
              }

              final children = (data['children'] as List?) ?? [];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    user.email ?? '(no email)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),

                  _kv('uid', user.uid),
                  _kv('onboarded', '${data['onboarded']}'),
                  _kv('profileComplete', '${data['profileComplete']}'),
                  _kv('updatedAt', '${data['updatedAt']}'),

                  const SizedBox(height: 24),
                  Text(
                    'Children (${children.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),

                  if (children.isEmpty)
                    const Text('No children saved.')
                  else
                    ...children.map(_childCard).toList(),

                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
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

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              key,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _childCard(dynamic child) {
    if (child is! Map) {
      return Text('Invalid child record: $child');
    }

    final name = child['name']?.toString() ?? '(no name)';
    final dob = child['dob']?.toString() ?? '(no dob)';
    final hasAllergies = child['hasAllergies'];
    final allergies =
        (child['allergies'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('DOB: $dob'),
            if (hasAllergies != null) Text('Has allergies: $hasAllergies'),
            Text(
              'Allergies: ${allergies.isEmpty ? 'None' : allergies.join(', ')}',
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../profile/profile_screen.dart';

class TopHeaderBar extends StatelessWidget {
  const TopHeaderBar({super.key});

  String _deriveName({
    required User user,
    required Map<String, dynamic>? data,
  }) {
    // Try common fields first
    final raw = (data?['firstName'] ??
            data?['first_name'] ??
            data?['name'] ??
            data?['displayName'])
        ?.toString()
        .trim();

    if (raw != null && raw.isNotEmpty) {
      // If it's a full name, take the first word
      return raw.split(' ').first.trim();
    }

    // Fallback: email prefix (before @)
    final email = user.email ?? '';
    if (email.contains('@')) {
      final prefix = email.split('@').first.trim();
      if (prefix.isNotEmpty) return prefix;
    }

    // Last fallback
    return 'Profile';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withOpacity(0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // LEFT: logo / title
          Row(
            children: const [
              Icon(Icons.eco),
              SizedBox(width: 8),
              Text(
                'Little Vegan Eats',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),

          const Spacer(),

          // RIGHT: name + profile button (live)
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, authSnap) {
              final user = authSnap.data;

              // Not logged in → just show "Profile"
              if (user == null) {
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Text('Profile', style: TextStyle(fontWeight: FontWeight.w500)),
                        SizedBox(width: 8),
                        CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16)),
                      ],
                    ),
                  ),
                );
              }

              final docRef =
                  FirebaseFirestore.instance.collection('users').doc(user.uid);

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: docRef.snapshots(),
                builder: (context, docSnap) {
                  final data = docSnap.data?.data();
                  final firstName = _deriveName(user: user, data: data);

                  return InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Text(firstName,
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          const CircleAvatar(
                            radius: 14,
                            child: Icon(Icons.person, size: 16),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

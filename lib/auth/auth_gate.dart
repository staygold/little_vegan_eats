// lib/auth/auth_gate.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'marketing_gate.dart';
import 'verify_email_screen.dart';
import '../onboarding/kids_onboarding_flow.dart';
import '../app/app_shell.dart';
import '../recipes/recipes_bootstrap_gate.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<void> _setVerifySkipped(String uid) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    // Use merge so we don't clobber other fields if doc exists
    await userRef.set(
      {
        'verifySkipped': true,
        'verifySkippedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

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

        // ✅ Signed out → Marketing flow
        if (user == null) return const MarketingGate();

        final userRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userRef.snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (userSnap.hasError) {
              final msg = kDebugMode
                  ? 'Account load error: ${userSnap.error}'
                  : 'Could not load your account. Please try again.';
              return Scaffold(
                body: Center(
                  child: Text(msg, textAlign: TextAlign.center),
                ),
              );
            }

            final exists = userSnap.data?.exists ?? false;
            final data = userSnap.data?.data() ?? <String, dynamic>{};

            final onboarded = data['onboarded'] == true;

            // ✅ verification gate flags
            final verifySkipped = data['verifySkipped'] == true;
            final emailVerified = user.emailVerified;

            // ✅ Signed-in users who are not fully onboarded:
            // Verify screen (unless skipped) → Kids flow
            if (!exists || !onboarded) {
              if (!emailVerified && !verifySkipped) {
                return VerifyEmailScreen(
                  // Keep verify-later visible during onboarding
                  showVerifyLater: true,

                  // If they verify successfully, proceed to kids onboarding.
                  // No navigation needed here because AuthGate will rebuild
                  // (user.emailVerified will become true after reload).
                  onVerified: () {
                    // Optional: nothing required.
                    // If you want, you could also write a flag like `emailVerifiedAt`.
                  },

                  // "Verify later" must NOT pop (can be root -> black screen).
                  // Instead: write verifySkipped=true, which will cause AuthGate
                  // to rebuild and drop into KidsOnboardingFlow.
                  onVerifyLater: () async {
                    try {
                      await _setVerifySkipped(user.uid);
                      // No Navigator calls needed.
                    } catch (e) {
                      // Don't crash the gate; just show a message if possible.
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              kDebugMode
                                  ? 'Could not skip verification: $e'
                                  : 'Could not skip verification. Please try again.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                );
              }

              return const KidsOnboardingFlow();
            }

            // ✅ Fully onboarded → app
            return RecipesBootstrapGate(
              child: const AppShell(initialIndex: 0),
            );
          },
        );
      },
    );
  }
}

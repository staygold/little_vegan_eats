// lib/auth/auth_gate.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'marketing_gate.dart';
import 'verify_email_screen.dart'; // ✅ add this
import '../onboarding/kids_onboarding_flow.dart';
import '../app/app_shell.dart';
import '../recipes/recipes_bootstrap_gate.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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

        // ✅ Signed out → Splash → Carousel → PreAuthFlow
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
            final data = userSnap.data?.data() ?? {};

            final onboarded = data['onboarded'] == true;

            // ✅ verification gate flags
            final verifySkipped = data['verifySkipped'] == true;
            final emailVerified = user.emailVerified;

            // ✅ Signed-in users who are not fully onboarded:
            // Password → Verify screen (unless skipped) → Kids flow
            if (!exists || !onboarded) {
              if (!emailVerified && !verifySkipped) {
                return const VerifyEmailScreen();
              }
              return const KidsOnboardingFlow();
            }

            return RecipesBootstrapGate(
              child: const AppShell(initialIndex: 0),
            );
          },
        );
      },
    );
  }
}

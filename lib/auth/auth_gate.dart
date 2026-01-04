import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../home/welcome_screen.dart';
import '../onboarding/onboarding_flow.dart';
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnap.data;
        if (user == null) return const WelcomeScreen();

        final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userRef.snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            if (userSnap.hasError) {
              final msg = kDebugMode
                  ? 'Account load error: ${userSnap.error}'
                  : 'Could not load your account. Please try again.';
              return Scaffold(body: Center(child: Text(msg, textAlign: TextAlign.center)));
            }

            if (!userSnap.hasData || !(userSnap.data?.exists ?? false)) {
              return const OnboardingFlow();
            }

            final data = userSnap.data!.data() ?? {};
            final onboarded = data['onboarded'] == true;

            if (!onboarded) return const OnboardingFlow();

            return RecipesBootstrapGate(
              child: const AppShell(initialIndex: 0),
            );
          },
        );
      },
    );
  }
}

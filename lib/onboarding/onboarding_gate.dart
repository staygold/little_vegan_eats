import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'onboarding_flow.dart';

class OnboardingGate extends StatelessWidget {
  const OnboardingGate({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: userRef.get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data?.data();

        // You are writing: "onboarded" and "profileComplete"
        final onboarded = data?['onboarded'] == true;

        if (onboarded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacementNamed('/app');
          });
          return const SizedBox.shrink();
        }

        // IMPORTANT: OnboardingFlow does NOT accept userRef in your code.
        return const OnboardingFlow();
      },
    );
  }
}

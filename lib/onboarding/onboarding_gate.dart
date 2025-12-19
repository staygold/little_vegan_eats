// onboarding/onboarding_gate.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'onboarding_flow.dart';

class OnboardingGate extends StatelessWidget {
  const OnboardingGate({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return FutureBuilder<DocumentSnapshot>(
      future: userRef.get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final data = snap.data!.data() as Map<String, dynamic>?;

        final complete = (data?['onboardingComplete'] == true);

        if (complete) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacementNamed('/app');
          });
          return const SizedBox.shrink();
        }

        return OnboardingFlow(userRef: userRef);
      },
    );
  }
}

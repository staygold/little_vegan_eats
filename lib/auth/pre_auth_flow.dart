// lib/auth/pre_auth_flow.dart
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';
import '../onboarding/steps/step_parent_name.dart';
import 'pending_signup.dart';
import 'email_password_signup_screen.dart';
import 'widgets/social_sign_in_buttons.dart';

enum PreAuthStep { name, choose }

class PreAuthFlow extends StatefulWidget {
  const PreAuthFlow({super.key});

  @override
  State<PreAuthFlow> createState() => _PreAuthFlowState();
}

class _PreAuthFlowState extends State<PreAuthFlow> {
  PreAuthStep step = PreAuthStep.name;

  void _backFromName() {
    // If PreAuthFlow was pushed from marketing, this returns to carousel/splash.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    // Fallback: go home/root if somehow it's the root.
    Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    switch (step) {
      case PreAuthStep.name:
        return Scaffold(
          backgroundColor: const Color(0xFFECF3F4),
          body: Column(
            children: [
              SubHeaderBar(
                title: 'Welcome',
                onBack: _backFromName,
              ),
              Expanded(
                child: StepParentName(
                  initialValue: PendingSignup.name,
                  onNext: (name) {
                    PendingSignup.name = name.trim();
                    setState(() => step = PreAuthStep.choose);
                  },
                
                ),
              ),
            ],
          ),
        );

      case PreAuthStep.choose:
        final name = (PendingSignup.name ?? '').trim();

        return Scaffold(
          backgroundColor: const Color(0xFFECF3F4),
          body: Column(
            children: [
              SubHeaderBar(
                title: 'Continue',
                onBack: () => setState(() => step = PreAuthStep.name),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            name.isEmpty ? 'Hi!' : 'Hi $name!',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),

                          // ✅ Email → single combined email+password screen
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EmailPasswordSignupScreen(
                                      initialEmail: null,
                                    ),
                                  ),
                                );
                              },
                              child: const Text(
                                'Continue with Email',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ✅ Apple / Google
                          SocialSignInButtons(),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

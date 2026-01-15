// lib/home/welcome_screen.dart
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';

import '../auth/sign_in_screen.dart';
import '../auth/forgot_password_screen.dart';
import '../auth/widgets/social_sign_in_buttons.dart';
import '../onboarding/onboarding_flow.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _goBack(BuildContext context) {
    // If this screen was pushed, pop.
    // If it’s the first route, go back to MarketingGate/root.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFECF3F4);

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ✅ Sub header with back
          SubHeaderBar(
            title: 'Welcome',
            onBack: () => _goBack(context),
          ),

          // Body
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),

                      const Text(
                        'Little Vegan Eats',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Meal plans and recipes for your family.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black.withOpacity(0.70),
                          height: 1.25,
                        ),
                      ),

                      const SizedBox(height: 26),

                      // 🔐 Apple / Google sign-in
                      const SocialSignInButtons(),

                      const SizedBox(height: 22),

                      // Divider
                      Row(
                        children: [
                          Expanded(
                            child: Divider(color: Colors.black.withOpacity(0.15)),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(color: Colors.black.withOpacity(0.15)),
                          ),
                        ],
                      ),

                      const SizedBox(height: 22),

                      // Register → onboarding flow
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const OnboardingFlow()),
                            );
                          },
                          child: const Text(
                            'CREATE ACCOUNT',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Sign in (email/password)
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SignInScreen()),
                            );
                          },
                          child: const Text(
                            'SIGN IN',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Logged-out password recovery
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: const Text('Forgot password?'),
                      ),
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

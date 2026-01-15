import 'package:flutter/material.dart';

import 'pre_auth_flow.dart';
import 'splash_screen.dart';
import 'intro_carousel.dart';
import 'sign_in_screen.dart';

enum MarketingStep { splash, carousel, signup }

class MarketingGate extends StatefulWidget {
  const MarketingGate({super.key});

  @override
  State<MarketingGate> createState() => _MarketingGateState();
}

class _MarketingGateState extends State<MarketingGate> {
  MarketingStep step = MarketingStep.splash;

  void _openLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (step) {
      case MarketingStep.splash:
        return SplashScreen(
          onExplore: () => setState(() => step = MarketingStep.carousel),
          onLogin: _openLogin,
        );

      case MarketingStep.carousel:
        return IntroCarousel(
          onGetStarted: () => setState(() => step = MarketingStep.signup),
          onLogin: _openLogin,
        );

      case MarketingStep.signup:
        return const PreAuthFlow();
    }
  }
}

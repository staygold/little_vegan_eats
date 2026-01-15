import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    required this.onExplore,
    required this.onLogin,
  });

  final VoidCallback onExplore;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              // Replace with your logo / hero later
              Text(
                'Little Vegan Eats',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Vegan recipes + meal planning for families.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),

              const Spacer(),

              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: onExplore,
                  child: const Text('Explore'),
                ),
              ),
              const SizedBox(height: 10),

              TextButton(
                onPressed: onLogin,
                child: const Text('Already have an account? Log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

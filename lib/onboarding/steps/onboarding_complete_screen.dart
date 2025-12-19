import 'package:flutter/material.dart';

class OnboardingCompleteScreen extends StatelessWidget {
  const OnboardingCompleteScreen({
    super.key,
    required this.onFinish,
    this.childrenNames = const [],
  });

  final Future<void> Function() onFinish;
  final List<String> childrenNames;

  @override
  Widget build(BuildContext context) {
    final names = childrenNames.where((n) => n.trim().isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Done')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'All set!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  names.isEmpty
                      ? 'Your account is ready.'
                      : 'Added ${names.length} ${names.length == 1 ? 'child' : 'children'}: ${names.join(', ')}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    await onFinish();
                  },
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class StepChildAllergiesYesNo extends StatelessWidget {
  const StepChildAllergiesYesNo({
    super.key,
    required this.childName,
    required this.onYes,
    required this.onNo,
    this.onBack,
  });

  final String childName;
  final VoidCallback onYes;
  final VoidCallback onNo;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Allergies'),
        leading: onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Does $childName have allergies?', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onYes, child: const Text('Yes')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onNo, child: const Text('No')),
          ],
        ),
      ),
    );
  }
}

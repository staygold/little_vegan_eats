import 'package:flutter/material.dart';

class StepAnotherChild extends StatelessWidget {
  const StepAnotherChild({
    super.key,
    required this.lastChildName,
    required this.onYes,
    required this.onNo,
    this.onBack,
  });

  final String lastChildName;
  final VoidCallback onYes;
  final VoidCallback onNo;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add family'),
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
            Text('Added $lastChildName ✅', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            const Text('Do you have any other kids?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
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

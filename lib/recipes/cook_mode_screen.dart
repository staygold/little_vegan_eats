import 'package:flutter/material.dart';


class CookModeScreen extends StatefulWidget {
  const CookModeScreen({super.key, required this.title, required this.steps});
  final String title;
  final List<String> steps;

  @override
  State<CookModeScreen> createState() => _CookModeScreenState();
}

class _CookModeScreenState extends State<CookModeScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final hasSteps = widget.steps.isNotEmpty;
    final stepText = hasSteps ? widget.steps[index] : 'No steps found.';

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasSteps
                  ? 'Step ${index + 1} of ${widget.steps.length}'
                  : 'Cook Mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  stepText,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (!hasSteps || index == 0)
                        ? null
                        : () => setState(() => index--),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (!hasSteps || index >= widget.steps.length - 1)
                        ? null
                        : () => setState(() => index++),
                    child: const Text('Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
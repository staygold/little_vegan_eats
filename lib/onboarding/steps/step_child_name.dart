import 'package:flutter/material.dart';

class StepChildName extends StatefulWidget {
  const StepChildName({
    super.key,
    required this.onNext,
    this.onBack,
    this.onSkip,
  });

  final void Function(String name) onNext;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  State<StepChildName> createState() => _StepChildNameState();
}

class _StepChildNameState extends State<StepChildName> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    if (v.isEmpty) return;
    widget.onNext(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: const Text('Child'),
        actions: [
          if (widget.onSkip != null)
            TextButton(onPressed: widget.onSkip, child: const Text('Skip'))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Child name', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'First name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: const Text('Continue')),
          ],
        ),
      ),
    );
  }
}

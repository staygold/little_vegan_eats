import 'package:flutter/material.dart';

class StepParentName extends StatefulWidget {
  const StepParentName({
    super.key,
    required this.onNext,
    this.onBack,
    this.initialValue,
  });

  final void Function(String name) onNext;
  final VoidCallback? onBack;
  final String? initialValue;

  @override
  State<StepParentName> createState() => _StepParentNameState();
}

class _StepParentNameState extends State<StepParentName> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _continue() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    widget.onNext(name);
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _ctrl.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your details'),
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('What’s your name?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _continue(),
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: canContinue ? _continue : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

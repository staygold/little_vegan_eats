import 'package:flutter/material.dart';

class StepEmail extends StatefulWidget {
  const StepEmail({
    super.key,
    required this.onNext,
    this.onBack,
    this.initialValue,
  });

  final void Function(String email) onNext;
  final VoidCallback? onBack;
  final String? initialValue;

  @override
  State<StepEmail> createState() => _StepEmailState();
}

class _StepEmailState extends State<StepEmail> {
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

  bool get _valid {
    final v = _ctrl.text.trim();
    return v.contains('@') && v.contains('.');
  }

  void _continue() {
    final email = _ctrl.text.trim();
    if (!_valid) return;
    widget.onNext(email);
  }

  @override
  Widget build(BuildContext context) {
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
            const Text('What’s your email?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _continue(),
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _valid ? _continue : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

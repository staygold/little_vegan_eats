import 'package:flutter/material.dart';

class StepChildDob extends StatefulWidget {
  const StepChildDob({
    super.key,
    required this.childName,
    required this.onNext,
    this.onBack,
    this.initialValue,
  });

  final String childName;
  final void Function(DateTime dob) onNext;
  final VoidCallback? onBack;
  final DateTime? initialValue;

  @override
  State<StepChildDob> createState() => _StepChildDobState();
}

class _StepChildDobState extends State<StepChildDob> {
  DateTime? dob;

  @override
  void initState() {
    super.initState();
    dob = widget.initialValue;
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: dob ?? DateTime(now.year - 2, now.month, now.day),
      firstDate: DateTime(now.year - 18, 1, 1),
      lastDate: now,
    );
    if (picked != null) setState(() => dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    final label = dob == null
        ? 'Select date'
        : '${dob!.year}-${dob!.month.toString().padLeft(2, '0')}-${dob!.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add family'),
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
            Text('When was ${widget.childName} born?', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _pick, child: Text(label)),
            const Spacer(),
            FilledButton(
              onPressed: dob == null ? null : () => widget.onNext(dob!),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

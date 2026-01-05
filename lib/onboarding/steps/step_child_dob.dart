// lib/onboarding/steps/step_child_dob.dart
import 'package:flutter/material.dart';

class StepChildDob extends StatefulWidget {
  const StepChildDob({
    super.key,
    required this.childName,
    required this.onNext,
    this.onBack,
    this.initialMonth,
    this.initialYear,
  });

  final String childName;
  final void Function(int month, int year) onNext;
  final VoidCallback? onBack;

  final int? initialMonth; // 1-12
  final int? initialYear;

  @override
  State<StepChildDob> createState() => _StepChildDobState();
}

class _StepChildDobState extends State<StepChildDob> {
  int? _month;
  int? _year;

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
    _year = widget.initialYear;
  }

  List<DropdownMenuItem<int>> _monthItems() {
    const names = <String>[
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return List.generate(12, (i) {
      final m = i + 1;
      return DropdownMenuItem<int>(
        value: m,
        child: Text('${names[i]}'),
      );
    });
  }

  List<DropdownMenuItem<int>> _yearItems() {
    final now = DateTime.now();
    final maxY = now.year;
    final minY = now.year - 18;
    final years = <int>[];
    for (int y = maxY; y >= minY; y--) {
      years.add(y);
    }
    return years
        .map((y) => DropdownMenuItem<int>(value: y, child: Text('$y')))
        .toList();
  }

  String _label() {
    if (_month == null || _year == null) return 'Select month and year';
    const names = <String>[
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${names[_month! - 1]} $_year';
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _month != null && _year != null;

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
            Text(
              'When was ${widget.childName} born?',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'We only ask for month and year to protect your child’s privacy.',
            ),
            const SizedBox(height: 16),

            // Month
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Month'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _month,
                  isExpanded: true,
                  hint: const Text('Select month'),
                  items: _monthItems(),
                  onChanged: (v) => setState(() => _month = v),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Year
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Year'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _year,
                  isExpanded: true,
                  hint: const Text('Select year'),
                  items: _yearItems(),
                  onChanged: (v) => setState(() => _year = v),
                ),
              ),
            ),

            const SizedBox(height: 14),
            Text(_label(), textAlign: TextAlign.center),

            const Spacer(),
            FilledButton(
              onPressed: canContinue ? () => widget.onNext(_month!, _year!) : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

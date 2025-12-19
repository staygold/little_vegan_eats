import 'package:flutter/material.dart';

class StepChildAllergies extends StatefulWidget {
  const StepChildAllergies({
    super.key,
    required this.childName,
    required this.onConfirm,
    this.onBack,
    this.initialSelected,
  });

  final String childName;
  final void Function(List<String> allergies) onConfirm;
  final VoidCallback? onBack;
  final List<String>? initialSelected;

  @override
  State<StepChildAllergies> createState() => _StepChildAllergiesState();
}

class _StepChildAllergiesState extends State<StepChildAllergies> {
  late final Set<String> selected;

  // Vegan-relevant food allergies/intolerances (no dairy/egg etc)
  final options = const [
    'Peanuts',
    'Tree nuts',
    'Soy',
    'Wheat / Gluten',
    'Sesame',
    'Mustard',
    'Celery',
    'Lupin',
    'Sulphites',
    'Coconut',
    'Legumes (general)',
  ];

  @override
  void initState() {
    super.initState();
    selected = {...(widget.initialSelected ?? const <String>[])};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
        title: Text('Allergies'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Does ${widget.childName} have any allergies?',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select allergies',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: options.map((a) {
                  final checked = selected.contains(a);
                  return CheckboxListTile(
                    title: Text(a),
                    value: checked,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected.add(a);
                      } else {
                        selected.remove(a);
                      }
                    }),
                  );
                }).toList(),
              ),
            ),
            FilledButton(
              onPressed: () => widget.onConfirm(selected.toList()..sort()),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

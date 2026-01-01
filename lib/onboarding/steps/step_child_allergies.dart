import 'package:flutter/material.dart';

// IMPORTANT:
// We store canonical keys (e.g. "soy", "gluten") so AllergyEngine works everywhere.
// We still display friendly labels ("Soy", "Wheat / Gluten") in the UI.

class StepChildAllergies extends StatefulWidget {
  const StepChildAllergies({
    super.key,
    required this.childName,
    required this.onConfirm,
    this.onBack,
    this.initialSelected,
  });

  final String childName;
  final void Function(List<String> allergies) onConfirm; // canonical keys
  final VoidCallback? onBack;

  /// Can be old labels (e.g. "Soy") OR canonical keys (e.g. "soy")
  final List<String>? initialSelected;

  @override
  State<StepChildAllergies> createState() => _StepChildAllergiesState();
}

class _StepChildAllergiesState extends State<StepChildAllergies> {
  late final Set<String> selectedKeys; // canonical keys only

  /// Canonical keys your AllergyEngine supports today.
  static const Set<String> supportedKeys = {
    'peanut',
    'tree_nut',
    'soy',
    'gluten',
    'sesame',
    'coconut',
    'seed',
  };

  /// All options you want to show in onboarding.
  /// key = what we store
  /// label = what user sees
  ///
  /// NOTE: Some are not supported by the engine yet. We still store them
  /// so you can support them later, but we warn the user.
  static const List<_AllergyOption> options = [
    _AllergyOption(key: 'peanut', label: 'Peanuts'),
    _AllergyOption(key: 'tree_nut', label: 'Tree nuts'),
    _AllergyOption(key: 'soy', label: 'Soy'),
    _AllergyOption(key: 'gluten', label: 'Wheat / Gluten'),
    _AllergyOption(key: 'sesame', label: 'Sesame'),
    _AllergyOption(key: 'mustard', label: 'Mustard'),
    _AllergyOption(key: 'celery', label: 'Celery'),
    _AllergyOption(key: 'lupin', label: 'Lupin'),
    _AllergyOption(key: 'sulphites', label: 'Sulphites'),
    _AllergyOption(key: 'coconut', label: 'Coconut'),
    _AllergyOption(key: 'seed', label: 'Seeds'),
    _AllergyOption(key: 'legumes', label: 'Legumes (general)'),
  ];

  @override
  void initState() {
    super.initState();
    selectedKeys = {};

    final initial = widget.initialSelected ?? const <String>[];
    for (final raw in initial) {
      final key = _canonicalizeFromAnything(raw);
      if (key != null) selectedKeys.add(key);
    }
  }

  // Accepts:
  // - canonical keys: "soy"
  // - old labels: "Soy", "Wheat / Gluten", etc
  // - slight variants: "peanuts", "tree nuts"
  String? _canonicalizeFromAnything(String raw) {
    final s = raw.trim().toLowerCase();

    // If already canonical key:
    for (final o in options) {
      if (s == o.key) return o.key;
    }

    // Handle label-based / legacy values:
    if (s == 'soy') return 'soy';
    if (s == 'peanut' || s == 'peanuts') return 'peanut';
    if (s == 'tree nut' ||
        s == 'tree nuts' ||
        s == 'nuts' ||
        s == 'nut' ||
        s == 'tree_nut') {
      return 'tree_nut';
    }
    if (s == 'sesame') return 'sesame';
    if (s == 'wheat / gluten' ||
        s == 'wheat/gluten' ||
        s == 'gluten' ||
        s == 'wheat') {
      return 'gluten';
    }
    if (s == 'coconut') return 'coconut';

    // Seeds
    if (s == 'seed' || s == 'seeds') return 'seed';

    // Not yet supported by engine, but we keep them:
    if (s == 'mustard') return 'mustard';
    if (s == 'celery') return 'celery';
    if (s == 'lupin') return 'lupin';
    if (s == 'sulphites' || s == 'sulfites') return 'sulphites';
    if (s == 'legumes (general)' || s == 'legumes' || s == 'legume') {
      return 'legumes';
    }

    return null;
  }

  bool _isSupportedByEngine(String key) => supportedKeys.contains(key);

  @override
  Widget build(BuildContext context) {
    final selectedUnsupported =
        selectedKeys.where((k) => !_isSupportedByEngine(k)).toList();

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
        title: const Text('Allergies'),
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

            if (selectedUnsupported.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Text(
                  "Note: Some selected allergies aren't fully supported yet and may not filter recipes reliably: "
                  "${selectedUnsupported.join(', ')}",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],

            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: options.map((opt) {
                  final checked = selectedKeys.contains(opt.key);
                  final supported = _isSupportedByEngine(opt.key);

                  return CheckboxListTile(
                    title: Text(opt.label),
                    subtitle: supported ? null : const Text('Not fully supported yet'),
                    value: checked,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          selectedKeys.add(opt.key);
                        } else {
                          selectedKeys.remove(opt.key);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            FilledButton(
              onPressed: () {
                final out = selectedKeys.toList()..sort();
                widget.onConfirm(out);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllergyOption {
  final String key;
  final String label;
  const _AllergyOption({required this.key, required this.label});
}

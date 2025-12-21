class ChildProfile {
  final String name;
  final bool hasAllergies;
  final List<String> allergies; // canonical keys like ["soy", "peanut"]

  const ChildProfile({
    required this.name,
    required this.hasAllergies,
    required this.allergies,
  });

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChildProfile &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          hasAllergies == other.hasAllergies &&
          _listEquals(allergies, other.allergies);

  @override
  int get hashCode =>
      name.hashCode ^ hasAllergies.hashCode ^ allergies.join('|').hashCode;

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}


enum AllergyStatus {
  safe,
  swapRequired,
  notSuitable,
}

class AllergyResult {
  final AllergyStatus status;
  final List<String> detectedAllergens; // keys
  final List<String> swapNotes; // user-facing: "Soy milk → oat milk"

  const AllergyResult({
    required this.status,
    required this.detectedAllergens,
    required this.swapNotes,
  });
}

class AllergyEngine {
  // MVP: conservative keyword packs.
  // It's better to flag too much than miss an allergen.
  static const Map<String, List<String>> allergenKeywords = {
    'soy': [
      'soy',
      'soya',
      'soy milk',
      'tofu',
      'tempeh',
      'edamame',
      'miso',
      'tamari',
      'shoyu',
      'soy sauce',
    ],
    'peanut': ['peanut', 'peanuts', 'peanut butter'],
    'tree_nut': [
      'almond',
      'cashew',
      'walnut',
      'pecan',
      'hazelnut',
      'pistachio',
      'macadamia',
    ],
    'sesame': ['sesame', 'tahini'],
    'gluten': [
      'wheat',
      'flour',
      'bread',
      'pasta',
      'noodles',
      'soy sauce', // often contains wheat unless tamari
    ],
    // Optional: if you collect this in onboarding
    'coconut': ['coconut', 'coconut milk', 'coconut cream', 'coconut oil'],
    // Optional: if you collect this in onboarding
    'seed': ['sunflower', 'sunflower seed', 'sesame', 'tahini', 'pumpkin seed'],
  };

  // High-confidence swap rules for MVP.
  // IMPORTANT: swapRequired is only possible when we detect a specific trigger phrase.
  static const List<_SwapRule> swapRules = [
    _SwapRule(
      allergen: 'soy',
      triggers: ['soy milk'],
      replacements: [
        _ReplacementOption(label: 'oat milk', blocksIfAllergicTo: []),
        _ReplacementOption(label: 'rice milk', blocksIfAllergicTo: []),
        _ReplacementOption(label: 'coconut milk', blocksIfAllergicTo: ['coconut']),
        _ReplacementOption(label: 'almond milk', blocksIfAllergicTo: ['tree_nut']),
      ],
      noteTemplate: 'Soy milk → {replacement}',
    ),
    _SwapRule(
      allergen: 'peanut',
      triggers: ['peanut butter'],
      replacements: [
        _ReplacementOption(label: 'sunflower seed butter', blocksIfAllergicTo: ['seed']),
      ],
      noteTemplate: 'Peanut butter → {replacement}',
    ),
  ];

  static AllergyResult evaluateRecipe({
    required String ingredientsText,
    required List<String> childAllergies,
    required bool includeSwapRecipes,
  }) {
    final text = ingredientsText.toLowerCase();

    // 1) Detect allergens based on child profile
    final detected = <String>[];
    for (final allergen in childAllergies) {
      final keys = allergenKeywords[allergen];
      if (keys == null || keys.isEmpty) continue;

      if (_containsAny(text, keys)) {
        detected.add(allergen);
      }
    }

    if (detected.isEmpty) {
      return const AllergyResult(
        status: AllergyStatus.safe,
        detectedAllergens: [],
        swapNotes: [],
      );
    }

    // 2) If swaps are not included, anything detected is not suitable
    if (!includeSwapRecipes) {
      return AllergyResult(
        status: AllergyStatus.notSuitable,
        detectedAllergens: detected,
        swapNotes: const [],
      );
    }

    // 3) Try to build swaps for each detected allergen
    final swapNotes = <String>[];
    final covered = <String>{};

    for (final allergen in detected) {
      final rules = swapRules.where((r) => r.allergen == allergen).toList();
      if (rules.isEmpty) continue;

      for (final r in rules) {
        // Require the specific trigger (e.g. "soy milk"), not generic "soy".
        if (!_containsAny(text, r.triggers)) continue;

        final replacement = r.pickReplacementAvoiding(childAllergies);
        if (replacement == null) continue;

        swapNotes.add(r.noteTemplate.replaceAll('{replacement}', replacement));
        covered.add(allergen);
        break;
      }
    }

    // Only allow swapRequired if ALL detected allergens are covered
    final allCovered = detected.every(covered.contains);
    if (allCovered && swapNotes.isNotEmpty) {
      return AllergyResult(
        status: AllergyStatus.swapRequired,
        detectedAllergens: detected,
        swapNotes: swapNotes,
      );
    }

    return AllergyResult(
      status: AllergyStatus.notSuitable,
      detectedAllergens: detected,
      swapNotes: swapNotes,
    );
  }

  static bool _containsAny(String text, List<String> needles) {
    for (final n in needles) {
      final needle = n.toLowerCase().trim();
      if (needle.isEmpty) continue;
      if (text.contains(needle)) return true;
    }
    return false;
  }
}

// ---------- internal types ----------
class _SwapRule {
  final String allergen;
  final List<String> triggers;
  final List<_ReplacementOption> replacements;
  final String noteTemplate;

  const _SwapRule({
    required this.allergen,
    required this.triggers,
    required this.replacements,
    required this.noteTemplate,
  });

  String? pickReplacementAvoiding(List<String> childAllergies) {
    for (final r in replacements) {
      final blocked = r.blocksIfAllergicTo.any(childAllergies.contains);
      if (!blocked) return r.label;
    }
    return null;
  }
}

class _ReplacementOption {
  final String label;
  final List<String> blocksIfAllergicTo;

  const _ReplacementOption({
    required this.label,
    required this.blocksIfAllergicTo,
  });
}

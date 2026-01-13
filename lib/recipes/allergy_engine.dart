// lib/recipes/allergy_engine.dart
import 'package:flutter/foundation.dart';

enum SuitabilityMode { wholeFamily, allChildren, specificPeople }

enum AllergyStatus { safe, swapRequired, notSuitable, unknown }

class AllergyEvaluationResult {
  final AllergyStatus status;
  final List<String> blockingIngredients;
  final List<String> swapIngredients;

  const AllergyEvaluationResult({
    required this.status,
    this.blockingIngredients = const [],
    this.swapIngredients = const [],
  });
}

@immutable
class AllergiesSelection {
  final bool enabled;
  final SuitabilityMode mode;
  final Set<String> personIds;

  // ✅ THE NEW FLAGS
  final bool hideUnsafe;   // Default: true (Hide red recipes)
  final bool strictAge;    // Default: false (Show "too old" recipes with warning)
  final bool includeSwaps; // Default: true (Show amber recipes)

  const AllergiesSelection({
    this.enabled = true,
    this.mode = SuitabilityMode.wholeFamily,
    this.personIds = const {},
    this.hideUnsafe = true,  // Safety First
    this.strictAge = false,  // Flexibility First
    this.includeSwaps = true,
  });

  int get activeCount {
    if (!enabled) return 0;
    int count = 1;
    // We count strict modifications as active filters
    if (!hideUnsafe) count++;
    if (strictAge) count++;
    if (!includeSwaps) count++;
    return count;
  }

  AllergiesSelection copyWith({
    bool? enabled,
    SuitabilityMode? mode,
    Set<String>? personIds,
    bool? hideUnsafe,
    bool? strictAge,
    bool? includeSwaps,
  }) {
    return AllergiesSelection(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      personIds: personIds ?? this.personIds,
      hideUnsafe: hideUnsafe ?? this.hideUnsafe,
      strictAge: strictAge ?? this.strictAge,
      includeSwaps: includeSwaps ?? this.includeSwaps,
    );
  }
}

class AllergyEngine {
  static AllergyEvaluationResult evaluate({
    required List<String> recipeAllergyTags,
    required String swapFieldText,
    required List<String> userAllergies,
  }) {
    if (userAllergies.isEmpty) return const AllergyEvaluationResult(status: AllergyStatus.safe);
    
    final lowerTags = recipeAllergyTags.map((e) => e.trim().toLowerCase()).toSet();
    final lowerUser = userAllergies.map((e) => e.trim().toLowerCase()).toSet();
    final swapContent = swapFieldText.toLowerCase();

    final blocking = <String>[];
    final swappable = <String>[];

    for (final allergy in lowerUser) {
      if (lowerTags.contains(allergy)) {
        if (swapContent.contains(allergy)) {
          swappable.add(allergy);
        } else {
          blocking.add(allergy);
        }
      }
    }

    if (blocking.isNotEmpty) {
      return AllergyEvaluationResult(status: AllergyStatus.notSuitable, blockingIngredients: blocking);
    }
    if (swappable.isNotEmpty) {
      return AllergyEvaluationResult(status: AllergyStatus.swapRequired, swapIngredients: swappable);
    }
    return const AllergyEvaluationResult(status: AllergyStatus.safe);
  }
}
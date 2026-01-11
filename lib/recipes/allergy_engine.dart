// lib/recipes/allergy_engine.dart
import 'allergy_keys.dart';

/// How the UI chooses which people to consider when filtering.
/// (Used by recipe pages / filters UI, not required by MealPlanController.)
enum SuitabilityMode { wholeFamily, allChildren, specificPeople }

class AllergiesSelection {
  final bool enabled;
  final SuitabilityMode mode;

  /// Selected people (when mode == specificPeople)
  final Set<String> personIds;

  /// If true: allow recipes that are "swap required"
  final bool includeSwaps;

  const AllergiesSelection({
    this.enabled = true,
    this.mode = SuitabilityMode.wholeFamily,
    this.personIds = const <String>{},
    this.includeSwaps = false,
  });

  int get activeCount {
    if (!enabled) return 0;
    int n = 1; // enabled
    if (includeSwaps) n += 1;
    return n;
  }

  AllergiesSelection copyWith({
    bool? enabled,
    SuitabilityMode? mode,
    Set<String>? personIds,
    bool? includeSwaps,
  }) {
    return AllergiesSelection(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      personIds: personIds ?? this.personIds,
      includeSwaps: includeSwaps ?? this.includeSwaps,
    );
  }
}

enum AllergyStatus { safe, swapRequired, notSuitable }

class AllergyResult {
  final AllergyStatus status;

  /// Optional hint you can populate later if you want UI copy.
  final String? swapHint;

  const AllergyResult({required this.status, this.swapHint});
}

/// ✅ V1 engine: ONLY uses
/// - recipe allergy tags (canonicalized)
/// - swap field text (free text mentioning allergens / keys)
///
/// There is NO ingredient scanning in this file.
class AllergyEngine {
  /// Evaluate a recipe against user allergies using:
  /// - recipeAllergyTags: list of allergy tags applied to the recipe (strings or slugs)
  /// - swapFieldText: text where you might mention swappable allergens (e.g. "swap soy milk...")
  /// - userAllergies: list of allergy strings from the user profile
  ///
  /// Rules:
  /// - If user has no allergies -> safe
  /// - If recipe has no allergy tags -> safe (nothing to match against)
  /// - If a user allergy is present in recipe tags:
  ///     - if also present in swap text -> swapRequired
  ///     - otherwise -> notSuitable
  static AllergyResult evaluate({
    required List<String> recipeAllergyTags,
    required String swapFieldText,
    required List<String> userAllergies,
  }) {
    if (userAllergies.isEmpty) {
      return const AllergyResult(status: AllergyStatus.safe);
    }

    final recipeKeys = _canonicalizeRecipeTags(recipeAllergyTags);
    if (recipeKeys.isEmpty) {
      // No tag signal -> can't decide anything unsafe in v1.
      return const AllergyResult(status: AllergyStatus.safe);
    }

    final swapKeys = _extractSwapKeys(swapFieldText);

    bool anyBlocked = false;
    bool anySwappable = false;

    for (final raw in userAllergies) {
      final k = AllergyKeys.normalize(raw);
      if (k == null) continue;

      // Only matters if the recipe is tagged with this allergy key.
      if (!recipeKeys.contains(k)) continue;

      // If swap text mentions it, treat as swappable.
      if (swapKeys.contains(k)) {
        anySwappable = true;
      } else {
        anyBlocked = true;
      }
    }

    if (anyBlocked) {
      return const AllergyResult(status: AllergyStatus.notSuitable);
    }
    if (anySwappable) {
      return const AllergyResult(status: AllergyStatus.swapRequired);
    }
    return const AllergyResult(status: AllergyStatus.safe);
  }

  /// Convenience: convert evaluate() result into "allowed" based on UI preference.
  /// - allowSwaps=false => only SAFE passes
  /// - allowSwaps=true  => SAFE + SWAP_REQUIRED pass
  static bool isAllowed({
    required List<String> recipeAllergyTags,
    required String swapFieldText,
    required List<String> userAllergies,
    required bool allowSwaps,
  }) {
    final res = evaluate(
      recipeAllergyTags: recipeAllergyTags,
      swapFieldText: swapFieldText,
      userAllergies: userAllergies,
    );

    if (res.status == AllergyStatus.safe) return true;
    if (allowSwaps && res.status == AllergyStatus.swapRequired) return true;
    return false;
  }

  /// Canonicalize recipe tags into normalized allergy keys.
  static Set<String> _canonicalizeRecipeTags(List<String> tags) {
    final out = <String>{};
    for (final t in tags) {
      final k = AllergyKeys.normalize(t);
      if (k != null) out.add(k);
    }
    return out;
  }

  /// Extract allergy keys from swap text.
  ///
  /// Strategy:
  /// 1) direct substring match for known keys (fast path)
  /// 2) token scan + normalize() for synonyms
  static Set<String> _extractSwapKeys(String text) {
    final s = text.toLowerCase();
    if (s.trim().isEmpty) return <String>{};

    final out = <String>{};

    // 1) direct key mentions
    for (final k in AllergyKeys.allKeys) {
      if (s.contains(k.toLowerCase())) out.add(k);
    }

    // 2) token scan for synonyms that normalize()
    final tokens = s
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((x) => x.trim().isNotEmpty)
        .toList();

    for (final tok in tokens) {
      final k = AllergyKeys.normalize(tok);
      if (k != null) out.add(k);
    }

    return out;
  }
}

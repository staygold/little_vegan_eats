/// Canonical allergy keys used across profiles, recipes, and meal planning
class AllergyKeys {
  static const Set<String> supported = {
    'soy',
    'peanut',
    'tree_nut',
    'sesame',
    'gluten',
    'coconut',
    'seed',
  };

  static bool isSupported(String? key) {
    if (key == null) return false;
    final k = key.trim();
    if (k.isEmpty) return false;
    return supported.contains(k);
  }
}

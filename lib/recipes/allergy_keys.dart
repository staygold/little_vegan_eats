// lib/recipes/allergy_keys.dart

class AllergyKeys {
  static const soy = 'soy';
  static const peanut = 'peanut';
  static const treeNut = 'tree_nut';
  static const sesame = 'sesame';
  static const gluten = 'gluten';
  static const coconut = 'coconut';
  static const seed = 'seed';

  // optional / future
  static const mustard = 'mustard';
  static const celery = 'celery';
  static const lupin = 'lupin';
  static const sulphites = 'sulphites';
  static const legumes = 'legumes';

  static const supported = <String>[
    soy, peanut, treeNut, sesame, gluten, coconut, seed,
  ];

  static const all = <String>[
    soy, peanut, treeNut, sesame, gluten, coconut, seed,
    mustard, celery, lupin, sulphites, legumes,
  ];

  // Useful for scanning swap text.
  static const allKeys = all;

  static String label(String key) {
    switch (key) {
      case soy: return 'Soy';
      case peanut: return 'Peanuts';
      case treeNut: return 'Tree nuts';
      case sesame: return 'Sesame';
      case gluten: return 'Gluten/Wheat';
      case coconut: return 'Coconut';
      case seed: return 'Seeds';
      case mustard: return 'Mustard';
      case celery: return 'Celery';
      case lupin: return 'Lupin';
      case sulphites: return 'Sulphites';
      case legumes: return 'Legumes (general)';
      default: return key;
    }
  }

  /// Accepts BOTH onboarding labels and canonical keys.
  static String? normalize(String raw) {
    final s = raw.trim().toLowerCase();

    // already canonical
    if (all.contains(s)) return s;

    // labels/synonyms
    if (s == 'soy') return soy;
    if (s == 'peanut' || s == 'peanuts') return peanut;

    if (s == 'tree nut' || s == 'tree nuts' || s == 'nuts' || s == 'nut') {
      return treeNut;
    }

    if (s == 'sesame') return sesame;

    if (s == 'gluten' ||
        s == 'wheat' ||
        s == 'wheat / gluten' ||
        s == 'wheat/gluten') {
      return gluten;
    }

    if (s == 'coconut') return coconut;

    if (s == 'seed' || s == 'seeds') return seed;

    // optional
    if (s == 'mustard') return mustard;
    if (s == 'celery') return celery;
    if (s == 'lupin') return lupin;
    if (s == 'sulphites') return sulphites;
    if (s == 'legumes (general)' || s == 'legumes') return legumes;

    return null;
  }
}

// lib/lists/shopping_engine.dart

class ShoppingEngine {
  ShoppingEngine._();

  // ---------------------------------------------------------------------------
  // Exclusions (e.g., plain water should not appear in shopping list)
  // ---------------------------------------------------------------------------

  /// Returns true if this ingredient name is "plain water" (tap/filtered/hot/cold/etc.)
  /// and should NOT appear on shopping lists.
  ///
  /// IMPORTANT: We DO NOT exclude things like "coconut water", "sparkling water",
  /// "rose water", etc.
  static bool shouldExcludeFromShoppingName(String rawName) {
    final n = _Norm.canonicalName(rawName);

    if (n.isEmpty) return false;

    // Keep common "water" products / ingredients
    // (add more here if you find false positives)
    const keepIfContains = <String>[
      'coconut water',
      'sparkling water',
      'soda water',
      'mineral water',
      'rose water',
      'orange flower water',
      'lavender water',
      'distilled water', // arguably a product, but keep (user might buy it)
    ];
    for (final k in keepIfContains) {
      if (n.contains(k)) return false;
    }

    // If it doesn't mention water, don't exclude.
    if (!n.contains('water')) return false;

    // Strip common descriptors and punctuation around water
    // to detect "plain water".
    var t = n;

    // Remove common adjectives/phrases that still mean plain water.
    const plainDescriptors = <String>[
      'tap',
      'filtered',
      'drinking',
      'fresh',
      'clean',
      'warm',
      'hot',
      'cold',
      'boiling',
      'boiled',
      'room temperature',
      'room-temp',
      'lukewarm',
      'tepid',
    ];

    // Remove "for ..." notes that often appear: "water for boiling", "water for cooking"
    t = t.replaceAll(RegExp(r'\bfor\b.*$'), '').trim();

    for (final d in plainDescriptors) {
      t = t.replaceAll(RegExp(r'\b' + RegExp.escape(d) + r'\b'), '').trim();
    }

    // Collapse whitespace
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();

    // After stripping, if it's exactly "water", exclude.
    if (t == 'water') return true;

    // Also exclude common plain variants like "water to boil", "water to mix" after partial stripping
    // (kept conservative: only if it starts with "water" and has no other meaningful noun)
    if (t.startsWith('water ')) {
      // If remaining words are only generic cooking verbs, treat as plain water.
      final rest = t.substring('water'.length).trim();
      const generic = <String>[
        'to',
        'boil',
        'boiling',
        'cook',
        'cooking',
        'mix',
        'mixing',
        'soak',
        'soaking',
        'steam',
        'steaming',
        'thin',
        'thinning',
        'dilute',
        'diluting',
      ];
      final tokens = rest.split(' ').where((x) => x.isNotEmpty).toList();
      if (tokens.isNotEmpty && tokens.every((x) => generic.contains(x))) {
        return true;
      }
    }

    return false;
  }

  /// Convenience: check a built shopping item map.
  static bool shouldExcludeFromShoppingItem(Map<String, dynamic> item) {
    final name = (item['name'] ?? item['text'] ?? '').toString().trim();
    return shouldExcludeFromShoppingName(name);
  }

  // ---------------------------------------------------------------------------
  // Keys + names
  // ---------------------------------------------------------------------------

  /// Stable dedupe key for Firestore doc id (lowercase, hyphenated)
  static String normalizeKey(String rawName) => _Norm.normalizeNameKey(rawName);

  /// Canonical display name (title case of canonical form)
  static String canonicalDisplayName(String rawName) =>
      _titleCase(_Norm.canonicalName(rawName));

  static String normalizeUnit(String rawUnit) => _Norm.normUnit(rawUnit);

  static double? parseAmountToDouble(String rawAmount) =>
      _Norm.parseAmount(rawAmount);

  static bool isNonSummableCookingMeasure(String unit) =>
      _Norm.isNonSummableCookingMeasure(unit);

  static bool isSummableUnit(String unit) => _Norm.isSummableUnit(unit);

  static ({double qty, String unit}) toBaseUnits(double qty, String unit) =>
      _Norm.toBase(qty, unit);

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  static String? sectionForItem(Map<String, dynamic> item) {
    final explicit = (item['section'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;

    final name =
        (item['name'] ?? item['text'] ?? '').toString().toLowerCase().trim();
    if (name.isEmpty) return null;

    final unit = (item['sumUnitBase'] ??
            item['sumUnitMetric'] ??
            item['sumUnitUs'] ??
            item['sumUnitUS'] ??
            item['sumUnit'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();

    return classifySection(
      canonicalNameLower: _Norm.canonicalName(name),
      unit: unit,
    );
  }

  static String classifySection({
    required String canonicalNameLower,
    required String unit,
  }) {
    final n = canonicalNameLower;
    final u = _Norm.normUnit(unit);

    bool hasAny(List<String> terms) => terms.any((t) => n.contains(t));

    // 1. Pantry
    const pantry = [
      // Staples
      'flour', 'sugar', 'salt', 'pepper', 'rice', 'pasta', 'oats', 'lentils',
      'beans', 'chickpeas', 'oil', 'vinegar', 'soy sauce', 'tamari', 'yeast',
      'baking powder', 'baking soda', 'chocolate', 'cacao', 'cocoa', 'syrup',
      'honey', 'coffee', 'tea',

      // Nuts & Seeds (Added)
      'nut', 'nuts', 'walnut', 'almond', 'cashew', 'pecan', 'hazelnut',
      'pistachio', 'macadamia', 'seed', 'chia', 'flax', 'hemp', 'sesame',
      'pumpkin seed', 'sunflower',

      // Bakery-ish staples
      'bread', 'wrap', 'tortilla', 'pita', 'bagel', 'bun', 'roll',

      // Packaging types
      'tinned', 'canned', 'can', 'jar', 'pack',

      // Herbs & Spices
      'spice', 'spices', 'herb', 'herbs', 'seasoning', 'condiment', 'sauce',
      'dried', 'ground', 'powder', 'flake', 'extract', 'vanilla',
      'cumin', 'paprika', 'cinnamon', 'nutmeg', 'clove', 'cardamom',
      'turmeric', 'curry', 'chilli', 'chili', 'cayenne', 'saffron',
      'oregano', 'thyme', 'rosemary', 'sage', 'bay leaf', 'dill', 'fennel'
    ];

    if (hasAny(pantry)) return 'Pantry';
    if (u == 'can' || u == 'jar' || u == 'pack') return 'Pantry';

    // 2. Fresh
    const fresh = [
      'apple', 'banana', 'berries', 'berry', 'spinach', 'lettuce', 'tomato',
      'onion', 'garlic', 'carrot', 'lemon', 'lime', 'cucumber', 'capsicum',
      'pepper', 'broccoli', 'mushroom', 'avocado', 'zucchini', 'courgette',
      'potato', 'sweet potato', 'pumpkin', 'kale', 'cabbage', 'celery', 'ginger',
      'fruit', 'vegetable', 'salad',
      // Specific fresh herbs
      'basil', 'parsley', 'coriander', 'cilantro', 'mint', 'chives'
    ];

    if (hasAny(fresh)) return 'Fresh';

    // 3. Chilled & Frozen
    const chilledFrozen = [
      'milk', 'yoghurt', 'yogurt', 'cheese', 'tofu', 'tempeh', 'cream',
      'butter', 'margarine', 'frozen', 'ice', 'peas', 'corn', 'edamame',
      // Pastry (Added)
      'pastry', 'puff', 'dough', 'filo', 'phyllo'
    ];

    if (hasAny(chilledFrozen)) return 'Chilled & Frozen';

    return 'Other';
  }

  // ---------------------------------------------------------------------------
  // Secondary line (single mode: "You need X in total")
  // ---------------------------------------------------------------------------

  static String? buildSecondaryLine(
    Map<String, dynamic> item, {
    required String unitSystem,
  }) {
    final units = unitSystem.toLowerCase().trim(); // metric|us

    if (units == 'us') {
      // 1) Prefer explicit US summed totals if they exist
      final usQty = _asDouble(item['sumQtyUs'] ?? item['sumQtyUS']);
      final usUnit =
          (item['sumUnitUs'] ?? item['sumUnitUS'] ?? '').toString().trim();

      if (usQty != null && usQty > 0) {
        final qtyStr = _prettyQty(usQty, usUnit);
        return 'You need $qtyStr in total';
      }

      // 2) Otherwise try examplesUs
      final examplesUs = _stringList(item['examplesUs']);
      final chunkUs = _bestMeasureChunk(examplesUs);

      if (chunkUs != null) {
        return 'You need $chunkUs in total';
      }

      // 3) Fallback to metric
      return _buildMetricSecondary(item);
    }

    // Metric
    return _buildMetricSecondary(item);
  }

  static String? _buildMetricSecondary(Map<String, dynamic> item) {
    final sumQty =
        _asDouble(item['sumQtyBase'] ?? item['sumQtyMetric'] ?? item['sumQty']);
    final sumUnit =
        (item['sumUnitBase'] ?? item['sumUnitMetric'] ?? item['sumUnit'] ?? '')
            .toString()
            .trim();

    if (sumQty != null && sumQty > 0) {
      final qtyStr = _prettyQty(sumQty, sumUnit);
      return 'You need $qtyStr in total';
    }

    final examplesMetric = _stringList(item['examplesMetric']);
    final chunkMetric = _bestMeasureChunk(examplesMetric);
    if (chunkMetric != null) return 'You need $chunkMetric in total';

    final examples = _stringList(item['examples']);
    final chunk = _bestMeasureChunk(examples);
    if (chunk != null) return 'You need $chunk in total';

    return null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static List<String> _stringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString())
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static double? _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    final s = (v ?? '').toString().trim();
    return double.tryParse(s);
  }

  static String? _bestMeasureChunk(List<String> examples) {
    if (examples.isEmpty) return null;

    final uniq = <String>{};
    for (final e in examples) {
      final cleaned = _stripTrailingNotes(e);
      if (cleaned.isEmpty) continue;
      uniq.add(cleaned);
      if (uniq.length >= 8) break;
    }

    String? firstNaked;

    for (final line in uniq) {
      final chunk = _extractMeasureChunk(line);
      if (chunk.isEmpty) continue;

      if (_isNakedNumber(chunk)) {
        firstNaked ??= chunk;
        continue;
      }
      return chunk;
    }

    return firstNaked;
  }

  static bool _isNakedNumber(String s) {
    final t = s.trim();
    return RegExp(r'^\d+(?:\.\d+)?$').hasMatch(t);
  }

  static String _stripTrailingNotes(String s) {
    var t = s.trim();
    t = t.replaceAll(r'\/', '/');
    t = t.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), ' ').trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static String _extractMeasureChunk(String line) {
    var t = line.trim();
    if (t.isEmpty) return '';

    t = t.replaceAll(r'\/', '/');
    const slashClass = r'(?:/|⁄|∕)';

    final m = RegExp(
      r'^('
      r'\d+\s+\d+' + slashClass + r'\d+' // Mixed: 1 1/2
      r'|\d+' + slashClass + r'\d+' // Fractions: 2/3
      r'|[½⅓⅔¼¾⅛⅜⅝⅞]' // Unicode
      r'|\d+(?:\.\d+)?' // Int/Dec: 2 or 2.5
      r')\s*([a-zA-Z\-]+)?',
    ).firstMatch(t);

    if (m == null) return '';

    final amount = (m.group(1) ?? '').trim();
    final unitRaw = (m.group(2) ?? '').trim();

    if (amount.isEmpty) return '';
    if (unitRaw.isEmpty) return amount;

    final unitNorm = _Norm.normUnit(unitRaw);
    if (!_Norm.isKnownUnit(unitNorm)) {
      return amount;
    }

    return '$amount $unitNorm'.trim();
  }

  static String _prettyQty(double qty, String unit) {
    final u = _Norm.normUnit(unit);
    final valueStr = _fmt(qty);

    if (u.isEmpty) return valueStr;

    String displayUnit = u;
    if (qty > 1) {
      const plurals = {
        'clove': 'cloves',
        'can': 'cans',
        'tin': 'tins',
        'jar': 'jars',
        'pack': 'packs',
        'bag': 'bags',
        'handful': 'handfuls',
        'pinch': 'pinches',
      };
      if (plurals.containsKey(u)) {
        displayUnit = plurals[u]!;
      }
    }

    return '$valueStr $displayUnit'.trim();
  }

  static String _fmt(double v) {
    final isInt = (v - v.roundToDouble()).abs() < 0.0001;
    if (isInt) return v.round().toString();

    // Recover common cooking fractions
    if ((v - 1 / 3).abs() < 0.02) return '1/3';
    if ((v - 2 / 3).abs() < 0.02) return '2/3';
    if ((v - 0.25).abs() < 0.01) return '1/4';
    if ((v - 0.75).abs() < 0.01) return '3/4';
    if ((v - 0.5).abs() < 0.01) return '1/2';
    if ((v - 0.125).abs() < 0.01) return '1/8';

    return v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  }

  static String _titleCase(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    return t
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .map((w) => w.length == 1
            ? w.toUpperCase()
            : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

// ============================================================================
// Internal normalisation + parsing
// ============================================================================

class _Norm {
  static final _space = RegExp(r'\s+');
  static final _nonWord = RegExp(r'[^a-z0-9\s]');
  static final _multiDash = RegExp(r'-+');

  static const Map<String, String> aliases = {
    'chick peas': 'chickpeas',
    'garbanzo beans': 'chickpeas',
  };

  static String canonicalName(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll('&', 'and');
    s = s.replaceAll(_nonWord, ' ');
    s = s.replaceAll(_space, ' ').trim();
    if (aliases.containsKey(s)) s = aliases[s]!;
    return s;
  }

  static String normalizeNameKey(String raw) {
    var s = canonicalName(raw);
    s = s.replaceAll(' ', '-');
    s = s.replaceAll(_multiDash, '-').trim();
    if (s.isEmpty) s = 'item';
    if (s.length > 150) s = s.substring(0, 150);
    return s;
  }

  /// Parses cooking-ish numeric strings (ints, decimals, 1/2, 1 1/2, unicode)
  /// + ✅ supports "2 x" / "2x" scale notation used by the UI.
  static double? parseAmount(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    // Normalize whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // ✅ handle "2x" / "2 x"
    // We accept only a leading number + optional x, and treat it as numeric.
    final compact = s.replaceAll(' ', '');
    final mx =
        RegExp(r'^(\d+(?:\.\d+)?)x$', caseSensitive: false).firstMatch(compact);
    if (mx != null) return double.tryParse(mx.group(1)!);

    s = s.replaceAll(r'\/', '/');

    const unicode = {
      '½': 0.5,
      '⅓': 1 / 3,
      '⅔': 2 / 3,
      '¼': 0.25,
      '¾': 0.75,
      '⅛': 0.125,
      '⅜': 0.375,
      '⅝': 0.625,
      '⅞': 0.875,
    };
    if (unicode.containsKey(s)) return unicode[s];

    const slashClass = r'(?:/|⁄|∕)';

    final mixed =
        RegExp(r'^(\d+)\s+(\d+)\s*' + slashClass + r'\s*(\d+)$').firstMatch(s);
    if (mixed != null) {
      final whole = double.parse(mixed.group(1)!);
      final a = double.parse(mixed.group(2)!);
      final b = double.parse(mixed.group(3)!);
      if (b == 0) return null;
      return whole + (a / b);
    }

    final frac =
        RegExp(r'^(\d+)\s*' + slashClass + r'\s*(\d+)$').firstMatch(s);
    if (frac != null) {
      final a = double.parse(frac.group(1)!);
      final b = double.parse(frac.group(2)!);
      if (b == 0) return null;
      return a / b;
    }

    return double.tryParse(s);
  }

  static String normUnit(String raw) {
    var u = raw.toLowerCase().trim();
    if (u.isEmpty) return '';

    const map = {
      'grams': 'g',
      'gram': 'g',
      'g': 'g',
      'kilograms': 'kg',
      'kilogram': 'kg',
      'kg': 'kg',
      'milliliters': 'ml',
      'millilitre': 'ml',
      'millilitres': 'ml',
      'milliliter': 'ml',
      'ml': 'ml',
      'liter': 'l',
      'litre': 'l',
      'liters': 'l',
      'litres': 'l',
      'l': 'l',
      'tsp': 'tsp',
      'teaspoon': 'tsp',
      'teaspoons': 'tsp',
      'tbsp': 'tbsp',
      'tablespoon': 'tbsp',
      'tablespoons': 'tbsp',
      'cup': 'cup',
      'cups': 'cup',
      'can': 'can',
      'cans': 'can',
      'tin': 'can',
      'tins': 'can',
      'jar': 'jar',
      'jars': 'jar',
      'pack': 'pack',
      'packs': 'pack',
      'clove': 'clove',
      'cloves': 'clove',
      'pinch': 'pinch',
      'handful': 'handful',
      'dash': 'dash',
      'to taste': 'to-taste',
      'to-taste': 'to-taste',
      'bag': 'bag',
      'bags': 'bag',
    };

    return map[u] ?? u;
  }

  static bool isKnownUnit(String unit) {
    final u = normUnit(unit);
    return {
      'g',
      'kg',
      'ml',
      'l',
      'tsp',
      'tbsp',
      'cup',
      'can',
      'jar',
      'pack',
      'clove',
      'pinch',
      'handful',
      'dash',
      'to-taste',
      'bag',
    }.contains(u);
  }

  static bool isSummableUnit(String unit) {
    final u = normUnit(unit);
    return {'g', 'kg', 'ml', 'l', 'can', 'jar', 'pack', 'clove', 'bag'}
        .contains(u);
  }

  static bool isNonSummableCookingMeasure(String unit) {
    final u = normUnit(unit);
    return {'tsp', 'tbsp', 'cup', 'pinch', 'handful', 'dash', 'to-taste'}
        .contains(u);
  }

  static ({double qty, String unit}) toBase(double qty, String unit) {
    final u = normUnit(unit);
    if (u == 'kg') return (qty: qty * 1000.0, unit: 'g');
    if (u == 'l') return (qty: qty * 1000.0, unit: 'ml');
    return (qty: qty, unit: u);
  }
}

// lib/recipes/serving_engine.dart
import 'dart:math';

enum ServingMode {
  shared,
  countable,
}

class ServingAdvice {
  final String headline;

  /// ✅ This should now be ONLY the “Your family needs …” line
  final String detailLine;

  final String? extra;

  /// The raw multiplier needed (can be fractional like 1.18)
  final double multiplierRaw;

  /// shared vs countable (so UI can decide whether half-batch is allowed)
  final ServingMode mode;

  /// If we recommend scaling, we give a “nice” multiplier (0.5, 1.5, 2.0, 2.5...)
  /// Use this for “Update ingredients to Xx”.
  final double? recommendedMultiplier;

  /// If true, UI can show a “Make half a batch” CTA.
  final bool canHalf;

  const ServingAdvice({
    required this.headline,
    required this.detailLine,
    required this.multiplierRaw,
    required this.mode,
    this.recommendedMultiplier,
    this.extra,
    this.canHalf = false,
  });
}

ServingAdvice buildServingAdvice({
  required Map<String, dynamic>? recipe,
  required int adults,
  required int kids,
}) {
  final a = max(0, adults);
  final k = max(0, kids);

  if (a + k == 0) {
    return const ServingAdvice(
      headline: 'Set your family size',
      detailLine: 'Add adults/kids in your profile to get serving guidance.',
      multiplierRaw: 1.0,
      mode: ServingMode.shared,
    );
  }

  final mode = _getServingMode(recipe);

  // ✅ agreed model:
  // 1 adult = 1.0, 1 kid = 0.5
  final adultEquivalentNeeded = a + (k * 0.5);

  if (mode == ServingMode.countable) {
    return _countableAdvice(
      recipe: recipe,
      adults: a,
      kids: k,
    );
  }

  return _sharedAdvice(
    recipe: recipe,
    adultEquivalentNeeded: adultEquivalentNeeded,
    adults: a,
    kids: k,
  );
}

ServingMode _getServingMode(Map<String, dynamic>? recipe) {
  // Prefer the nested "tags" map if present (WPRM recipe payload)
  final tags = recipe?['tags'];
  final servingMode = tags is Map ? tags['serving_mode'] : null;

  if (servingMode is List && servingMode.isNotEmpty) {
    final first = servingMode.first;
    if (first is Map) {
      final slug = (first['slug'] ?? '').toString().toLowerCase();
      final name = (first['name'] ?? '').toString().toLowerCase();

      // Flexible detection: "countable", "count", "items", etc.
      if (slug.contains('count') || name.contains('count')) return ServingMode.countable;
      if (slug.contains('item') || name.contains('item')) return ServingMode.countable;
    }
  }

  // Default assumption: shared dish (servings = adult servings)
  return ServingMode.shared;
}

/// Shared dish advice: WPRM "servings" = adult servings
ServingAdvice _sharedAdvice({
  required Map<String, dynamic>? recipe,
  required double adultEquivalentNeeded,
  required int adults,
  required int kids,
}) {
  final baseServings = _num(recipe?['servings']) ?? 0;
  final base = baseServings > 0 ? baseServings.toDouble() : 0.0;

  if (base <= 0) {
    return const ServingAdvice(
      headline: 'Serving info missing',
      detailLine: 'This recipe is missing a base servings value in WPRM.',
      multiplierRaw: 1.0,
      mode: ServingMode.shared,
      extra: 'Set WPRM “Servings” to adult servings (e.g. 4).',
    );
  }

  final multiplier = adultEquivalentNeeded / base;

  // ✅ UI requested: ONLY the “Your family needs…” line (no family breakdown, no base recipe sentence)
  final detailLine = 'You need the equivalent of ~${_fmt1(adultEquivalentNeeded)} adult portions';

  // Half-batch rule (shared dishes only):
  // show if you need <= 65% of base (i.e. base is clearly too big)
  final canHalf = multiplier <= 0.65;

  if (multiplier <= 1.0) {
    return ServingAdvice(
      headline: 'Perfect for your family',
      detailLine: detailLine,
      multiplierRaw: multiplier,
      mode: ServingMode.shared,
      canHalf: canHalf,
      extra: canHalf ? 'Optional: make a half batch.' : 'No need to scale.',
    );
  }

  final rec = _niceMultiplier(multiplier);

  return ServingAdvice(
    headline: 'You may want to make more',
    detailLine: detailLine,
    multiplierRaw: multiplier,
    mode: ServingMode.shared,
    recommendedMultiplier: rec,
    canHalf: false,
    extra: 'Recommended: ${_fmtMultiplier(rec)} batch.',
  );
}

/// Countable advice: WPRM "servings" = makes X items
/// Uses your taxonomy: items_per_person (or wprm_items_per_person)
ServingAdvice _countableAdvice({
  required Map<String, dynamic>? recipe,
  required int adults,
  required int kids,
}) {
  final makes = _num(recipe?['servings']) ?? 0;
  final itemsPerPerson = _itemsPerPerson(recipe) ?? 0;

  if (makes <= 0 || itemsPerPerson <= 0) {
    return const ServingAdvice(
      headline: 'Countable item',
      detailLine: 'This looks countable, but “makes” or items-per-person is missing.',
      multiplierRaw: 1.0,
      mode: ServingMode.countable,
      extra: 'Set WPRM Servings to “makes” (e.g. 20) and assign Items Per Person (e.g. 5).',
    );
  }

  // For countables, use people count (kids count as people here).
  final people = adults + kids;
  final itemsNeeded = people * itemsPerPerson;

  final multiplier = itemsNeeded / makes;

  // ✅ UI requested: ONLY the “Your family needs…” line
  final detailLine = 'You need the equivalent of ~${_fmt0(itemsNeeded.toDouble())} adult portions';

  if (multiplier <= 1.0) {
    return ServingAdvice(
      headline: 'Enough for your family',
      detailLine: detailLine,
      multiplierRaw: multiplier,
      mode: ServingMode.countable,
      canHalf: false,
      extra: 'Items per person: $itemsPerPerson',
    );
  }

  final rec = _niceMultiplier(multiplier);

  return ServingAdvice(
    headline: 'You may want to make more',
    detailLine: detailLine,
    multiplierRaw: multiplier,
    mode: ServingMode.countable,
    recommendedMultiplier: rec,
    canHalf: false,
    extra: 'Recommended: ${_fmtMultiplier(rec)} batch (items/person: $itemsPerPerson).',
  );
}

int? _itemsPerPerson(Map<String, dynamic>? recipe) {
  final tags = recipe?['tags'];
  if (tags is! Map) return null;

  // Support multiple possible keys
  dynamic list = tags['items_per_person'];
  list ??= tags['wprm_items_per_person'];

  if (list is! List || list.isEmpty) return null;

  final first = list.first;

  if (first is Map) {
    final slug = (first['slug'] ?? '').toString().trim();
    final name = (first['name'] ?? '').toString().trim();

    final fromSlug = int.tryParse(slug) ??
        int.tryParse(slug.replaceAll(RegExp(r'[^0-9]'), ''));
    if (fromSlug != null && fromSlug > 0) return fromSlug;

    final fromName = int.tryParse(name) ??
        int.tryParse(name.replaceAll(RegExp(r'[^0-9]'), ''));
    if (fromName != null && fromName > 0) return fromName;
  }

  if (first is String) {
    final v = int.tryParse(first) ??
        int.tryParse(first.replaceAll(RegExp(r'[^0-9]'), ''));
    if (v != null && v > 0) return v;
  }

  if (first is num) {
    final v = first.toInt();
    if (v > 0) return v;
  }

  return null;
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

String _familyLine({required int adults, required int kids}) {
  final parts = <String>[];
  if (adults > 0) parts.add('$adults adult${adults == 1 ? '' : 's'}');
  if (kids > 0) parts.add('$kids kid${kids == 1 ? '' : 's'}');
  return parts.isEmpty ? 'Family' : parts.join(' + ');
}

double _niceMultiplier(double raw) {
  // we only use this when raw > 1.0
  if (raw <= 1.25) return 1.5;
  if (raw <= 1.75) return 2.0;
  if (raw <= 2.25) return 2.5;
  if (raw <= 2.75) return 3.0;
  return raw.ceilToDouble();
}

String _fmt0(double v) => v.round().toString();

String _fmt1(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

String _fmtMultiplier(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? '${s.substring(0, s.length - 2)}x' : '${s}x';
}

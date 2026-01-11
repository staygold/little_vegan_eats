// lib/meal_plan/widgets/meal_plan_entry_parser.dart

class MealPlanEntryParser {
  MealPlanEntryParser._();

  static int? recipeIdFromAny(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static String _typeOf(Map<String, dynamic> m) =>
      (m['type'] ?? '').toString().trim().toLowerCase();

  static String? _stringOrNull(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  static Map<String, dynamic>? parse(dynamic raw) {
    if (raw == null) return null;

    // legacy: raw int/num = recipe id
    if (raw is int) {
      return {'type': 'recipe', 'recipeId': raw, 'source': 'auto'};
    }
    if (raw is num) {
      return {'type': 'recipe', 'recipeId': raw.toInt(), 'source': 'auto'};
    }

    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final type = _typeOf(m);

      // -----------------------------
      // NOTE
      // -----------------------------
      if (type == 'note') {
        final text = _stringOrNull(m['text']);
        if (text == null) return null;
        return {'type': 'note', 'text': text};
      }

      // -----------------------------
      // RECIPE
      // -----------------------------
      if (type == 'recipe') {
        final rid = recipeIdFromAny(m['recipeId']);
        if (rid == null) return null;

        return {
          'type': 'recipe',
          'recipeId': rid,
          'source': (m['source'] ?? 'auto').toString(),
          if (m['audience'] != null) 'audience': (m['audience'] ?? '').toString(),
          if (m['childKey'] != null) 'childKey': (m['childKey'] ?? '').toString(),
          if (m['childName'] != null) 'childName': (m['childName'] ?? '').toString(),
          if (m['_reuseFrom'] is Map)
            '_reuseFrom': Map<String, dynamic>.from(m['_reuseFrom']),
        };
      }

      // -----------------------------
      // REUSE
      // -----------------------------
      if (type == 'reuse') {
        final fromDayKey = _stringOrNull(m['fromDayKey']);
        final fromSlot = _stringOrNull(m['fromSlot']);
        if (fromDayKey == null || fromSlot == null) return null;
        return {'type': 'reuse', 'fromDayKey': fromDayKey, 'fromSlot': fromSlot};
      }

      // -----------------------------
      // FIRST FOODS (baby snacks)
      // -----------------------------
      if (type == 'first_foods') {
        final childKey = _stringOrNull(m['childKey']);
        if (childKey == null) return null;

        final childName = _stringOrNull(m['childName']);
        final audience = _stringOrNull(m['audience']) ?? '';
        final source = _stringOrNull(m['source']) ?? 'auto';

        return {
          'type': 'first_foods',
          'childKey': childKey,
          if (childName != null) 'childName': childName,
          'audience': audience,
          'source': source,
        };
      }

      // -----------------------------
      // CLEAR / CLEARED
      // -----------------------------
      // clear = explicit empty
      // cleared = persisted locked empty
      // We normalize both to type: clear, while preserving metadata.
      if (type == 'clear' || type == 'cleared') {
        final reason = _stringOrNull(m['reason']);
        final childKey = _stringOrNull(m['childKey']);
        final childName = _stringOrNull(m['childName']);
        final audience = _stringOrNull(m['audience']);
        final source = _stringOrNull(m['source']);

        return {
          'type': 'clear',
          if (reason != null) 'reason': reason,
          if (childKey != null) 'childKey': childKey,
          if (childName != null) 'childName': childName,
          if (audience != null) 'audience': audience,
          if (source != null) 'source': source,
        };
      }

      // Sometimes controller gives us already-resolved entries with _reuseFrom attached
      if (m['_reuseFrom'] is Map && (type == 'recipe' || type == 'note')) {
        return m;
      }
    }

    return null;
  }

  static int? entryRecipeId(Map<String, dynamic>? e) {
    if (e == null) return null;
    if ((e['type'] ?? '').toString() != 'recipe') return null;
    return recipeIdFromAny(e['recipeId']);
  }

  static String? entryNoteText(Map<String, dynamic>? e) {
    if (e == null) return null;
    if ((e['type'] ?? '').toString() != 'note') return null;
    final t = (e['text'] ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  static bool isFirstFoods(Map<String, dynamic>? e) =>
      e != null && (e['type'] ?? '').toString() == 'first_foods';

  static bool isClear(Map<String, dynamic>? e) =>
      e == null || (e['type'] ?? '').toString().trim().isEmpty || (e['type'] ?? '').toString() == 'clear';

  static String? clearReason(Map<String, dynamic>? e) {
    if (e == null) return null;
    if ((e['type'] ?? '').toString() != 'clear') return null;
    final r = (e['reason'] ?? '').toString().trim();
    return r.isEmpty ? null : r;
  }

  static String? childName(Map<String, dynamic>? e) {
    final n = (e?['childName'] ?? '').toString().trim();
    return n.isEmpty ? null : n;
  }

  static String? childKey(Map<String, dynamic>? e) {
    final k = (e?['childKey'] ?? '').toString().trim();
    return k.isEmpty ? null : k;
  }

  /// ✅ If entry is resolved and has reuse meta, return it
  static Map<String, String>? entryReuseFrom(Map<String, dynamic>? e) {
    if (e == null) return null;

    // resolved entries have `_reuseFrom`
    final meta = e['_reuseFrom'];
    if (meta is Map) {
      final m = Map<String, dynamic>.from(meta);
      final dayKey = (m['dayKey'] ?? '').toString().trim();
      final slot = (m['slot'] ?? '').toString().trim();
      if (dayKey.isEmpty || slot.isEmpty) return null;
      return {'dayKey': dayKey, 'slot': slot};
    }

    // raw reuse entry
    if ((e['type'] ?? '').toString() == 'reuse') {
      final dayKey = (e['fromDayKey'] ?? '').toString().trim();
      final slot = (e['fromSlot'] ?? '').toString().trim();
      if (dayKey.isEmpty || slot.isEmpty) return null;
      return {'dayKey': dayKey, 'slot': slot};
    }

    return null;
  }
}

// lib/meal_plan/widgets/meal_plan_entry_parser.dart

class MealPlanEntryParser {
  MealPlanEntryParser._();

  static int? recipeIdFromAny(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static Map<String, dynamic>? parse(dynamic raw) {
    if (raw == null) return null;

    // legacy: raw int = recipe id
    if (raw is int) {
      return {'type': 'recipe', 'recipeId': raw, 'source': 'auto'};
    }
    if (raw is num) {
      return {'type': 'recipe', 'recipeId': raw.toInt(), 'source': 'auto'};
    }

    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final type = (m['type'] ?? '').toString();

      if (type == 'note') {
        final text = (m['text'] ?? '').toString().trim();
        if (text.isEmpty) return null;
        return {'type': 'note', 'text': text};
      }

      if (type == 'recipe') {
        final rid = recipeIdFromAny(m['recipeId']);
        if (rid == null) return null;
        return {
          'type': 'recipe',
          'recipeId': rid,
          'source': (m['source'] ?? 'auto').toString(),
          if (m['_reuseFrom'] is Map)
            '_reuseFrom': Map<String, dynamic>.from(m['_reuseFrom']),
        };
      }

      if (type == 'reuse') {
        final fromDayKey = (m['fromDayKey'] ?? '').toString().trim();
        final fromSlot = (m['fromSlot'] ?? '').toString().trim();
        if (fromDayKey.isEmpty || fromSlot.isEmpty) return null;
        return {'type': 'reuse', 'fromDayKey': fromDayKey, 'fromSlot': fromSlot};
      }

      // ✅ Explicit empty states
      //
      // `clear` is an in-memory UI intent (treat as empty).
      if (type == 'clear') {
        return {'type': 'clear'};
      }

      // ✅ `cleared` is the persisted "locked empty" state (treat as empty for UI,
      // but keep it explicit so screens *can* distinguish it if needed).
      if (type == 'cleared') {
        return {'type': 'clear'};
      }

      // Sometimes controller gives us already-resolved entries with _reuseFrom attached
      if (m['_reuseFrom'] is Map && (type == 'recipe' || type == 'note')) {
        return m;
      }
    }

    return null;
  }

  static int? entryRecipeId(Map<String, dynamic>? e) {
    if (e == null || e['type'] != 'recipe') return null;
    return recipeIdFromAny(e['recipeId']);
  }

  static String? entryNoteText(Map<String, dynamic>? e) {
    if (e == null || e['type'] != 'note') return null;
    final t = (e['text'] ?? '').toString().trim();
    return t.isEmpty ? null : t;
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
    if (e['type'] == 'reuse') {
      final dayKey = (e['fromDayKey'] ?? '').toString().trim();
      final slot = (e['fromSlot'] ?? '').toString().trim();
      if (dayKey.isEmpty || slot.isEmpty) return null;
      return {'dayKey': dayKey, 'slot': slot};
    }

    return null;
  }
}

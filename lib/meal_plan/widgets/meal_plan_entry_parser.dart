// lib/meal_plan/widgets/meal_plan_entry_parser.dart

class MealPlanEntryParser {
  MealPlanEntryParser._();

  // ------------------------------------
  // BASIC COERCION HELPERS
  // ------------------------------------
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

  static Map<String, dynamic>? _mapOrNull(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static List<dynamic>? _listOrNull(dynamic v) {
    if (v is List) return v;
    return null;
  }

  // ------------------------------------
  // PARSE
  // ------------------------------------
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

      // If controller gives already-resolved entries with _reuseFrom attached,
      // keep them as-is so we don't lose extra fields (warnings/meta/etc).
      if (m['_reuseFrom'] is Map && (type == 'recipe' || type == 'note')) {
        return m;
      }

      // -----------------------------
      // NOTE
      // -----------------------------
      if (type == 'note') {
        final text = _stringOrNull(m['text']);
        if (text == null) return null;

        return {
          'type': 'note',
          'text': text,
          if (m['_reuseFrom'] is Map)
            '_reuseFrom': Map<String, dynamic>.from(m['_reuseFrom']),
        };
      }

      // -----------------------------
      // RECIPE
      // -----------------------------
      if (type == 'recipe') {
        final rid = recipeIdFromAny(m['recipeId']);
        if (rid == null) return null;

        final source = (m['source'] ?? 'auto').toString();
        final audience = _stringOrNull(m['audience']);
        final childKey = _stringOrNull(m['childKey']);
        final childName = _stringOrNull(m['childName']);

        // ✅ warnings (new + legacy)
        // - warning: Map<String,dynamic> (single warning object)
        // - warnings: List<Map> (many warning objects) OR List<String> (legacy codes)
        final warning = _mapOrNull(m['warning']);
        final warnings = _listOrNull(m['warnings']);

        // ✅ optional warningMeta (legacy support)
        final warningMeta = _mapOrNull(m['warningMeta']);

        // ✅ leftover marker (optional)
        final leftover = (m['leftover'] == true);

        return {
          'type': 'recipe',
          'recipeId': rid,
          'source': source,
          if (audience != null) 'audience': audience,
          if (childKey != null) 'childKey': childKey,
          if (childName != null) 'childName': childName,

          // Keep raw shapes so UI can render message cleanly.
          if (warning != null) 'warning': warning,
          if (warnings != null) 'warnings': warnings,

          if (warningMeta != null) 'warningMeta': warningMeta,

          if (leftover) 'leftover': true,
          if (m['_reuseFrom'] is Map)
            '_reuseFrom': Map<String, dynamic>.from(m['_reuseFrom']),
        };
      }

      // -----------------------------
      // REUSE (raw placeholder)
      // -----------------------------
      if (type == 'reuse') {
        final fromDayKey = _stringOrNull(m['fromDayKey']);
        final fromSlot = _stringOrNull(m['fromSlot']);
        if (fromDayKey == null || fromSlot == null) return null;

        return {
          'type': 'reuse',
          'fromDayKey': fromDayKey,
          'fromSlot': fromSlot,
        };
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
    }

    return null;
  }

  // ------------------------------------
  // READ HELPERS
  // ------------------------------------
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
      e == null ||
      (e['type'] ?? '').toString().trim().isEmpty ||
      (e['type'] ?? '').toString() == 'clear';

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

  static String? audience(Map<String, dynamic>? e) {
    final a = (e?['audience'] ?? '').toString().trim();
    return a.isEmpty ? null : a;
  }

  // ------------------------------------
  // WARNINGS
  // ------------------------------------

  /// Returns a single warning object if present (new shape).
  static Map<String, dynamic>? warning(Map<String, dynamic>? e) {
    final w = e?['warning'];
    if (w is Map) return Map<String, dynamic>.from(w);
    return null;
  }

  /// Returns warning objects list (new shape) if present.
  static List<Map<String, dynamic>> warningObjects(Map<String, dynamic>? e) {
    final w = e?['warnings'];
    if (w is List) {
      final out = <Map<String, dynamic>>[];
      for (final x in w) {
        if (x is Map) out.add(Map<String, dynamic>.from(x));
      }
      return out;
    }
    return const [];
  }

  /// Returns legacy warning codes (List<String>) if warnings are strings.
  static List<String> warningCodes(Map<String, dynamic>? e) {
    final w = e?['warnings'];
    if (w is List) {
      final out = <String>[];
      for (final x in w) {
        if (x is String) {
          final s = x.trim();
          if (s.isNotEmpty) out.add(s);
        } else {
          final s = (x ?? '').toString().trim();
          if (s.isNotEmpty) out.add(s);
        }
      }
      return out;
    }
    if (w is String) {
      final s = w.trim();
      return s.isEmpty ? const [] : <String>[s];
    }
    return const [];
  }

  static Map<String, dynamic>? warningMeta(Map<String, dynamic>? e) {
    final m = e?['warningMeta'];
    if (m is Map) return Map<String, dynamic>.from(m);
    return null;
  }

  /// ✅ UI-friendly warning message.
  ///
  /// Priority:
  /// 1) warning.message (new)
  /// 2) warnings[0].message (new list)
  /// 3) warningMeta.text (legacy)
  /// 4) warningCodes[0] (legacy)
  static String? warningText(Map<String, dynamic>? e) {
    if (e == null) return null;

    // 1) single warning object
    final w = warning(e);
    final wm = (w?['message'] ?? w?['text'] ?? '').toString().trim();
    if (wm.isNotEmpty) return wm;

    // 2) warnings list of objects
    final objs = warningObjects(e);
    if (objs.isNotEmpty) {
      final first = objs.first;
      final m = (first['message'] ?? first['text'] ?? '').toString().trim();
      if (m.isNotEmpty) return m;
    }

    // 3) legacy meta text
    final meta = warningMeta(e);
    final t = meta?['text'];
    if (t is String && t.trim().isNotEmpty) return t.trim();

    // 4) legacy code fallback
    final codes = warningCodes(e);
    if (codes.isEmpty) return null;
    return codes.first.trim();
  }

  // ------------------------------------
  // REUSE META (resolved + raw reuse)
  // ------------------------------------
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

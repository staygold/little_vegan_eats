// lib/meal_plan/widgets/meal_plan_entry_parser.dart
class MealPlanEntryParser {
  static int? recipeIdFromAny(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return int.tryParse('${raw ?? ''}');
  }

  /// Canonical entry:
  /// - {'type': 'recipe', 'recipeId': int}
  /// - {'type': 'note', 'text': String}
  static Map<String, dynamic>? parse(dynamic raw) {
    if (raw is int) return {'type': 'recipe', 'recipeId': raw};
    if (raw is num) return {'type': 'recipe', 'recipeId': raw.toInt()};

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
        return {'type': 'recipe', 'recipeId': rid};
      }
    }

    if (raw is String) {
      final id = int.tryParse(raw.trim());
      if (id != null) return {'type': 'recipe', 'recipeId': id};
    }

    return null;
  }

  static int? entryRecipeId(Map<String, dynamic>? e) {
    if (e == null) return null;
    if (e['type'] != 'recipe') return null;
    return recipeIdFromAny(e['recipeId']);
  }

  static String? entryNoteText(Map<String, dynamic>? e) {
    if (e == null) return null;
    if (e['type'] != 'note') return null;
    final t = (e['text'] ?? '').toString().trim();
    return t.isNotEmpty ? t : null;
  }
}

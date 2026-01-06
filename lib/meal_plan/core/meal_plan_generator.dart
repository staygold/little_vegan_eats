import 'dart:math';
import 'meal_plan_slots.dart';
import '../../recipes/allergy_engine.dart';

class MealPlanGenerator {
  
  static Map<String, Map<String, dynamic>> generate({
    required Map<String, dynamic> config,
    required List<Map<String, dynamic>> allRecipes,
    required List<String> targetDayKeys, 
  }) {
    print("👨‍🍳 GENERATOR: Starting with ${allRecipes.length} recipes for ${targetDayKeys.length} days");

    // 1. Setup Buckets
    final buckets = <String, List<int>>{
      'breakfast': _getCandidatesForSlot('breakfast', allRecipes),
      'lunch': _getCandidatesForSlot('lunch', allRecipes),
      'dinner': _getCandidatesForSlot('dinner', allRecipes),
      'snack1': _getCandidatesForSlot('snack1', allRecipes),
      'snack2': _getCandidatesForSlot('snack2', allRecipes),
    };
    
    // Fallback bucket (All valid recipes)
    final allIds = allRecipes.map((r) => _recipeId(r)).whereType<int>().toList();

    print("👨‍🍳 GENERATOR: Bucket counts - B:${buckets['breakfast']?.length} L:${buckets['lunch']?.length} D:${buckets['dinner']?.length}");

    final usedIds = <int>{};
    final rng = Random();
    final Map<String, Map<String, dynamic>> plan = {};

    // 2. Parse enabled slots
    final slotsRaw = config['slots'] as List? ?? [];
    final enabledSlots = slotsRaw.map((e) => e.toString()).toSet();

    // 3. Fill Days
    for (final dayKey in targetDayKeys) {
      final dayMap = <String, dynamic>{};

      for (final slot in MealPlanSlots.order) {
        // Skip if user didn't select this meal type
        if (enabledSlots.isNotEmpty && !enabledSlots.contains(slot)) continue;

        var candidates = buckets[slot] ?? [];

        // Level 1 Fallback: Swap Lunch/Dinner
        if (candidates.isEmpty) {
           if (slot == 'lunch') candidates = buckets['dinner'] ?? [];
           else if (slot == 'dinner') candidates = buckets['lunch'] ?? [];
           else if (slot == 'snack1') candidates = buckets['snack2'] ?? [];
           else if (slot == 'snack2') candidates = buckets['snack1'] ?? [];
        }

        // Level 2 Fallback: USE ANYTHING (Critical fix)
        if (candidates.isEmpty && allIds.isNotEmpty) {
           print("⚠️ GENERATOR: No strict matches for $slot, using fallback.");
           candidates = allIds;
        }

        final picked = _pickId(rng, candidates, usedIds);
        
        if (picked != null) {
          dayMap[slot] = {
            'type': 'recipe',
            'recipeId': picked,
            'source': 'auto_builder',
          };
          usedIds.add(picked);
        }
      }
      
      if (dayMap.isNotEmpty) {
        plan[dayKey] = dayMap;
      }
    }

    print("👨‍🍳 GENERATOR: Finished. Generated ${plan.length} days.");
    return plan;
  }

  // --- Helpers ---

  static int? _pickId(Random rng, List<int> candidates, Set<int> avoid) {
    if (candidates.isEmpty) return null;
    final fresh = candidates.where((id) => !avoid.contains(id)).toList();
    if (fresh.isNotEmpty) return fresh[rng.nextInt(fresh.length)];
    return candidates[rng.nextInt(candidates.length)];
  }

  static List<int> _getCandidatesForSlot(
    String slot,
    List<Map<String, dynamic>> recipes,
  ) {
    return recipes.where((r) {
      // Add Allergy Checks here if needed
      
      final courseRaw = _extractCourse(r);
      final tokens = _courseTokens(courseRaw);
      if (tokens.isEmpty) return false;

      final norm = slot.toLowerCase();
      if (norm.contains('breakfast')) return _isBreakfast(tokens);
      if (norm.contains('lunch') || norm.contains('dinner')) return _isMains(tokens);
      if (norm.contains('snack')) return _isSnacks(tokens);

      return false;
    }).map((r) => _recipeId(r)).whereType<int>().toList();
  }

  static int? _recipeId(dynamic raw) {
     if (raw is Map) return int.tryParse(raw['id'].toString());
     return int.tryParse(raw.toString());
  }
  
  static String? _extractCourse(Map<String, dynamic> r) {
    final recipe = r['recipe'] ?? r;
    final v = recipe['course'] ?? recipe['meal_type'] ?? recipe['category']; 
    if (v is String) return v;
    if (v is List && v.isNotEmpty) return v.first.toString();
    
    // Look in taxonomies/tags if root is missing
    if (r['tags'] is Map) {
       return r['tags']['course']?.toString();
    }
    return null;
  }

  static List<String> _courseTokens(String? c) => 
      c?.toLowerCase().split(',').map((e)=>e.trim()).toList() ?? [];

  static bool _isBreakfast(List<String> t) => t.any((x) => x.contains('breakfast'));
  static bool _isMains(List<String> t) => t.any((x) => x.contains('main') || x.contains('lunch') || x.contains('dinner') || x.contains('entree'));
  static bool _isSnacks(List<String> t) => t.any((x) => x.contains('snack'));
}
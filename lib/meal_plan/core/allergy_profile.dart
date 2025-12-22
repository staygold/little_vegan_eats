import 'allergy_keys.dart';

class AllergyProfile {
  AllergyProfile._();

  static ({Set<String> excludedAllergens, Set<String> childAllergens}) buildFromUserDoc(
    Map<String, dynamic>? userData,
  ) {
    final excluded = <String>{};
    final child = <String>{};

    if (userData == null) return (excludedAllergens: excluded, childAllergens: child);

    void absorbFromList(dynamic list, {required bool isChild}) {
      if (list is! List) return;

      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);

        final has = m['hasAllergies'];
        final hasAllergies = has is bool ? has : false;
        if (!hasAllergies) continue;

        final rawAllergies = m['allergies'];
        if (rawAllergies is! List) continue;

        for (final a in rawAllergies) {
          final key = a?.toString().trim() ?? '';
          if (key.isEmpty) continue;
          if (!AllergyKeys.isSupported(key)) continue;

          excluded.add(key);
          if (isChild) child.add(key);
        }
      }
    }

    absorbFromList(userData['adults'], isChild: false);
    absorbFromList(userData['children'], isChild: true);

    return (excludedAllergens: excluded, childAllergens: child);
  }
}

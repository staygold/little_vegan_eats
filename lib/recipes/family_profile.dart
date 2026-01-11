// lib/recipes/family_profile.dart
import 'allergy_engine.dart';
import 'profile_person.dart';

class FamilyProfile {
  final List<ProfilePerson> adults;
  final List<ProfilePerson> children;

  const FamilyProfile({
    required this.adults,
    required this.children,
  });

  List<ProfilePerson> get allPeople => [...adults, ...children];

  List<ProfilePerson> activeProfilesFor(AllergiesSelection sel) {
    if (!sel.enabled) return allPeople;

    switch (sel.mode) {
      case SuitabilityMode.wholeFamily:
        return allPeople;
      case SuitabilityMode.allChildren:
        return children;
      case SuitabilityMode.specificPeople:
        // IMPORTANT: ensure personIds is Set<String> or this becomes Object?
        return allPeople.where((p) => sel.personIds.contains(p.id)).toList();
    }
  }

  bool get hasAnyAllergies =>
      allPeople.any((p) => p.hasAllergies && p.allergies.isNotEmpty);
}

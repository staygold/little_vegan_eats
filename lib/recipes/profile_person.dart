// lib/recipes/profile_person.dart

enum PersonType { adult, child }

class ProfilePerson {
  final String id;
  final PersonType type;
  final String name;

  // Allergies
  final bool hasAllergies;
  final List<String> allergies;

  // ✅ DOB (needed for age gating)
  // Prefer dobMonth/dobYear, but allow legacy dob
  final int? dobMonth; // 1-12
  final int? dobYear;  // e.g. 2025
  final DateTime? dob; // legacy exact date if you have it

  const ProfilePerson({
    required this.id,
    required this.type,
    required this.name,
    required this.hasAllergies,
    required this.allergies,
    this.dobMonth,
    this.dobYear,
    this.dob,
  });

  bool get isChild => type == PersonType.child;
}

// lib/recipes/profile_person.dart

enum PersonType { adult, child }

class ProfilePerson {
  final String id;
  final PersonType type;
  final String name;

  final bool hasAllergies;
  final List<String> allergies;

  final int? dobMonth;
  final int? dobYear;
  final DateTime? dob;

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

  // ✅ Backwards compatibility: older code expects `person.key`
  String get key => id;
}

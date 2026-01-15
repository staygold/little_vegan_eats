// lib/recipes/family_profile_repository.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'family_profile.dart';
import 'profile_person.dart';
import 'allergy_engine.dart';
import 'allergy_keys.dart';

class FamilyProfileRepository {
  final FirebaseFirestore _fs;
  final FirebaseAuth _auth;

  FamilyProfileRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _docForUid(String uid) {
    return _fs.collection('users').doc(uid);
  }

  /// ✅ Shared, auth-safe stream:
  /// - emits empty family when signed out
  /// - emits correct family when signed in (cold start included)
  /// - broadcast so multiple listeners share ONE underlying auth/doc subscription (per repo instance)
  late final Stream<FamilyProfile> _sharedFamilyStream =
      _auth.authStateChanges().asyncExpand((user) {
        if (user == null) {
          return Stream.value(const FamilyProfile(adults: [], children: []));
        }
        return _docForUid(user.uid).snapshots().map((snap) {
          final data = snap.data() ?? const <String, dynamic>{};
          return _parseFamily(data);
        });
      }).asBroadcastStream();

  Stream<FamilyProfile> watchFamilyProfile() => _sharedFamilyStream;

  // ------------------------------------------------------------
  // ✅ NEW: Supports BOTH schemas
  // - New: parent: {name, email}
  // - Old: parentName / parentEmail
  // Ensures at least 1 adult exists in the in-memory profile
  // ------------------------------------------------------------
  FamilyProfile _parseFamily(Map<String, dynamic> data) {
    final adultsRaw =
        (data['adults'] is List) ? data['adults'] as List : const [];
    final kidsRaw =
        (data['children'] is List) ? data['children'] as List : const [];

    final adults = adultsRaw
        .whereType<Map>()
        .map((m) => _parsePerson(Map<String, dynamic>.from(m), forceChild: false))
        .toList();

    final children = kidsRaw
        .whereType<Map>()
        .map((m) => _parsePerson(Map<String, dynamic>.from(m), forceChild: true))
        .toList();

    // ✅ If adults missing, synthesize an Adult 1 from parent.name
    if (adults.isEmpty) {
      final parentName = _readParentName(data);
      if (parentName.isNotEmpty) {
        adults.add(ProfilePerson(
          id: 'adult_1',
          type: PersonType.adult,
          name: parentName,
          hasAllergies: false,
          allergies: const <String>[],
          dobMonth: null,
          dobYear: null,
          dob: null,
        ));
      }
    }

    return FamilyProfile(adults: adults, children: children);
  }

  String _readParentName(Map<String, dynamic> data) {
    // new: parent.name
    final parent = data['parent'];
    if (parent is Map && parent['name'] is String) {
      final n = (parent['name'] as String).trim();
      if (n.isNotEmpty) return n;
    }

    // legacy: parentName
    if (data['parentName'] is String) {
      final n = (data['parentName'] as String).trim();
      if (n.isNotEmpty) return n;
    }

    return '';
  }

  ProfilePerson _parsePerson(
    Map<String, dynamic> m, {
    required bool forceChild,
  }) {
    // -----------------------------
    // TYPE
    // -----------------------------
    final type = forceChild ? PersonType.child : PersonType.adult;

    // -----------------------------
    // ID (robust)
    // -----------------------------
    final id = (m['id'] ?? m['childKey'] ?? m['adultKey'] ?? '').toString();

    // -----------------------------
    // DOB (robust)
    // -----------------------------
    int? dobMonth = m['dobMonth'] is int ? m['dobMonth'] as int : null;
    int? dobYear = m['dobYear'] is int ? m['dobYear'] as int : null;

    DateTime? dob;

    // Firestore Timestamp
    if (m['dob'] is Timestamp) {
      dob = (m['dob'] as Timestamp).toDate();
    }

    // String date fallback: "YYYY-MM-DD" (or ISO)
    if (dob == null && m['dob'] is String) {
      final s = (m['dob'] as String).trim();
      final parsed = DateTime.tryParse(s);
      if (parsed != null) dob = parsed;
    }

    // Month/year as strings fallback
    if (dobMonth == null && m['dobMonth'] is String) {
      dobMonth = int.tryParse((m['dobMonth'] as String).trim());
    }
    if (dobYear == null && m['dobYear'] is String) {
      dobYear = int.tryParse((m['dobYear'] as String).trim());
    }

    // If we have month/year but no DateTime, synthesize a dob (mid-month)
    if (dob == null && dobYear != null && dobMonth != null) {
      dob = DateTime(dobYear, dobMonth, 15);
    }

    // -----------------------------
    // ALLERGIES (support multiple shapes)
    // -----------------------------
    final allergyItems = _extractAllergyItems(m);

    // hasAllergies can be stored in multiple places, but should also be derived
    final hasAllergiesStored = (m['hasAllergies'] as bool?) ??
        ((m['allergies'] is Map)
            ? ((m['allergies'] as Map)['hasAllergies'] as bool?)
            : null) ??
        ((m['dietary'] is Map)
            ? ((m['dietary'] as Map)['hasAllergies'] as bool?)
            : null);

    final hasAllergies = (hasAllergiesStored == true) || allergyItems.isNotEmpty;

    return ProfilePerson(
      id: id,
      type: type,
      name: (m['name'] as String?) ?? '',
      hasAllergies: hasAllergies,
      allergies: allergyItems,
      dobMonth: dobMonth,
      dobYear: dobYear,
      dob: dob,
    );
  }

  /// ✅ Reads allergies from any of these:
  /// - hasAllergies + allergies: ["soy","nuts"]
  /// - allergies: { items: ["soy"] }
  /// - allergies: { items: [{key:"soy"}] } / maps / mixed
  /// - allergyKeys / allergy_keys
  /// - dietary: { allergies: [...] }
  /// And normalises via AllergyKeys.normalize(...)
  List<String> _extractAllergyItems(Map<String, dynamic> m) {
    dynamic raw;

    // 1) common alternate keys
    raw = m['allergy_keys'] ??
        m['allergyKeys'] ??
        m['allergies'] ??
        m['allergens'];

    // 2) nested dietary fallback
    if (raw == null && m['dietary'] is Map) {
      final d = Map<String, dynamic>.from(m['dietary'] as Map);
      raw = d['allergies'] ??
          d['allergy_keys'] ??
          d['allergyKeys'] ??
          d['allergens'];
    }

    // 3) if allergies is a Map, try items inside it
    if (raw is Map) {
      final block = Map<String, dynamic>.from(raw);
      raw = block['items'] ?? block['allergies'] ?? block['keys'];
    }

    final out = <String>[];

    void addOne(dynamic v) {
      if (v == null) return;

      // map shapes: {key: "soy"} / {id: "soy"} / {name:"Soy"} etc
      if (v is Map) {
        final mm = Map<String, dynamic>.from(v);
        final candidate =
            mm['key'] ?? mm['id'] ?? mm['slug'] ?? mm['name'] ?? mm['value'];
        final k = AllergyKeys.normalize(candidate?.toString() ?? '');
        if (k != null && k.trim().isNotEmpty) out.add(k);
        return;
      }

      // string / number
      final k = AllergyKeys.normalize(v.toString());
      if (k != null && k.trim().isNotEmpty) out.add(k);
    }

    if (raw is List) {
      for (final e in raw) {
        addOne(e);
      }
    } else if (raw is String) {
      // comma-separated fallback
      for (final part in raw.split(',')) {
        addOne(part.trim());
      }
    } else {
      addOne(raw);
    }

    return out.toSet().toList()..sort();
  }

  // Kept (not used in Home/Profile right now, but used elsewhere in your app)
  AllergiesSelection _parseSelection(Map<String, dynamic> data) {
    final raw =
        (data['allergiesSelection'] as Map?)?.cast<String, dynamic>() ??
            const {};

    final mode = SuitabilityMode.values.firstWhere(
      (m) => m.name == (raw['mode'] ?? 'wholeFamily'),
      orElse: () => SuitabilityMode.wholeFamily,
    );

    final ids =
        (raw['personIds'] as List?)?.map((e) => e.toString()).toSet() ??
            <String>{};

    return AllergiesSelection(
      enabled: raw['enabled'] == true,
      mode: mode,
      personIds: ids,
    );
  }
}

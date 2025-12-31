// lib/recipes/favorites_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FavoritesService {
  // ------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------

  static CollectionReference<Map<String, dynamic>>? _col() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .collection('favorites');
  }

  static DocumentReference<Map<String, dynamic>>? _doc(int recipeId) {
    final col = _col();
    if (col == null) return null;
    // ✅ Stable document ID = recipeId → prevents duplicates forever
    return col.doc(recipeId.toString());
  }

  // ------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------

  /// ✅ Source of truth: does the doc with id=recipeId exist?
  static Stream<bool> watchIsFavorite(int recipeId) {
    final ref = _doc(recipeId);
    if (ref == null) return Stream.value(false);
    return ref.snapshots().map((d) => d.exists);
  }

  /// ✅ Toggle favourite using stable doc id.
  /// Returns the new state (true = favorited).
  static Future<bool> toggleFavorite({
    required int recipeId,
    String? title,
    String? imageUrl,
  }) async {
    final ref = _doc(recipeId);
    if (ref == null) return false;

    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return false;
    }

    await ref.set(
      {
        'recipeId': recipeId, // keep for legacy readers
        if (title != null) 'title': title,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return true;
  }

  /// ✅ One-time cleanup:
  /// - Deduplicates any old favourites
  /// - Migrates everything to stable doc id = recipeId
  static Future<void> dedupeAndMigrate() async {
    final col = _col();
    if (col == null) return;

    final snap = await col.get();

    int parseRecipeId(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final data = d.data();
      final raw = data['recipeId'];
      final fromField = (raw is int) ? raw : int.tryParse('$raw');
      if (fromField != null && fromField > 0) return fromField;

      // fallback: maybe doc id already equals recipeId
      return int.tryParse(d.id) ?? -1;
    }

    final Map<int, List<QueryDocumentSnapshot<Map<String, dynamic>>>> buckets = {};

    for (final d in snap.docs) {
      final rid = parseRecipeId(d);
      if (rid <= 0) continue;
      buckets.putIfAbsent(rid, () => []).add(d);
    }

    final batch = FirebaseFirestore.instance.batch();

    for (final entry in buckets.entries) {
      final rid = entry.key;
      final docs = entry.value;

      // Ensure stable doc exists
      final stableRef = col.doc(rid.toString());
      batch.set(
        stableRef,
        {
          'recipeId': rid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Delete all non-stable duplicates
      for (final d in docs) {
        if (d.id == rid.toString()) continue;
        batch.delete(d.reference);
      }
    }

    await batch.commit();
  }

  /// 🧨 HARD RESET:
  /// Deletes ALL favourites for the current user.
  /// Safe for large collections (batched).
  static Future<void> clearAllFavorites() async {
    final col = _col();
    if (col == null) return;

    final snap = await col.get();
    if (snap.docs.isEmpty) return;

    const chunkSize = 450; // Firestore batch safety
    final docs = snap.docs;

    for (var i = 0; i < docs.length; i += chunkSize) {
      final batch = FirebaseFirestore.instance.batch();
      final end = (i + chunkSize < docs.length) ? i + chunkSize : docs.length;

      for (var j = i; j < end; j++) {
        batch.delete(docs[j].reference);
      }

      await batch.commit();
    }
  }
}

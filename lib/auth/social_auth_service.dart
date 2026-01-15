// lib/auth/social_auth_service.dart
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class SocialAuthService {
  SocialAuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    GoogleSignIn? google,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _google = google ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final GoogleSignIn _google;

  /// Ensure the Firestore user doc exists in a unified schema.
  ///
  /// - parent.name prefers the typed pendingName if provided
  /// - parent.email uses provider/user email if available
  /// - auth.provider stores provider id ('google.com', 'apple.com', 'password', etc.)
  /// - onboarded/profileComplete are merge-safe defaults
  Future<void> ensureUserDoc({
    required User user,
    String? name,
    String? email,
    required String providerId,
  }) async {
    final ref = _db.collection('users').doc(user.uid);

    final parentName = (name ?? '').trim();
    final parentEmail = (email ?? '').trim();

    final data = <String, dynamic>{
      "auth": {
        "provider": providerId,
        "emailVerified": user.emailVerified,
      },
      "updatedAt": FieldValue.serverTimestamp(),
      "createdAt": FieldValue.serverTimestamp(),
      // defaults (won't break if doc already exists)
      "onboarded": false,
      "profileComplete": false,
    };

    // Only set parent fields if we actually have values.
    final parent = <String, dynamic>{};
    if (parentName.isNotEmpty) parent["name"] = parentName;
    if (parentEmail.isNotEmpty) parent["email"] = parentEmail;
    if (parent.isNotEmpty) data["parent"] = parent;

    await ref.set(data, SetOptions(merge: true));
  }

  // ---------------- GOOGLE ----------------
  Future<UserCredential?> signInWithGoogle({String? pendingName}) async {
    final googleUser = await _google.signIn();
    if (googleUser == null) return null; // cancelled

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCred = await _auth.signInWithCredential(credential);
    final user = userCred.user;
    if (user == null) return null;

    await ensureUserDoc(
      user: user,
      name: (pendingName ?? user.displayName),
      email: user.email,
      providerId: 'google.com',
    );

    return userCred;
  }

  // ---------------- APPLE ----------------
  Future<UserCredential?> signInWithApple({String? pendingName}) async {
    final rawNonce = _generateNonce();
    final nonce = _sha256(rawNonce);

    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauth = OAuthProvider("apple.com").credential(
      idToken: apple.identityToken,
      rawNonce: rawNonce,
    );

    final userCred = await _auth.signInWithCredential(oauth);
    final user = userCred.user;
    if (user == null) return null;

    // Apple only returns these *once*.
    final given = (apple.givenName ?? '').trim();
    final family = (apple.familyName ?? '').trim();
    final fullName =
        ([given, family]..removeWhere((s) => s.isEmpty)).join(' ').trim();
    final appleEmail = (apple.email ?? '').trim();

    // Prefer the name typed in your pre-auth flow, else fall back to Apple fullName.
    final chosenName = (pendingName ?? fullName).trim();

    // Optionally set displayName on first sign in.
    if (fullName.isNotEmpty && (user.displayName ?? '').isEmpty) {
      try {
        await user.updateDisplayName(fullName);
      } catch (_) {}
    }

    await ensureUserDoc(
      user: user,
      name: chosenName.isNotEmpty ? chosenName : (user.displayName ?? fullName),
      // email may be null on subsequent logins
      email: appleEmail.isNotEmpty ? appleEmail : user.email,
      providerId: 'apple.com',
    );

    return userCred;
  }

  // -------- Helpers --------
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rand = Random.secure();
    return List.generate(length, (_) => charset[rand.nextInt(charset.length)])
        .join();
  }

  String _sha256(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

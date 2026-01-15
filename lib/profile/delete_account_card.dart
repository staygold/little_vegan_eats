// lib/profile/delete_account_card.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DeleteAccountCard extends StatefulWidget {
  const DeleteAccountCard({super.key});

  @override
  State<DeleteAccountCard> createState() => _DeleteAccountCardState();
}

class _DeleteAccountCardState extends State<DeleteAccountCard> {
  bool _loading = false;
  String? _error;

  Future<void> _startDeleteFlow() async {
    setState(() => _error = null);

    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    if (user == null || email.isEmpty) {
      setState(() => _error = 'You must be signed in with an email account.');
      return;
    }

    final pw = await _askForPassword(context, email);
    if (pw == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) Re-auth
      final cred = EmailAuthProvider.credential(email: email, password: pw);
      await user
          .reauthenticateWithCredential(cred)
          .timeout(const Duration(seconds: 15));

      // 2) Delete Firestore user data (client-side: known paths)
      await _deleteUserData(user.uid).timeout(const Duration(seconds: 60));

      // 3) Delete Auth user
      await user.delete().timeout(const Duration(seconds: 15));

      if (!mounted) return;

      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted')),
      );
    } on TimeoutException {
      setState(() {
        _error = 'Timed out deleting your account. Please try again.';
        _loading = false;
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = _friendlyAuthError(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password.';
      case 'requires-recent-login':
        return 'For security, please sign in again and try deleting your account.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return e.message ?? e.code;
    }
  }

  // ---------------------------------------------------------------------------
  // Client-side deletion (NO billing)
  //
  // Deletes everything you currently store under users/{uid} based on your
  // Firestore structure:
  // - favorites
  // - firstFoods
  // - mealPlan
  // - mealPrograms
  // - shoppingLists
  //
  // If you add new subcollections later, add another line here.
  // ---------------------------------------------------------------------------
  Future<void> _deleteUserData(String uid) async {
    final db = FirebaseFirestore.instance;
    final userDoc = db.collection('users').doc(uid);

    // Delete known subcollections (from your screenshot)
    await _deleteAllDocsInCollection(userDoc.collection('favorites'));
    await _deleteAllDocsInCollection(userDoc.collection('firstFoods'));
    await _deleteAllDocsInCollection(userDoc.collection('mealPlan'));
    await _deleteAllDocsInCollection(userDoc.collection('mealPrograms'));
    await _deleteAllDocsInCollection(userDoc.collection('shoppingLists'));

    // Finally delete the user document
    await userDoc.delete();
  }

  Future<void> _deleteAllDocsInCollection(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    // Batch delete in chunks (works well for small-medium sizes)
    while (true) {
      final snap = await col.limit(200).get();
      if (snap.docs.isEmpty) break;

      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Delete account',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'This permanently deletes your account and your saved data.',
              style: TextStyle(color: Colors.black.withOpacity(0.7)),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _loading ? null : _startDeleteFlow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade200, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'DELETE ACCOUNT',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _askForPassword(BuildContext context, String email) async {
  final ctrl = TextEditingController();
  bool show = false;

  return showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Confirm deletion'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter your password to delete this account:\n$email',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  obscureText: !show,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => show = !show),
                      icon: Icon(show ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This cannot be undone.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
    },
  );
}

// lib/profile/account_details_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../theme/app_theme.dart';

class AccountDetailsScreen extends StatelessWidget {
  const AccountDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        title: const Text('Account'),
        backgroundColor: AppColors.brandDark,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _EmailCard(email: (user?.email ?? '').trim()),
          const SizedBox(height: 12),
          const ChangePasswordCard(),
          const SizedBox(height: 12),
          const DeleteAccountCard(),

          // ✅ SHOW CRASH TEST CARD (debug only)
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            const _CrashlyticsTestCard(),
          ],
        ],
      ),
    );
  }
}

class _EmailCard extends StatelessWidget {
  final String email;
  const _EmailCard({required this.email});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.mail_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                email.isEmpty ? 'No email on file' : email,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Route A: current pw -> new pw -> confirm.
class ChangePasswordCard extends StatefulWidget {
  const ChangePasswordCard({super.key});

  @override
  State<ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends State<ChangePasswordCard> {
  final _formKey = GlobalKey<FormState>();

  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validateNewPassword(String? v) {
    final s = (v ?? '');
    if (s.isEmpty) return 'Enter a new password';
    if (s.length < 8) return 'Use at least 8 characters';
    if (s.trim() != s) return 'Password cannot start or end with spaces';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      if (!_formKey.currentState!.validate()) {
        setState(() => _loading = false);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      final email = (user?.email ?? '').trim();
      if (user == null || email.isEmpty) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'You must be signed in with an email account to change password.',
        );
      }

      final currentPw = _currentCtrl.text;
      final newPw = _newCtrl.text;

      if (newPw == currentPw) {
        setState(() {
          _error = 'New password must be different to your current password.';
          _loading = false;
        });
        return;
      }

      final cred = EmailAuthProvider.credential(email: email, password: currentPw);

      try {
        await user.reauthenticateWithCredential(cred).timeout(const Duration(seconds: 15));
      } on FirebaseAuthException catch (e) {
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          setState(() {
            _error = 'Current password is incorrect.';
            _loading = false;
          });
          return;
        }
        rethrow;
      }

      await user.updatePassword(newPw).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      _currentCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated')),
      );

      setState(() => _loading = false);
    } on TimeoutException {
      setState(() {
        _error = 'Timed out talking to Firebase. Check your connection and try again.';
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
      case 'requires-recent-login':
        return 'For security, please sign in again, then try changing your password.';
      case 'weak-password':
        return 'That password is too weak. Use at least 8 characters.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return e.message ?? e.code;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Change password', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _currentCtrl,
                obscureText: !_showCurrent,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showCurrent = !_showCurrent),
                    icon: Icon(_showCurrent ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newCtrl,
                obscureText: !_showNew,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showNew = !_showNew),
                    icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
                validator: _validateNewPassword,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showConfirm = !_showConfirm),
                    icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
                validator: (v) {
                  if ((v ?? '').isEmpty) return 'Confirm your new password';
                  if (v != _newCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 10),
              ],
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('UPDATE PASSWORD', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      final cred = EmailAuthProvider.credential(email: email, password: pw);
      await user.reauthenticateWithCredential(cred).timeout(const Duration(seconds: 15));

      await _deleteUserData(user.uid).timeout(const Duration(seconds: 45));

      await user.delete().timeout(const Duration(seconds: 15));

      if (!mounted) return;

      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deleted')));
    } on TimeoutException {
      setState(() {
        _error = 'Timed out deleting your account. Please try again.';
        _loading = false;
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = _friendlyDeleteError(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _friendlyDeleteError(FirebaseAuthException e) {
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

  Future<void> _deleteUserData(String uid) async {
    final db = FirebaseFirestore.instance;
    final userDoc = db.collection('users').doc(uid);

    await _deleteAllDocsInCollection(userDoc.collection('firstFoods'));

    await userDoc.delete();
  }

  Future<void> _deleteAllDocsInCollection(CollectionReference<Map<String, dynamic>> col) async {
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
            const Text('Delete account', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            Text('This permanently deletes your account and your saved data.',
                style: TextStyle(color: Colors.black.withOpacity(0.7))),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('DELETE ACCOUNT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrashlyticsTestCard extends StatelessWidget {
  const _CrashlyticsTestCard();

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
              'Crashlytics test',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Non-fatal logs an error. Hard crash terminates the app (iOS/Android).',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),

            // NON-FATAL
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () async {
                  // This should NOT crash the app. It just reports an error.
                  await FirebaseCrashlytics.instance.recordError(
                    StateError('Crashlytics test non-fatal error'),
                    StackTrace.current,
                    reason: 'User initiated non-fatal test',
                    fatal: false,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logged non-fatal to Crashlytics')),
                    );
                  }
                },
                child: const Text(
                  'LOG NON-FATAL',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // HARD CRASH
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () {
                  // IMPORTANT:
                  // - no async/await
                  // - no try/catch
                  // - do not throw a Dart exception here
                  FirebaseCrashlytics.instance.crash();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade200, width: 2),
                ),
                child: const Text(
                  'HARD CRASH (TERMINATE)',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6),
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
                Text('Enter your password to delete this account:\n$email', style: const TextStyle(fontSize: 14)),
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
                const Text('This cannot be undone.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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

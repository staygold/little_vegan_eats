// lib/auth/social/social_sign_in_buttons.dart
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pending_signup.dart';
import '../social_auth_service.dart';

class SocialSignInButtons extends StatefulWidget {
  const SocialSignInButtons({super.key});

  @override
  State<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends State<SocialSignInButtons> {
  final _svc = SocialAuthService();

  bool _loading = false;
  String? _error;

  // ✅ Keep "user cancelled" completely silent (no red error, no snackbar)
  bool _isUserCancelledAuth(Object e) {
    final msg = e.toString().toLowerCase();

    // Apple Sign In common
    if (msg.contains('authorizationerrorcode.canceled')) return true;
    if (msg.contains('canceled') || msg.contains('cancelled')) return true;
    if (msg.contains('user canceled') || msg.contains('user cancelled')) return true;

    // Your reported "1001" showing up after closing the Apple sheet
    if (msg.contains('1001')) return true;

    // Other cancellation-ish strings that show up depending on platform/version
    if (msg.contains('aborted') || msg.contains('sign-in was aborted')) return true;
    if (msg.contains('popup_closed_by_user')) return true; // web
    if (msg.contains('web-context-canceled')) return true;

    // Firebase can sometimes throw "ERROR_ABORTED_BY_USER" style messages
    if (msg.contains('aborted_by_user')) return true;

    return false;
  }

  Future<void> _run(Future<UserCredential?> Function() fn) async {
    if (_loading) return;

    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      final cred = await fn();

      if (cred != null) {
        // ✅ once signed in, we no longer need the pending name in memory
        PendingSignup.clear();
      }

      // No navigation required: AuthGate will rebuild via authStateChanges.
    } on FirebaseAuthException catch (e) {
      // ✅ silent cancel
      if (_isUserCancelledAuth(e)) return;
      if (!mounted) return;
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      // ✅ silent cancel
      if (_isUserCancelledAuth(e)) return;
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingName = (PendingSignup.name ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],

        if (!Platform.isAndroid) ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _loading
                  ? null
                  : () => _run(
                        () => _svc.signInWithApple(pendingName: pendingName),
                      ),
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue with Apple'),
            ),
          ),
          const SizedBox(height: 10),
        ],

        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: _loading
                ? null
                : () => _run(
                      () => _svc.signInWithGoogle(pendingName: pendingName),
                    ),
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue with Google'),
          ),
        ),
      ],
    );
  }
}

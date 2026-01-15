// lib/auth/email_password_signup_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';
import 'pending_signup.dart';
import 'sign_in_screen.dart';

class EmailPasswordSignupScreen extends StatefulWidget {
  const EmailPasswordSignupScreen({
    super.key,
    this.initialEmail,
  });

  final String? initialEmail;

  @override
  State<EmailPasswordSignupScreen> createState() =>
      _EmailPasswordSignupScreenState();
}

class _EmailPasswordSignupScreenState extends State<EmailPasswordSignupScreen> {
  static const int _minLen = 8;

  late final TextEditingController _emailCtrl;
  late final TextEditingController _pwCtrl;

  bool _loading = false;
  bool _showPw = false;

  String? _emailError;
  String? _pwError;
  String? _generalError;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
    _pwCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  String _emailTrim() => _emailCtrl.text.trim();
  String _pwRaw() => _pwCtrl.text;

  bool _looksLikeEmail(String v) => v.contains('@') && v.contains('.');

  String? _validateEmail(String v) {
    final s = v.trim();
    if (s.isEmpty) return 'Enter your email';
    if (!_looksLikeEmail(s)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePw(String v) {
    final s = v.trim();
    if (s.isEmpty) return 'Enter a password';
    if (s.length < _minLen) return 'Use at least $_minLen characters';
    return null;
  }

  Future<void> _goToSignIn() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final email = _emailTrim();
    final pw = _pwRaw();

    final eErr = _validateEmail(email);
    final pErr = _validatePw(pw);

    setState(() {
      _emailError = eErr;
      _pwError = pErr;
      _generalError = null;
    });

    if (eErr != null || pErr != null) return;

    setState(() => _loading = true);

    try {
      // ✅ Create the auth user (this is the authoritative "already in use" check)
      await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pw)
          .timeout(const Duration(seconds: 15));

      // ✅ Soft verification email (non-blocking)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        try {
          await user.sendEmailVerification().timeout(const Duration(seconds: 10));
        } catch (_) {}
      }

      // ✅ Write Firestore user doc (unified)
      if (_saving) return;
      _saving = true;

      await _ensureEmailUserDoc(email: email);

      PendingSignup.clear();

      if (!mounted) return;

      // AuthGate will take over; unwind.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      // Map errors to the right field for a clean UX
      if (e.code == 'email-already-in-use') {
        setState(() {
          _emailError = 'An account already exists for that email.';
        });
      } else if (e.code == 'invalid-email') {
        setState(() {
          _emailError = 'That email address doesn’t look right.';
        });
      } else if (e.code == 'weak-password') {
        setState(() {
          _pwError = 'Use at least $_minLen characters.';
        });
      } else {
        setState(() {
          _generalError = e.message ?? e.code;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _generalError = 'Timed out. Check your connection and try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generalError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureEmailUserDoc({required String email}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No authenticated user after signup.');
    }

    final uid = user.uid;
    final name = (PendingSignup.name ?? '').trim();
    final e = email.trim();

    final data = <String, dynamic>{
      "parent": {
        if (name.isNotEmpty) "name": name,
        if (e.isNotEmpty) "email": e,
      },
      "auth": {
        "provider": "password",
        "emailVerified": user.emailVerified,
      },
      "onboarded": false,
      "profileComplete": false,
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set(data, SetOptions(merge: true))
        .timeout(const Duration(seconds: 12));
  }

  @override
  Widget build(BuildContext context) {
    final emailInUse =
        (_emailError ?? '').toLowerCase().contains('already exists');

    final meetsLen = _pwCtrl.text.trim().length >= _minLen;

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      body: Column(
        children: [
          SubHeaderBar(
            title: 'Create account',
            onBack: _loading ? null : () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Friendly header
                      Builder(builder: (context) {
                        final name = (PendingSignup.name ?? '').trim();
                        final hi = name.isEmpty ? 'Hi!' : 'Hi $name!';
                        return Text(
                          hi,
                          style: Theme.of(context).textTheme.headlineSmall,
                        );
                      }),

                      const SizedBox(height: 16),

                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        enabled: !_loading,
                        onChanged: (_) {
                          if (_emailError != null || _generalError != null) {
                            setState(() {
                              _emailError = null;
                              _generalError = null;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Email',
                          errorText: _emailError,
                        ),
                      ),

                      if (emailInUse) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _loading ? null : _goToSignIn,
                            child: const Text('Already have an account? Sign in'),
                          ),
                        ),
                      ] else
                        const SizedBox(height: 12),

                      TextField(
                        controller: _pwCtrl,
                        obscureText: !_showPw,
                        textInputAction: TextInputAction.done,
                        enabled: !_loading,
                        onSubmitted: (_) => _loading ? null : _submit(),
                        onChanged: (_) {
                          if (_pwError != null || _generalError != null) {
                            setState(() {
                              _pwError = null;
                              _generalError = null;
                            });
                          } else {
                            setState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Password',
                          errorText: _pwError,
                          helperText: 'Use $_minLen+ characters.',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPw ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: _loading
                                ? null
                                : () => setState(() => _showPw = !_showPw),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            meetsLen
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: meetsLen ? Colors.green : Colors.black45,
                          ),
                          const SizedBox(width: 8),
                          Text('$_minLen+ characters'),
                        ],
                      ),

                      if (_generalError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _generalError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'CREATE ACCOUNT',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

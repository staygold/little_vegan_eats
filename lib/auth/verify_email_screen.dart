import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.onVerified,
    this.onVerifyLater,
    this.showVerifyLater = true,
    this.title = 'Verify email',
  });

  /// Called when user is confirmed verified (after reload).
  final VoidCallback? onVerified;

  /// Called when "Verify later" is tapped.
  final VoidCallback? onVerifyLater;

  final bool showVerifyLater;
  final String title;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _sending = false;
  bool _checking = false;
  String? _error;

  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    // Only attempt auto-send once, and don't block if it fails.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendVerificationEmail(auto: true));
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  User? get _user => FirebaseAuth.instance.currentUser;

  String get _email => (_user?.email ?? '').trim();

  void _startCooldown([int seconds = 30]) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = seconds);

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldownSeconds <= 1) {
        t.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds -= 1);
      }
    });
  }

  Future<void> _sendVerificationEmail({bool auto = false}) async {
    final user = _user;
    if (user == null) return;

    // Don't spam. If user taps repeatedly, enforce cooldown.
    if (!auto && _cooldownSeconds > 0) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await user.sendEmailVerification().timeout(const Duration(seconds: 15));
      if (!mounted) return;

      // Cooldown only after a manual tap (so auto-send doesn't "punish" the user).
      if (!auto) _startCooldown(30);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent')),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = 'Timed out sending email. Check your connection and try again.');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      // This matches what you're seeing: "blocked due to unusual activity".
      // Firebase often surfaces it as too-many-requests / operation-not-allowed / internal.
      final msg = _friendlyVerifyError(e);
      setState(() => _error = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _friendlyVerifyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Email verification is not enabled for this project.';
      default:
        // Some platforms return generic codes but a clear message.
        return e.message ?? e.code;
    }
  }

  Future<void> _checkVerified() async {
    final user = _user;
    if (user == null) return;

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      await user.reload().timeout(const Duration(seconds: 15));
      final refreshed = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      final isVerified = refreshed?.emailVerified ?? false;

      if (isVerified) {
        widget.onVerified?.call();

        // If no callback provided, just pop this screen.
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not verified yet. Tap the link in your email, then try again.')),
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = 'Timed out checking status. Try again.');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = !_sending && _cooldownSeconds == 0;

    return Scaffold(
      backgroundColor: const Color(0xFFEAF3F1),
      body: Column(
        children: [
          SubHeaderBar(
            title: widget.title,
            onBack: () => Navigator.of(context).pop(),
            backgroundColor: const Color(0xFFEAF3F1),
          ),

          // ✅ This is the key: Center + scroll prevents weird spacing on tall screens.
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),

                      Text(
                        'Almost done',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 10),

                      Text(
                        _email.isEmpty
                            ? 'We sent a verification link to your email.'
                            : 'We sent a verification link to:\n$_email',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),

                      const SizedBox(height: 18),

                      if (_error != null) ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else
                        const SizedBox(height: 8),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: (_checking || _sending) ? null : _checkVerified,
                          child: (_checking)
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  "I'VE VERIFIED",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: canResend ? () => _sendVerificationEmail(auto: false) : null,
                          child: _sending
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  _cooldownSeconds > 0
                                      ? 'Resend email ($_cooldownSeconds)'
                                      : 'Resend email',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ),
                      ),

                      if (widget.showVerifyLater) ...[
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: () {
                            if (widget.onVerifyLater != null) {
                              widget.onVerifyLater!.call();
                              return;
                            }
                            Navigator.of(context).pop(false);
                          },
                          child: const Text(
                            'Verify later',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
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

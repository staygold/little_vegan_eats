// lib/onboarding/kids_onboarding_flow.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'steps/step_child_name.dart';
import 'steps/step_child_dob.dart';
import 'steps/step_child_allergies_yes_no.dart';
import 'steps/step_child_allergies.dart';
import 'steps/step_another_child.dart';
import 'steps/onboarding_complete_screen.dart';

import '../recipes/allergy_keys.dart';
import '../auth/pending_signup.dart';

enum KidsOnboardingStep {
  childName,
  childDob,
  childHasAllergies,
  childAllergies,
  anotherChild,
  complete,
}

class KidsOnboardingFlow extends StatefulWidget {
  const KidsOnboardingFlow({super.key});

  @override
  State<KidsOnboardingFlow> createState() => _KidsOnboardingFlowState();
}

class _KidsOnboardingFlowState extends State<KidsOnboardingFlow> {
  KidsOnboardingStep step = KidsOnboardingStep.childName;

  // Child info (post-auth)
  final List<Map<String, dynamic>> children = [];
  Map<String, dynamic> currentChild = {};

  bool _bootstrapped = false;
  bool _bootstrapFailed = false;

  void next(KidsOnboardingStep s) => setState(() => step = s);

  DocumentReference<Map<String, dynamic>> get _userRef {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('No authenticated user.');
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  @override
  void initState() {
    super.initState();
    // Ensure a unified user doc exists and includes parent name/email if available.
    unawaited(_ensureUserDoc());
  }

  @override
  Widget build(BuildContext context) {
    // If the bootstrap failed, show a minimal retry UI.
    if (_bootstrapFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Setup')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'We couldn’t finish setting up your account.\nPlease try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => unawaited(_retryBootstrap()),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Optional: while initial bootstrap runs, show a spinner for a moment.
    if (!_bootstrapped) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    switch (step) {
      case KidsOnboardingStep.childName:
        return StepChildName(
          onNext: (name) {
            currentChild = {"name": name.trim()};
            next(KidsOnboardingStep.childDob);
          },
          // Back from first child screen = "skip onboarding"
          onBack: _skipOnboardingPostAuth,
          onSkip: _skipOnboardingPostAuth,
        );

      case KidsOnboardingStep.childDob:
        return StepChildDob(
          childName: (currentChild["name"] ?? "").toString(),
          onBack: () => next(KidsOnboardingStep.childName),
          onNext: (month, year) {
            currentChild["dobMonth"] = month; // int 1-12
            currentChild["dobYear"] = year; // int yyyy
            currentChild.remove("dob"); // remove legacy field if present
            next(KidsOnboardingStep.childHasAllergies);
          },
          initialMonth:
              currentChild["dobMonth"] is int ? currentChild["dobMonth"] as int : null,
          initialYear:
              currentChild["dobYear"] is int ? currentChild["dobYear"] as int : null,
        );

      case KidsOnboardingStep.childHasAllergies:
        return StepChildAllergiesYesNo(
          childName: (currentChild["name"] ?? "").toString(),
          onYes: () => next(KidsOnboardingStep.childAllergies),
          onNo: () {
            currentChild["hasAllergies"] = false;
            currentChild["allergies"] = <String>[]; // canonical keys
            _commitChild();
            next(KidsOnboardingStep.anotherChild);
          },
        );

      case KidsOnboardingStep.childAllergies:
        return StepChildAllergies(
          childName: (currentChild["name"] ?? "").toString(),
          onConfirm: (list) {
            final canonical = list
                .map((a) => AllergyKeys.normalize(a))
                .whereType<String>()
                .toSet()
                .toList()
              ..sort();

            currentChild["hasAllergies"] = canonical.isNotEmpty;
            currentChild["allergies"] = canonical;

            _commitChild();
            next(KidsOnboardingStep.anotherChild);
          },
        );

      case KidsOnboardingStep.anotherChild:
        return StepAnotherChild(
          lastChildName:
              children.isEmpty ? "" : (children.last["name"] ?? "").toString(),
          onYes: () => next(KidsOnboardingStep.childName),
          onNo: () => next(KidsOnboardingStep.complete),
        );

      case KidsOnboardingStep.complete:
        return OnboardingCompleteScreen(
          childrenNames: children.map((c) => (c['name'] ?? '').toString()).toList(),
          onFinish: _finishOnboarding,
        );
    }
  }

  // --- bootstrap ---

  Future<void> _retryBootstrap() async {
    setState(() {
      _bootstrapFailed = false;
      _bootstrapped = false;
    });
    await _ensureUserDoc();
  }

  Future<void> _ensureUserDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final pendingName = (PendingSignup.name ?? '').trim();
    final email = (user.email ?? '').trim();

    // Try to infer provider id (google.com / apple.com / password etc.)
    String? providerId;
    if (user.providerData.isNotEmpty) {
      providerId = user.providerData.first.providerId;
    }

    // Build a merge-safe update:
    // - only sets parent.name if we have a pending name
    // - always updates timestamps + auth info
    final data = <String, dynamic>{
      "onboarded": false, // merge-safe (won't override true if already true unless you write it)
      "profileComplete": false,
      "auth": {
        "provider": providerId ?? "unknown",
        "emailVerified": user.emailVerified,
      },
      "updatedAt": FieldValue.serverTimestamp(),
      "createdAt": FieldValue.serverTimestamp(),
    };

    if (email.isNotEmpty) {
      data["parent"] = {
        "email": email,
        if (pendingName.isNotEmpty) "name": pendingName,
      };
    } else if (pendingName.isNotEmpty) {
      data["parent"] = {"name": pendingName};
    }

    try {
      await _userRef
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      // We can clear pending name once it's safely merged into Firestore.
      if (pendingName.isNotEmpty) PendingSignup.clear();

      if (mounted) {
        setState(() {
          _bootstrapped = true;
          _bootstrapFailed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _bootstrapped = false;
          _bootstrapFailed = true;
        });
      }
    }
  }

  // --- child commits ---

  void _commitChild() {
    // IMPORTANT: never put FieldValue.serverTimestamp() inside this map
    children.add({...currentChild});
    currentChild = {};
  }

  Future<void> _finishOnboarding() async {
    try {
      await _userRef
          .set(
            {
              "onboarded": true,
              "profileComplete": true,
              "children": children,
              "updatedAt": FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not finish onboarding: $e')),
        );
      }
      return;
    }

    if (!mounted) return;

    // AuthGate will now show the app since onboarded=true.
    Navigator.of(context).pushReplacementNamed('/app');
  }

  Future<void> _skipOnboardingPostAuth() async {
    try {
      await _userRef
          .set(
            {
              "onboarded": true,
              "profileComplete": false,
              "updatedAt": FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/app');
  }
}

/// Minimal local unawaited helper (matches your style elsewhere)
void unawaited(Future<void> f) {}

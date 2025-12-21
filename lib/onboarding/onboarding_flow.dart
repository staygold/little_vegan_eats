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

enum OnboardingStep {
  childName,
  childDob,
  childHasAllergies,
  childAllergies,
  anotherChild,
  complete,
}

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  OnboardingStep step = OnboardingStep.childName;

  final List<Map<String, dynamic>> children = [];
  Map<String, dynamic> currentChild = {};

  void next(OnboardingStep s) => setState(() => step = s);

  DocumentReference<Map<String, dynamic>> get _userRef {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('No authenticated user.');
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  @override
  Widget build(BuildContext context) {
    switch (step) {
      case OnboardingStep.childName:
        return StepChildName(
          onNext: (name) {
            currentChild = {"name": name};
            next(OnboardingStep.childDob);
          },
          onSkip: _skipOnboarding,
        );

      case OnboardingStep.childDob:
        return StepChildDob(
          childName: (currentChild["name"] ?? "").toString(),
          onNext: (dob) {
            currentChild["dob"] = dob;
            next(OnboardingStep.childHasAllergies);
          },
        );

      case OnboardingStep.childHasAllergies:
        return StepChildAllergiesYesNo(
          childName: (currentChild["name"] ?? "").toString(),
          onYes: () => next(OnboardingStep.childAllergies),
          onNo: () {
            currentChild["hasAllergies"] = false;
            currentChild["allergies"] = <String>[]; // canonical keys
            _commitChild();
            next(OnboardingStep.anotherChild);
          },
        );

      case OnboardingStep.childAllergies:
        return StepChildAllergies(
          childName: (currentChild["name"] ?? "").toString(),
          onConfirm: (list) {
            // StepChildAllergies returns labels like "Peanuts", "Tree nuts", etc.
            // Convert to canonical keys like "peanut", "tree_nut"
            final canonical = list
                .map((a) => AllergyKeys.normalize(a))
                .whereType<String>()
                .toSet()
                .toList()
              ..sort();

            currentChild["hasAllergies"] = canonical.isNotEmpty;
            currentChild["allergies"] = canonical;

            _commitChild();
            next(OnboardingStep.anotherChild);
          },
        );

      case OnboardingStep.anotherChild:
        return StepAnotherChild(
          lastChildName:
              children.isEmpty ? "" : (children.last["name"] ?? "").toString(),
          onYes: () => next(OnboardingStep.childName),
          onNo: () => next(OnboardingStep.complete),
        );

      case OnboardingStep.complete:
        return OnboardingCompleteScreen(
          childrenNames:
              children.map((c) => (c['name'] ?? '').toString()).toList(),
          onFinish: _finishOnboarding,
        );
    }
  }

  void _commitChild() {
    // IMPORTANT: never put FieldValue.serverTimestamp() inside this map (arrays cannot contain it)
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
              "children": children, // array of maps, no FieldValue inside
              "updatedAt": FieldValue.serverTimestamp(), // OK here (top-level)
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
    Navigator.of(context).pushReplacementNamed('/app');
  }

  Future<void> _skipOnboarding() async {
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

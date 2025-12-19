import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'steps/step_parent_name.dart';
import 'steps/step_email.dart';
import 'steps/step_password.dart';
import 'steps/step_child_name.dart';
import 'steps/step_child_dob.dart';
import 'steps/step_child_allergies_yes_no.dart';
import 'steps/step_child_allergies.dart';
import 'steps/step_another_child.dart';
import 'steps/onboarding_complete_screen.dart';

enum OnboardingStep {
  parentName,
  email,
  password,
  childName,
  childDob,
  childHasAllergies,
  childAllergies,
  anotherChild,
  complete,
}

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.userRef,
  });

  final DocumentReference<Map<String, dynamic>> userRef;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  OnboardingStep step = OnboardingStep.parentName;

  String? parentName;
  String? email;
  String? password;

  final List<Map<String, dynamic>> children = [];
  Map<String, dynamic> currentChild = {};

  void next(OnboardingStep s) => setState(() => step = s);

  @override
  Widget build(BuildContext context) {
    switch (step) {

      // ───────────────────────── Parent details ─────────────────────────

      case OnboardingStep.parentName:
        return StepParentName(
          initialValue: parentName,
          onNext: (name) {
            parentName = name;
            next(OnboardingStep.email);
          },
        );

      case OnboardingStep.email:
        return StepEmail(
          initialValue: email,
          onBack: () => next(OnboardingStep.parentName),
          onNext: (val) {
            email = val;
            next(OnboardingStep.password);
          },
        );

     case OnboardingStep.password:
  return StepPassword(
    onBack: () => next(OnboardingStep.email),
    onNext: (pw) async {
      password = pw;

      try {
        debugPrint('[onboarding] before _saveParentBasics');
        await _saveParentBasics().timeout(const Duration(seconds: 10));
        debugPrint('[onboarding] after _saveParentBasics');

        next(OnboardingStep.childName);
      } catch (e, st) {
        debugPrint('[onboarding] ERROR saving basics: $e');
        debugPrint('$st');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save details: $e')),
        );

        rethrow; // so StepPassword stops the spinner too
      }
    },
  );

      // ───────────────────────── Child flow ─────────────────────────

      case OnboardingStep.childName:
        return StepChildName(
          onBack: children.isEmpty
              ? () => next(OnboardingStep.password)
              : () => next(OnboardingStep.anotherChild),
          onNext: (name) {
            currentChild = {"name": name};
            next(OnboardingStep.childDob);
          },
        );

      case OnboardingStep.childDob:
        return StepChildDob(
          childName: currentChild["name"] ?? "",
          onBack: () => next(OnboardingStep.childName),
          onNext: (dob) {
            currentChild["dob"] = dob;
            next(OnboardingStep.childHasAllergies);
          },
        );

      case OnboardingStep.childHasAllergies:
        return StepChildAllergiesYesNo(
          childName: currentChild["name"] ?? "",
          onBack: () => next(OnboardingStep.childDob),
          onYes: () => next(OnboardingStep.childAllergies),
          onNo: () {
            currentChild["hasAllergies"] = false;
            currentChild["allergies"] = [];
            _commitChild();
            next(OnboardingStep.anotherChild);
          },
        );

      case OnboardingStep.childAllergies:
        return StepChildAllergies(
          childName: currentChild["name"] ?? "",
          onBack: () => next(OnboardingStep.childHasAllergies),
          onConfirm: (list) {
            currentChild["hasAllergies"] = true;
            currentChild["allergies"] = list;
            _commitChild();
            next(OnboardingStep.anotherChild);
          },
        );

      case OnboardingStep.anotherChild:
        return StepAnotherChild(
          lastChildName: children.isNotEmpty
              ? children.last["name"]
              : currentChild["name"] ?? "",
          onBack: () => next(OnboardingStep.childName),
          onYes: () => next(OnboardingStep.childName),
          onNo: () => next(OnboardingStep.complete),
        );

      // ───────────────────────── Finish ─────────────────────────

      case OnboardingStep.complete:
        return OnboardingCompleteScreen(
          onFinish: () async {
            await _finishOnboarding();
            if (!mounted) return;
            Navigator.of(context).pushReplacementNamed('/recipes');
          },
        );
    }
  }

  // ───────────────────────── Helpers ─────────────────────────

  void _commitChild() {
    children.add({...currentChild});
    currentChild = {};
  }

  Future<void> _saveParentBasics() async {
  debugPrint('[onboarding] _saveParentBasics start');
  debugPrint('[onboarding] userRef path = ${widget.userRef.path}');

  await widget.userRef.set(
    {
      "parent": {
        "name": parentName,
        "email": email,
      },
      "updatedAt": FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  debugPrint('[onboarding] _saveParentBasics done');
}

  Future<void> _finishOnboarding() async {
    await widget.userRef.set(
      {
        "onboarded": true,
        "parent": {
          "name": parentName,
          "email": email,
        },
        "children": children,
        "updatedAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

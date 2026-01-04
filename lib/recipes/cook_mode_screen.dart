// lib/recipes/cook_mode_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_theme.dart';


class CookModeScreen extends StatefulWidget {
  const CookModeScreen({
    super.key,
    required this.title,
    required this.steps,
    this.recipeId,
  });

  final String title;
  final List<String> steps;

  /// Optional: pass the recipe id so we can record completion.
  final int? recipeId;

  @override
  State<CookModeScreen> createState() => _CookModeScreenState();
}

class _CookModeScreenState extends State<CookModeScreen> {
  int index = 0;

  late final DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
  }

  // If you later add a timer, you can cancel it here.
  void _stopTimer() {
    // no-op for now
  }

  Future<void> _finishCooking() async {
    _stopTimer();

    final durationSeconds = DateTime.now().difference(_startedAt).inSeconds;

    try {
      final user = FirebaseAuth.instance.currentUser;

      // Never block exit if auth is missing or recipeId not provided.
      if (user != null && widget.recipeId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('cookHistory')
            .add({
          'recipeId': widget.recipeId,
          'completedAt': FieldValue.serverTimestamp(),
          'durationSeconds': durationSeconds,
        });
      }
    } catch (_) {
      // silent fail – completion should never stop the user leaving
    }

    if (!mounted) return;

   ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    backgroundColor: AppColors.brandDark,
    content: const Text('Cooking complete 👏'),
  ),
);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasSteps = widget.steps.isNotEmpty;
    final stepText = hasSteps ? widget.steps[index] : 'No steps found.';
    final isLastStep = hasSteps && index == widget.steps.length - 1;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasSteps
                  ? 'Step ${index + 1} of ${widget.steps.length}'
                  : 'Cook Mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  stepText,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (!hasSteps || index == 0)
                        ? null
                        : () {
                            _stopTimer();
                            setState(() => index--);
                          },
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: !hasSteps
                        ? null
                        : isLastStep
                            ? _finishCooking
                            : () {
                                _stopTimer();
                                setState(() => index++);
                              },
                    child: Text(isLastStep ? 'Finish cooking' : 'Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

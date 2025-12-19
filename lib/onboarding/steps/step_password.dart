import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StepPassword extends StatefulWidget {
  const StepPassword({
    super.key,
    required this.email,
    required this.onCreated,
    this.onBack,
  });

  final String email;
  final VoidCallback onCreated;
  final VoidCallback? onBack;

  @override
  State<StepPassword> createState() => _StepPasswordState();
}

class _StepPasswordState extends State<StepPassword> {
  final controller = TextEditingController();
  bool loading = false;

  Future<void> _submit() async {
    setState(() => loading = true);

    await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: widget.email,
      password: controller.text,
    );

    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: loading ? null : _submit,
              child: loading
                  ? const CircularProgressIndicator()
                  : const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}

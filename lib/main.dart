import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'auth/auth_gate.dart';
import 'recipes/recipe_list_screen.dart'; // <-- add this

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const LittleVeganEatsApp());
}

class LittleVeganEatsApp extends StatelessWidget {
  const LittleVeganEatsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Little Vegan Eats',
      theme: ThemeData(useMaterial3: true),
      home: const AuthGate(),
      routes: {
        '/recipes': (_) => RecipeListScreen(), // <-- remove const
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';
import 'auth/auth_gate.dart';
import 'app/app_shell.dart';
import 'meal_plan/meal_plan_screen.dart';
import 'recipes/recipes_bootstrap_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Local cache (Hive)
  await Hive.initFlutter();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color appBackground = Color(0xFFECF3F4);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // ✅ GLOBAL THEME
      theme: ThemeData(
        useMaterial3: true,

        // ✅ Page background
        scaffoldBackgroundColor: appBackground,

        // Helps keep cards + surfaces white
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF32998D),
          background: appBackground,
          surface: Colors.white,
        ),
      ),

      // Root entry
      initialRoute: '/',

      routes: {
        '/': (_) => const AuthGate(),
        '/app': (_) => const AppShell(),

        // Meal plan (weekly)
        '/meal-plan': (_) =>
            RecipesBootstrapGate(child: MealPlanScreen()),
      },
    );
  }
}

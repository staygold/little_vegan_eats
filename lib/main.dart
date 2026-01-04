// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';
import 'auth/auth_gate.dart';
import 'app/app_shell.dart';
import 'meal_plan/meal_plan_screen.dart';
import 'recipes/recipes_bootstrap_gate.dart';

// ✅ GLOBAL: clamp scroll (no bounce / no pull-down reveal) + no glow (+ optional no scrollbar)
import 'app/no_bounce_scroll_behavior.dart';

// ✅ USE YOUR REAL APP THEME (includes SnackBarTheme, button themes, etc.)
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Status bar: let UI draw behind it, make icons white (matches your hero screens)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // Android icons
      statusBarBrightness: Brightness.dark, // iOS: dark => light icons
    ),
  );

  // ✅ IMPORTANT: don't block first frame with Firebase/Hive
  runApp(const MyApp());
}

/// Boots Firebase + Hive AFTER the first frame so you don't get the white screen
/// during debug / wireless deploy.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap({required this.child});
  final Widget child;

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();

    // Run AFTER first paint so the app renders immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        await Hive.initFlutter();

        if (!mounted) return;
        setState(() => _ready = true);
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Material(
        color: AppColors.bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Startup error:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppText.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return const Material(
        color: AppColors.bg,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return widget.child;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // ✅ This is now the ONLY theme source of truth (SnackBars included)
      theme: buildAppTheme(),

      // ✅ GLOBAL: no bounce / no pull-down reveal + no glow
      scrollBehavior: const NoBounceScrollBehavior(),

      // ✅ Boot Firebase/Hive AFTER first frame, then show AuthGate
      home: const _AppBootstrap(child: AuthGate()),

      // ✅ keep your routes intact (optional, but harmless)
      routes: {
        '/app': (_) => const AppShell(),
        '/meal-plan': (_) => RecipesBootstrapGate(child: MealPlanScreen()),
      },
    );
  }
}

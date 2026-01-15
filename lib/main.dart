// lib/main.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';
import 'auth/auth_gate.dart';
import 'app/app_shell.dart';
import 'meal_plan/meal_plan_screen.dart';
import 'recipes/recipes_bootstrap_gate.dart';

// Global scroll behaviour
import 'app/no_bounce_scroll_behavior.dart';

// App theme
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // Do NOT block first frame
  runApp(const MyApp());
}

/// Boots Firebase + Hive AFTER first frame
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // -------------------------------
        // Firebase
        // -------------------------------
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );

        // -------------------------------
        // Crashlytics
        // -------------------------------

        // 🔧 ENABLE while testing (you can change this later)
        await FirebaseCrashlytics.instance
    .setCrashlyticsCollectionEnabled(true);

        // Flutter framework errors (non-fatal unless framework aborts)
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterError;

        // Async / platform errors (fatal)
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(
            error,
            stack,
            fatal: true,
          );
          return true;
        };

        // -------------------------------
        // Hive
        // -------------------------------
        await Hive.initFlutter();

        if (!mounted) return;
        setState(() => _ready = true);
      } catch (e, st) {
        // Capture startup errors too
        await FirebaseCrashlytics.instance
            .recordError(e, st, fatal: true);

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

      // Single theme source of truth
      theme: buildAppTheme(),

      // Global scroll behaviour
      scrollBehavior: const NoBounceScrollBehavior(),

      // Firebase/Hive bootstrapped after first frame
      home: const _AppBootstrap(child: AuthGate()),

      routes: {
        '/app': (_) => const AppShell(),
        '/meal-plan': (_) =>
            RecipesBootstrapGate(child: MealPlanScreen()),
      },
    );
  }
}

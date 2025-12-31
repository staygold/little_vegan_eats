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

// ✅ global no-scrollbar behaviour
import 'app/no_scrollbar_behavior.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Status bar: let UI draw behind it, make icons white
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, // iOS ignores colour; must be transparent
      statusBarIconBrightness: Brightness.light, // Android icons
      statusBarBrightness: Brightness.dark, // iOS icons (dark bg => light icons)
    ),
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Hive.initFlutter();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // 🎨 Brand colours
  static const Color appBackground = Color(0xFFECF3F4);
  static const Color brandActive = Color(0xFF32998D);
  static const Color brandDark = Color(0xFF044246);

  static ThemeData _buildTheme() {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: appBackground,
      fontFamily: 'Montserrat',
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandActive,
        background: appBackground,
        surface: Colors.white,
        brightness: Brightness.light,
      ).copyWith(
        primary: brandActive,
        secondary: brandDark,
        surface: Colors.white,

        // ✅ LOCK "on" colours so random widgets stop rendering white text
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: brandDark,
        onSurface: brandDark,
      ),
    );

    final textTheme = base.textTheme.apply(
      fontFamily: 'Montserrat',
      bodyColor: brandDark,
      displayColor: brandDark,
    );

    final transparentOverlay = MaterialStateProperty.all(Colors.transparent);

    return base.copyWith(
      // 🚫 Kill splash / hover / highlight artefacts
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,

      textTheme: textTheme.copyWith(
        headlineSmall: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: brandDark,
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: brandDark,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: brandDark,
        ),
        labelLarge: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: brandDark,
        ),
      ),

      // 🧱 Global card style
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),

      // 📋 List tiles (also stop ListTile from inheriting weird “onSurfaceVariant”)
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textColor: brandDark,
        iconColor: brandDark,
      ),

      // 🔘 Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandActive,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ).copyWith(
          overlayColor: transparentOverlay,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brandDark,
          side: const BorderSide(color: brandDark, width: 1),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ).copyWith(
          overlayColor: transparentOverlay,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ).copyWith(
          overlayColor: transparentOverlay,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.all(brandDark),
          overlayColor: transparentOverlay,
        ),
      ),

      // 🧭 App bars
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: brandDark,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),

      // ✅ GLOBAL: no scrollbar, no overscroll glow
      scrollBehavior: NoScrollbarBehavior(),

      initialRoute: '/',
      routes: {
        '/': (_) => const AuthGate(),
        '/app': (_) => const AppShell(),
        '/meal-plan': (_) => RecipesBootstrapGate(child: MealPlanScreen()),
      },
    );
  }
}

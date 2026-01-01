// lib/shell/app_shell.dart
import 'dart:ui' show FontVariation;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../home/home_screen.dart';
import '../recipes/recipe_hub_screen.dart';
import '../meal_plan/plans_hub_screen.dart';
import '../profile/profile_screen.dart';

import 'top_header_bar.dart';

class AppShell extends StatefulWidget {
  final int initialIndex;

  const AppShell({super.key, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index;

  static const int _profileIndex = 3;

  final List<Widget> _pages = const [
    HomeScreen(),
    RecipeHubScreen(),
    PlansHubScreen(),
    ProfileScreen(),
  ];

  // 🎨 Colours
  static const Color inactiveColor = Color(0xFF005A4F);
  static const Color activeColor = Color(0xFF32998D);

  // 📐 Sizing (visual bar height, safe-area will be added automatically)
  static const double barHeight = 92;
  static const double iconSize = 24;

  // ✅ Cache first name so it never flashes back to "…" during stream rebuilds
  String? _cachedFirstName;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _pages.length - 1);
  }

  void _goProfile() {
    if (_index == _profileIndex) return;
    setState(() => _index = _profileIndex);
  }

  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  /// users/{uid}.adults[0].name → "Cat Dean" → "Cat"
  String? _extractFirstName(Map<String, dynamic> data) {
    final adults = data['adults'];
    if (adults is! List || adults.isEmpty) return null;

    final firstAdult = adults.first;
    if (firstAdult is! Map) return null;

    final name = (firstAdult['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.first : null;
  }

  Widget _buildHeader() {
    final doc = _userDoc();

    if (doc == null) {
      return TopHeaderBar(
        firstName: _cachedFirstName, // could be null
        onProfileTap: _goProfile,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: doc.snapshots(),
      builder: (context, snap) {
        // ✅ Always prefer cached value to avoid flashing
        String? firstNameToShow = _cachedFirstName;

        if (snap.hasData) {
          final data = snap.data?.data() ?? <String, dynamic>{};
          final extracted = _extractFirstName(data);

          // only update cache when we have a real, non-empty value
          if (extracted != null && extracted.trim().isNotEmpty) {
            _cachedFirstName = extracted.trim();
            firstNameToShow = _cachedFirstName;
          }
        }

        return TopHeaderBar(
          firstName: firstNameToShow, // never forced to "…"
          onProfileTap: _goProfile,
        );
      },
    );
  }

  Widget _navIcon(String asset, bool active) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          asset,
          width: iconSize,
          height: iconSize,
          colorFilter: ColorFilter.mode(
            active ? activeColor : inactiveColor,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );

    return Scaffold(
      body: Column(
        children: [
          // ✅ Header extends behind the iOS status bar
          _buildHeader(),

          // ✅ IMPORTANT:
          // We do NOT want bottom SafeArea padding here, because it creates the “green bar” gap
          // above the bottom nav. The bottom nav will handle the safe area instead.
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false, // ✅ FIX: remove the gap above BottomNavigationBar
              child: IndexedStack(
                index: _index,
                children: _pages,
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: Theme(
        data: theme,
        child: SafeArea(
          top: false,
          // ✅ Bottom safe area belongs to the nav (not the page body)
          child: Container(
            height: barHeight,
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  offset: Offset(0, 0),
                  blurRadius: 20,
                  spreadRadius: 0,
                  color: Color.fromRGBO(0, 0, 0, 0.2),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _index,
              onTap: (i) {
                if (i == _index) return;
                setState(() => _index = i);
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              elevation: 0,
              selectedItemColor: activeColor,
              unselectedItemColor: inactiveColor,
              selectedFontSize: 12,
              unselectedFontSize: 12,

              // ✅ Variable font weight lock
              selectedLabelStyle: const TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w700,
                fontVariations: [FontVariation('wght', 700)],
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w700,
                fontVariations: [FontVariation('wght', 700)],
              ),

              items: [
                BottomNavigationBarItem(
                  icon: _navIcon('assets/images/icons/home.svg', false),
                  activeIcon: _navIcon('assets/images/icons/home.svg', true),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: _navIcon('assets/images/icons/recipes.svg', false),
                  activeIcon: _navIcon('assets/images/icons/recipes.svg', true),
                  label: 'Recipes',
                ),
                BottomNavigationBarItem(
                  icon: _navIcon('assets/images/icons/plans.svg', false),
                  activeIcon: _navIcon('assets/images/icons/plans.svg', true),
                  label: 'Plans',
                ),
                BottomNavigationBarItem(
                  icon: _navIcon('assets/images/icons/family.svg', false),
                  activeIcon: _navIcon('assets/images/icons/family.svg', true),
                  label: 'Family',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

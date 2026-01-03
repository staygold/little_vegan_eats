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

  static const Color inactiveColor = Color(0xFF005A4F);
  static const Color activeColor = Color(0xFF32998D);
  static const double iconSize = 24;

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

  String? _extractFirstName(Map<String, dynamic> data) {
    final adults = data['adults'];
    if (adults is! List || adults.isEmpty) return null;

    final firstAdult = adults.first;
    if (firstAdult is! Map) return null;

    final name = (firstAdult['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    return name.split(RegExp(r'\s+')).first;
  }

  Widget _buildHeader() {
    final doc = _userDoc();

    if (doc == null) {
      return TopHeaderBar(
        firstName: _cachedFirstName,
        onProfileTap: _goProfile,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: doc.snapshots(),
      builder: (context, snap) {
        var name = _cachedFirstName;
        if (snap.hasData) {
          final extracted = _extractFirstName(snap.data!.data() ?? {});
          if (extracted != null && extracted.isNotEmpty) {
            _cachedFirstName = extracted;
            name = extracted;
          }
        }
        return TopHeaderBar(
          firstName: name,
          onProfileTap: _goProfile,
        );
      },
    );
  }

  Widget _navIcon(String asset, bool active) {
    return SvgPicture.asset(
      asset,
      width: iconSize,
      height: iconSize,
      colorFilter: ColorFilter.mode(
        active ? activeColor : inactiveColor,
        BlendMode.srcIn,
      ),
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
          _buildHeader(),
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false,
              child: IndexedStack(
                index: _index,
                children: _pages,
              ),
            ),
          ),
        ],
      ),

      // ✅ THIS IS THE KEY PART
      bottomNavigationBar: Theme(
        data: theme,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                blurRadius: 20,
                color: Color.fromRGBO(0, 0, 0, 0.2),
              ),
            ],
          ),
         child: SafeArea(
  top: false,
  child: Padding(
    padding: const EdgeInsets.only(top: 6), // 👈 adjust this
    child: BottomNavigationBar(
              currentIndex: _index,
              onTap: (i) {
                if (i == _index) return;
                setState(() => _index = i);
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              elevation: 0,
              iconSize: iconSize,
              selectedItemColor: activeColor,
              unselectedItemColor: inactiveColor,
              selectedFontSize: 12,
              unselectedFontSize: 12,
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
      ),
    );
  }
}

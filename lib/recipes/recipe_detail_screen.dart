// lib/recipes/recipe_detail_screen.dart
import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../theme/app_theme.dart';
import '../utils/text.dart';
import '../utils/images.dart';
import '../recipes/recipe_repository.dart';
import '../recipes/serving_engine.dart';
import '../recipes/favorites_service.dart';
import 'cook_mode_screen.dart';
import '../app/no_bounce_scroll_behavior.dart';

import '../lists/shopping_list_picker_sheet.dart';
import '../lists/shopping_repo.dart';

// ✅ Family profile now comes from the repo (single source of truth)
import '../recipes/family_profile_repository.dart';
import '../recipes/family_profile.dart';

class _RText {
  static const String font = 'Montserrat';

  static const TextStyle h1 = TextStyle(
    fontFamily: font,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    height: 1.05,
    letterSpacing: 0,
    color: AppColors.brandDark,
  );

  static const TextStyle meta = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.2,
    letterSpacing: 0,
    color: AppColors.brandDark,
  );

  static const TextStyle section = TextStyle(
    fontFamily: font,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    height: 1.0,
    letterSpacing: 0.2,
    color: AppColors.brandDark,
  );

  static const TextStyle title = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    height: 1.1,
    letterSpacing: 0,
    color: AppColors.brandDark,
  );

  static const TextStyle body = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.6,
    letterSpacing: 0,
    color: AppColors.brandDark,
  );

  static const TextStyle bodySoft = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 1.4,
    letterSpacing: 0,
    color: AppColors.brandDark,
  );

  static const TextStyle chip = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 1.0,
    letterSpacing: 0,
    color: AppColors.brandDark,
  );

  static const TextStyle button = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    height: 1.0,
    letterSpacing: 0,
    color: Colors.white,
  );

  static const TextStyle instructionNumber = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
    height: 1.0,
    color: AppColors.brandDark,
  );

  static const TextStyle instructionText = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.4,
    color: AppColors.brandDark,
  );

  static const TextStyle ingAmount = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.4,
    color: AppColors.brandDark,
  );

  static const TextStyle ingName = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.4,
    color: AppColors.brandDark,
  );

  static const TextStyle ingNotes = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 1.4,
    color: AppColors.brandDark,
  );

  static const double ingRadius = 12;
  static const EdgeInsets ingPadding = EdgeInsets.fromLTRB(18, 16, 18, 16);

  static const TextStyle servingTop = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.1,
    color: AppColors.brandDark,
  );

  static const TextStyle servingMid = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.4,
    color: AppColors.brandDark,
  );

  static const TextStyle servingBanner = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    height: 1.0,
    color: AppColors.brandDark,
  );

  static const TextStyle servingRecLabel = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 1.2,
    color: AppColors.brandDark,
  );

  static const TextStyle servingRecStrong = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.1,
    color: AppColors.brandDark,
  );

  static const TextStyle servingRecSoft = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 1.1,
    color: AppColors.brandDark,
  );

  static const TextStyle servingCta = TextStyle(
    fontFamily: font,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    letterSpacing: 0.5,
    height: 1.0,
    color: Colors.white,
  );

  static const TextStyle stepperLabel = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    height: 1.0,
    color: Color.fromARGB(215, 0, 90, 80),
  );

  static const TextStyle stepperValue = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    height: 1.0,
    color: AppColors.brandDark,
  );
}

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({super.key, required this.id});
  final int id;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'LittleVeganEatsApp/1.0',
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  int _adults = 2;
  int _kids = 1;
  int _profileAdults = 2;
  int _profileKids = 1;
  double _scale = 1.0;

  /// 1 = Metric (default), 2 = US (if conversion exists)
  int _unitSystem = 1;

  /// ✅ Only used to decide whether to show the "ALLERGY SWAPS" section.
  bool _profileHasAllergies = false;

  // ✅ single subscription via repo
  StreamSubscription<FamilyProfile>? _familySub;

  final ScrollController _scrollCtrl = ScrollController();
  double _scrollY = 0;

  bool _showStickyHeader = false;

  @override
  void initState() {
    super.initState();
    _wireFamilyProfile();
    _load(forceRefresh: false);

    _scrollCtrl.addListener(() {
      if (!mounted) return;

      final offset = _scrollCtrl.offset;
      const double threshold = 260.0 - kToolbarHeight - 20;
      final shouldBeSticky = offset > threshold;

      setState(() {
        _scrollY = offset;
        if (_showStickyHeader != shouldBeSticky) {
          _showStickyHeader = shouldBeSticky;
        }
      });
    });
  }

  @override
  void dispose() {
    _familySub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _wireFamilyProfile() {
    final repo = FamilyProfileRepository();

    _familySub = repo.watchFamilyProfile().listen((family) {
      int namedCount(List list) {
        return list.where((p) {
          try {
            final name = (p.name ?? '').toString().trim();
            return name.isNotEmpty;
          } catch (_) {
            return false;
          }
        }).length;
      }

      bool anyAllergies(List list) {
        return list.any((p) {
          try {
            return p.hasAllergies == true;
          } catch (_) {
            return false;
          }
        });
      }

      final adultCount = namedCount(family.adults);
      final kidCount = namedCount(family.children);

      final nextAdults = adultCount > 0 ? adultCount : 1;
      final nextKids = kidCount;

      final hasAllergies = anyAllergies(family.adults) || anyAllergies(family.children);

      if (!mounted) return;

      final changedCounts = (nextAdults != _profileAdults) || (nextKids != _profileKids);
      final changedAllergies = hasAllergies != _profileHasAllergies;

      if (changedCounts || changedAllergies) {
        setState(() {
          final prevProfileAdults = _profileAdults;
          final prevProfileKids = _profileKids;

          _profileAdults = nextAdults;
          _profileKids = nextKids;
          _profileHasAllergies = hasAllergies;

          // keep manual steppers unless they still match the previous profile defaults
          if (_adults == prevProfileAdults) _adults = _profileAdults;
          if (_kids == prevProfileKids) _kids = _profileKids;
        });
      }
    });
  }

  Future<void> _load({required bool forceRefresh}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await RecipeRepository.ensureRecipesLoaded(
        backgroundRefresh: true,
        forceRefresh: forceRefresh,
      );
      final cached = _findById(list, widget.id);
      if (cached != null) {
        setState(() {
          _data = cached;
          _loading = false;
        });
        return;
      }

      final res = await _dio.get(
        'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe/${widget.id}',
      );
      setState(() {
        _data = Map<String, dynamic>.from(res.data.cast<String, dynamic>());
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _findById(List<Map<String, dynamic>> list, int id) {
    for (final r in list) {
      final rid = r['id'];
      if (rid is int && rid == id) return r;
      if (rid is String && int.tryParse(rid) == id) return r;
    }
    return null;
  }

  ServingAdvice? _safeAdvice(Map<String, dynamic>? recipe) {
    if (recipe == null) return null;
    try {
      return buildServingAdvice(recipe: recipe, adults: _adults, kids: _kids);
    } catch (_) {
      return null;
    }
  }

  void _applyScale(double value) => setState(() => _scale = value);

  // ===========================================================================
  // 🟢 HELPERS: FIELDS & PARSING
  // ===========================================================================

  String _sanitize(dynamic val) {
    if (val == null) return '';
    if (val is bool && val == false) return '';
    final s = val.toString().trim();
    if (s.toLowerCase() == 'false') return '';
    return s;
  }

  String _getField(Map<String, dynamic>? r, String key) {
    if (r == null) return '';

    if (r['recipe'] is Map) {
      final recipeData = r['recipe'] as Map;
      if (recipeData['custom_fields'] is Map) {
        final val = _sanitize(recipeData['custom_fields'][key]);
        if (val.isNotEmpty) return val;
      }
      final val = _sanitize(recipeData[key]);
      if (val.isNotEmpty) return val;
    }

    if (r['custom_fields'] is Map) {
      final val = _sanitize(r['custom_fields'][key]);
      if (val.isNotEmpty) return val;
    }

    var val = _sanitize(r[key]);
    if (val.isNotEmpty) return val;

    if (r['meta'] is Map) {
      val = _sanitize(r['meta'][key]);
      if (val.isNotEmpty) return val;
    }

    if (r['recipe'] is Map && r.keys.length > 1) {
      final inner = r['recipe'] as Map<String, dynamic>;
      if (inner != r) {
        return _getField(inner, key);
      }
    }

    return '';
  }

  List<Map<String, String>> _parseSwaps(String raw) {
    if (raw.trim().isEmpty) return [];
    final list = <Map<String, String>>[];
    final pairs = raw.split(',');
    for (var pair in pairs) {
      final parts = pair.split('>');
      if (parts.length == 2) {
        list.add({'from': parts[0].trim(), 'to': parts[1].trim()});
      }
    }
    return list;
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString().trim());
  }

  String _pluralise(String singular, int count) {
    if (count == 1) return singular;

    if (singular.endsWith('y') &&
        !singular.endsWith('ay') &&
        !singular.endsWith('ey') &&
        !singular.endsWith('oy') &&
        !singular.endsWith('uy')) {
      return '${singular.substring(0, singular.length - 1)}ies';
    }

    if (singular.endsWith('s') ||
        singular.endsWith('x') ||
        singular.endsWith('z') ||
        singular.endsWith('ch') ||
        singular.endsWith('sh')) {
      return '${singular}es';
    }

    return '${singular}s';
  }

  // ===========================================================================
  // ✅ WPRM ITEM MODE HELPERS (read from recipe.tags.*)
  // ===========================================================================

  String _termSlug(Map<String, dynamic>? recipe, String groupKey) {
    final tags = recipe?['tags'];
    if (tags is Map) {
      final list = tags[groupKey];
      if (list is List && list.isNotEmpty && list.first is Map) {
        final m = list.first as Map;
        final slug = (m['slug'] ?? '').toString().trim();
        if (slug.isNotEmpty) return slug;
      }
    }
    return '';
  }

  String _termName(Map<String, dynamic>? recipe, String groupKey) {
    final tags = recipe?['tags'];
    if (tags is Map) {
      final list = tags[groupKey];
      if (list is List && list.isNotEmpty && list.first is Map) {
        final m = list.first as Map;
        final name = (m['name'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    }
    return '';
  }

  int? _termNameInt(Map<String, dynamic>? recipe, String groupKey) {
    final s = _termName(recipe, groupKey);
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  bool _isItemsMode(Map<String, dynamic>? recipe) {
    final slug = _termSlug(recipe, 'serving_mode').toLowerCase();
    return slug == 'item' || slug == 'items';
  }

  String _itemLabelSingular(Map<String, dynamic>? recipe) {
    final label = _termName(recipe, 'item_label').toLowerCase().trim();
    return label.isNotEmpty ? label : 'item';
  }

  int? _itemsPerPerson(Map<String, dynamic>? recipe) {
    return _termNameInt(recipe, 'items_per_person');
  }

  double _kidsFactor(Map<String, dynamic>? recipe) {
    if (recipe == null) return 0.5;

    final term = _termName(recipe, 'kids_items_factor').trim();
    if (term.isNotEmpty) {
      final v = double.tryParse(term);
      if (v != null) {
        if ((v - 1.0).abs() < 0.0001) return 1.0;
        if ((v - 0.5).abs() < 0.0001) return 0.5;
      }
    }

    final cf1 = _getField(recipe, 'kids_items_factor').trim();
    if (cf1 == '1') return 1.0;
    final cf2 = _getField(recipe, 'wprm_kids_items_factor').trim();
    if (cf2 == '1') return 1.0;

    return 0.5;
  }

  // ===========================================================================
  // ✅ Items-mode scaling rules
  // ===========================================================================

  double _roundUpToHalf(double v) {
    if (v <= 0) return 0.0;
    return ((v * 2).ceilToDouble()) / 2.0;
  }

  // ===========================================================================
  // WPRM UNIT HELPERS
  // ===========================================================================

  bool _rowHasConverted2(Map row) {
    final converted = row['converted'];
    if (converted is Map) {
      final c2 = converted['2'] ?? converted[2];
      if (c2 is Map) {
        final amt = c2['amount']?.toString().trim() ?? '';
        final unit = c2['unit']?.toString().trim() ?? '';
        return amt.isNotEmpty || unit.isNotEmpty;
      }
    }
    return false;
  }

  bool _hasConvertedSystem2(List ingredientsFlat) {
    for (final row in ingredientsFlat) {
      if (row is Map && row['type'] != 'group') {
        if (_rowHasConverted2(row)) return true;
      }
    }
    return false;
  }

  Map<String, dynamic>? _converted2(Map row) {
    final converted = row['converted'];
    if (converted is Map) {
      final c2 = converted['2'] ?? converted[2];
      if (c2 is Map) return Map<String, dynamic>.from(c2.cast<String, dynamic>());
    }
    return null;
  }

  double? _parseAmountToDouble(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    const unicode = {
      '½': 0.5,
      '⅓': 1 / 3,
      '⅔': 2 / 3,
      '¼': 0.25,
      '¾': 0.75,
      '⅛': 0.125,
      '⅜': 0.375,
      '⅝': 0.625,
      '⅞': 0.875
    };
    if (unicode.containsKey(s)) return unicode[s];

    final mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(s);
    if (mixed != null) {
      final whole = double.parse(mixed.group(1)!);
      final a = double.parse(mixed.group(2)!);
      final b = double.parse(mixed.group(3)!);
      if (b == 0) return null;
      return whole + (a / b);
    }

    final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(s);
    if (frac != null) {
      final a = double.parse(frac.group(1)!);
      final b = double.parse(frac.group(2)!);
      if (b == 0) return null;
      return a / b;
    }

    return double.tryParse(s);
  }

  String _amountForRow(Map row) {
    if (_unitSystem == 2 && _rowHasConverted2(row)) {
      final c2 = _converted2(row);
      final raw = (c2?['amount'] ?? '').toString();
      return _scaledAmount(raw, _scale);
    }
    return _scaledAmount((row['amount'] ?? '').toString(), _scale);
  }

  String _unitForRow(Map row) {
    if (_unitSystem == 2 && _rowHasConverted2(row)) {
      final c2 = _converted2(row);
      final u = (c2?['unit'] ?? '').toString().trim();
      return u;
    }
    return (row['unit'] ?? '').toString().trim();
  }

  // ===========================================================================
  // ✅ SHOPPING LIST: convert ingredients_flat -> List<ShoppingIngredient>
  // ===========================================================================
  List<ShoppingIngredient> _ingredientsToShoppingIngredients(List ingredientsFlat) {
    final out = <ShoppingIngredient>[];

    for (final row in ingredientsFlat) {
      if (row is! Map) continue;

      // ✅ FILTER OUT GROUPS/HEADERS
      final type = (row['type'] ?? '').toString().toLowerCase();
      if (type == 'group' || type == 'header') continue;

      final name = (row['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final notes = stripHtml((row['notes'] ?? '').toString()).trim();

      final metricAmount = _scaledAmount((row['amount'] ?? '').toString(), _scale).trim();
      final metricUnit = (row['unit'] ?? '').toString().trim();

      String usAmount = '';
      String usUnit = '';
      if (_rowHasConverted2(row)) {
        final c2 = _converted2(row);
        usAmount = _scaledAmount((c2?['amount'] ?? '').toString(), _scale).trim();
        usUnit = (c2?['unit'] ?? '').toString().trim();
      }

      out.add(
        ShoppingIngredient(
          name: name,
          notes: notes,
          metricAmount: metricAmount,
          metricUnit: metricUnit,
          usAmount: usAmount,
          usUnit: usUnit,
        ),
      );
    }

    return out;
  }

  // ===========================================================================
  // UI HELPERS
  // ===========================================================================

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(22)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _circleFrostButton({
    required Widget child,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.white.withOpacity(0.22),
          child: InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleFrostIconWrapper({required Widget child}) {
    return SizedBox(width: 28, height: 28, child: Center(child: child));
  }

  Widget _unitSystemToggle({
    required bool show,
    String leftLabel = 'METRIC',
    String rightLabel = 'US',
  }) {
    if (!show) return const SizedBox.shrink();
    const trackBg = Colors.white;
    const pillBg = Color(0xFFD9E6E5);
    final border = Colors.black.withOpacity(0.06);
    const height = 40.0;
    const pad = 4.0;
    final radius = BorderRadius.circular(999);

    Widget segButton({required int value, required String label}) {
      final selected = _unitSystem == value;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            borderRadius: radius,
            onTap: () => setState(() => _unitSystem = value),
            child: SizedBox(
              height: height,
              child: Center(
                child: Text(
                  label,
                  style: _RText.bodySoft.copyWith(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontVariations: [FontVariation('wght', selected ? 700 : 600)],
                    color: AppColors.brandDark,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 12),
      padding: const EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: radius,
        border: Border.all(color: border),
      ),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            final half = (c.maxWidth - (pad * 2)) / 2;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  top: 0,
                  bottom: 0,
                  left: (_unitSystem == 1) ? 0 : half,
                  width: half,
                  child: Container(decoration: BoxDecoration(color: pillBg, borderRadius: radius)),
                ),
                Row(
                  children: [
                    segButton(value: 1, label: leftLabel),
                    segButton(value: 2, label: rightLabel),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// ✅ Allergies only affect whether we show swaps.
  /// If the profile has no allergies, we hide swaps completely.
  Widget _swapsCard(Map<String, dynamic>? recipe) {
    if (!_profileHasAllergies) return const SizedBox.shrink();

    final rawText = _getField(recipe, 'ingredient_swaps');
    final swaps = _parseSwaps(rawText);
    if (swaps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Row(
          children: [
            const Icon(Icons.swap_horiz_rounded, color: AppColors.brandDark, size: 24),
            const SizedBox(width: 8),
            Text('ALLERGY SWAPS', style: _RText.section),
          ],
        ),
        const SizedBox(height: 12),
        _card(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Column(
            children: [
              for (int i = 0; i < swaps.length; i++) ...[
                if (i > 0) Divider(height: 1, color: Colors.black.withOpacity(0.06)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          swaps[i]['from']!,
                          style: _RText.body.copyWith(
                            color: const Color.fromARGB(255, 141, 16, 16),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.arrow_forward_rounded, color: AppColors.brandDark, size: 20),
                      ),
                      Expanded(
                        flex: 5,
                        child: Text(
                          swaps[i]['to']!,
                          style: _RText.body.copyWith(color: AppColors.brandDark, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _servingSuggestionsCard(Map<String, dynamic>? recipe) {
    final text = stripHtml(_getField(recipe, 'serving')).trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        Text('SERVING SUGGESTIONS', style: _RText.section),
        const SizedBox(height: 12),
        _card(child: Text(text, style: _RText.body.copyWith(height: 1.4))),
      ],
    );
  }

  Widget _storageCard(Map<String, dynamic>? recipe) {
    String text = _getField(recipe, 'storage').trim();
    if (text.isEmpty) {
      final noteRaw = _sanitize(recipe?['notes']);
      text = stripHtml(noteRaw).trim();
    } else {
      text = stripHtml(text);
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        Text('STORAGE DETAILS', style: _RText.section),
        const SizedBox(height: 12),
        _card(child: Text(text, style: _RText.body.copyWith(height: 1.4))),
      ],
    );
  }

  Widget _peopleStepperCard({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    const bg = Color(0xFFF0F5F4);
    const text = Color(0xFF044246);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove, size: 20, color: text),
          ),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontFamily: 'Montserrat', color: text),
              children: [
                TextSpan(text: '$label: ', style: _RText.stepperLabel),
                TextSpan(text: '$value', style: _RText.stepperValue),
              ],
            ),
          ),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add, size: 20, color: text),
          ),
        ],
      ),
    );
  }

  String _multiplierLabel(double v) =>
      (v - 0.5).abs() < 0.0001 ? 'Half batch' : '${_fmtMultiplier(v)} batch';

  String _ctaLabel(double v) => (v - 0.5).abs() < 0.0001
      ? 'UPDATE TO HALF BATCH'
      : 'UPDATE INGREDIENTS (${_fmtMultiplier(v).toUpperCase()})';

  String _suggestMultiplierLine(double recommended, {required bool itemsMode}) => '';

  Widget _servingPanelCard(BuildContext context, Map<String, dynamic>? recipe) {
    final itemsMode = _isItemsMode(recipe);
    final ipp = _itemsPerPerson(recipe);
    final itemSingular = _itemLabelSingular(recipe);
    final kFactor = _kidsFactor(recipe);

    final servingsRaw = (recipe?['servings'] ?? recipe?['servings_number'] ?? recipe?['servings_amount']);
    final servingsCount = _toInt(servingsRaw);

    final advice = _safeAdvice(recipe);
    if (!itemsMode && advice == null) return const SizedBox.shrink();

    String? makesLine;
    int? itemsMade;
    if (itemsMode && servingsCount != null && ipp != null) {
      itemsMade = (servingsCount * ipp).clamp(0, 999999);
      final itemsText = _pluralise(itemSingular, itemsMade);
      makesLine =
          'Makes $itemsMade $itemsText ($servingsCount adult ${servingsCount == 1 ? 'serving' : 'servings'})';
    } else if (servingsRaw != null && servingsRaw.toString().trim().isNotEmpty) {
      final servingsText = servingsRaw.toString().trim();
      makesLine = 'This recipe makes $servingsText adult portions';
    }

    bool needsMore;
    bool showHalf;
    double? recommended;

    if (itemsMode && itemsMade != null && itemsMade > 0 && ipp != null && ipp > 0) {
      final rawItemsNeeded = (_adults * ipp) + (_kids * (ipp * kFactor));
      final itemsNeeded = rawItemsNeeded.round().clamp(0, 999999);

      final ratio = itemsNeeded / itemsMade;

      needsMore = ratio > 1.0;
      showHalf = ratio > 0 && ratio <= 0.65;

      if (needsMore) {
        recommended = _roundUpToHalf(ratio);
        if (recommended < 1.0) recommended = 1.0;
      } else if (showHalf) {
        recommended = 0.5;
      } else {
        recommended = null;
      }
    } else {
      needsMore = advice!.multiplierRaw > 1.0;
      showHalf = advice.canHalf && !needsMore;
      recommended = showHalf ? 0.5 : advice.recommendedMultiplier;
    }

    final showRecommended = recommended != null && (needsMore || showHalf);
    final isApplied = recommended != null && (recommended - _scale).abs() < 0.001;
    final showHiddenSection = showRecommended || _scale != 1.0;

    final perPersonSuffix = (itemsMode && ipp != null) ? '' : null;

    final bannerHeadline = needsMore
        ? 'You may want to make more'
        : (showHalf ? "You'll have leftovers" : 'Perfect for your family');

    String lineText;
    if (itemsMode && ipp != null && ipp > 0) {
      final rawItemsNeeded = (_adults * ipp) + (_kids * (ipp * kFactor));
      final totalItemsNeeded = rawItemsNeeded.round().clamp(0, 999999);
      lineText =
          'Your family needs the equivalent of ~$totalItemsNeeded ${_pluralise(itemSingular, totalItemsNeeded)} adult portions';
    } else {
      lineText = (advice != null && advice.detailLine.trim().isNotEmpty)
          ? advice.detailLine
          : 'Your family needs more';
    }

    return _card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (makesLine != null && makesLine.trim().isNotEmpty) ...[
            Text(makesLine, style: _RText.servingTop),
            const SizedBox(height: 12),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5F4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  needsMore ? Icons.warning_amber_rounded : Icons.check_circle,
                  size: 20,
                  color: AppColors.brandDark,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(bannerHeadline, style: _RText.servingBanner)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.black.withOpacity(0.08), height: 1),
          const SizedBox(height: 20),
          Text(lineText, style: _RText.servingMid),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _peopleStepperCard(
                label: 'Adults',
                value: _adults,
                onChanged: (v) => setState(() => _adults = v),
              ),
              const SizedBox(height: 12),
              _peopleStepperCard(
                label: 'Children',
                value: _kids,
                onChanged: (v) => setState(() => _kids = v),
              ),
            ],
          ),
          if (showHiddenSection) ...[
            const SizedBox(height: 20),
            Divider(color: Colors.black.withOpacity(0.08), height: 1),
            const SizedBox(height: 20),
          ],
          if (showRecommended && !isApplied) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Recommended:', style: _RText.servingRecLabel),
                const SizedBox(width: 10),
                Text(_multiplierLabel(recommended!), style: _RText.servingRecStrong),
                if (perPersonSuffix != null && !showHalf) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      perPersonSuffix,
                      style: _RText.servingRecSoft.copyWith(
                        color: const Color(0xFF044246).withOpacity(0.6),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandDark,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.transparent, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _applyScale(recommended!),
                child: Text(_ctaLabel(recommended!), style: _RText.servingCta),
              ),
            ),
          ] else if (_scale != 1.0) ...[
            Row(
              children: [
                Text('Ingredients updated to:', style: _RText.servingRecLabel),
                const SizedBox(width: 8),
                Text(_multiplierLabel(_scale), style: _RText.servingRecStrong),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.brandDark,
                  side: BorderSide(
                    color: AppColors.brandDark.withOpacity(0.6),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _applyScale(1.0),
                child: Text(
                  'RESET INGREDIENTS',
                  style: _RText.servingCta.copyWith(color: AppColors.brandDark),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic>? _nutritionMap(Map<String, dynamic>? recipe) {
    if (recipe == null) return null;
    final n = recipe['nutrition'];
    return n is Map ? Map<String, dynamic>.from(n.cast<String, dynamic>()) : null;
  }

  List<dynamic>? _parseValueUnit(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(-?\d+(?:\.\d+)?)\s*([^\d].*)?$').firstMatch(s);
    if (m == null) return null;
    final value = double.tryParse(m.group(1) ?? '');
    return value == null ? null : [value, (m.group(2) ?? '').trim()];
  }

  String _scaleNutritionString(dynamic raw, double mult) {
    if (raw == null) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty) return '-';
    final parsed = _parseValueUnit(s);
    if (parsed == null) return s;
    final value = (parsed[0] as double) * mult;
    final unit = parsed[1] as String;
    final pretty = _fmtSmart(value);
    return unit.isEmpty ? pretty : '$pretty $unit';
  }

  Widget _nutritionPanel(BuildContext context, Map<String, dynamic>? recipe) {
    final n = _nutritionMap(recipe);
    if (n == null || n.isEmpty) return const SizedBox.shrink();

    final kidMult = _kidsFactor(recipe);

    dynamic pick(List<String> keys) {
      for (final k in keys) {
        if (n.containsKey(k) && n[k] != null && n[k].toString().trim().isNotEmpty) return n[k];
      }
      return null;
    }

    final rows = [
      {'l': 'Calories', 'v': pick(['calories', 'kcal', 'energy']), 's': true},
      {'l': 'Fat', 'v': pick(['fat', 'total_fat']), 's': true},
      {'l': 'Sat Fat', 'v': pick(['saturated_fat', 'sat_fat', 'saturates']), 'sub': true},
      {'l': 'Carbs', 'v': pick(['carbohydrates', 'carbs']), 's': true},
      {'l': 'Sugar', 'v': pick(['sugar', 'sugars']), 'sub': true},
      {'l': 'Fibre', 'v': pick(['fiber', 'fibre']), 's': true},
      {'l': 'Protein', 'v': pick(['protein']), 's': true},
      {'l': 'Iron', 'v': pick(['iron']), 's': true},
      {'l': 'Calcium', 'v': pick(['calcium']), 's': true},
      {'l': 'Vitamin C', 'v': pick(['vitamin_c', 'vitaminC']), 's': true},
      {'l': 'Sodium', 'v': pick(['sodium', 'salt']), 's': true},
    ];
    if (rows.every((r) => r['v'] == null)) return const SizedBox.shrink();

    final footer = (kidMult - 1.0).abs() < 0.0001
        ? 'Child values are estimated at 1.0 adult serving'
        : 'Child values are estimated at 0.5 adult serving';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ESTIMATED NUTRITION', style: _RText.section),
        const SizedBox(height: 12),
        _card(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Text('Per serving', style: _RText.chip)),
                SizedBox(
                  width: 86,
                  child: Text('Adult', textAlign: TextAlign.right, style: _RText.chip),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 86,
                  child: Text('Child', textAlign: TextAlign.right, style: _RText.chip),
                ),
              ]),
              const SizedBox(height: 12),
              Divider(height: 1, thickness: 1, color: Colors.black.withOpacity(0.06)),
              const SizedBox(height: 8),
              for (int i = 0, visualIndex = 0; i < rows.length; i++)
                if (rows[i]['v'] != null)
                  Builder(builder: (context) {
                    final r = rows[i];
                    final isSub = r['sub'] == true;

                    bool nextIsSub = false;
                    for (int j = i + 1; j < rows.length; j++) {
                      if (rows[j]['v'] == null) continue;
                      nextIsSub = rows[j]['sub'] == true;
                      break;
                    }

                    final showDivider = isSub || !nextIsSub;

                    final isStriped = visualIndex.isOdd;
                    visualIndex++;

                    final bgColor = isStriped ? Colors.black.withOpacity(0.035) : Colors.transparent;

                    final topPadding = isSub ? 4.0 : 12.0;
                    final bottomPadding = isSub ? 8.0 : 12.0;

                    return Column(
                      children: [
                        Container(
                          color: bgColor,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: topPadding,
                              bottom: bottomPadding,
                              left: isSub ? 16 : 0,
                              right: 0,
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Text(
                                  isSub ? ' - ${r['l']}' : r['l'] as String,
                                  style: isSub
                                      ? _RText.bodySoft.copyWith(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        )
                                      : _RText.bodySoft.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 86,
                                child: Text(
                                  _scaleNutritionString(r['v'], 1.0),
                                  textAlign: TextAlign.right,
                                  style: isSub
                                      ? _RText.body.copyWith(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        )
                                      : _RText.body.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 86,
                                child: Text(
                                  _scaleNutritionString(r['v'], kidMult),
                                  textAlign: TextAlign.right,
                                  style: isSub
                                      ? _RText.body.copyWith(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        )
                                      : _RText.body.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                ),
                              ),
                            ]),
                          ),
                        ),
                        if (showDivider)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.black.withOpacity(0.06),
                          ),
                      ],
                    );
                  }),
              const SizedBox(height: 20),
              Text(footer, style: _RText.chip),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // ✅ SCALING HELPERS (these were missing in your broken file)
  // ===========================================================================

  String _scaledAmount(String rawAmount, double mult) {
    final a = rawAmount.trim();
    if (a.isEmpty || mult == 1.0) return a;

    final mX = RegExp(r'^\s*([0-9]+(?:\.\d+)?)(\s*x\s*)$', caseSensitive: false).firstMatch(a);
    if (mX != null) return '${_fmtSmart(double.parse(mX.group(1)!) * mult)} x';

    final mPrefix = RegExp(
      r'^\s*([0-9]+(?:\.\d+)?(?:\s+[0-9]+\s*/\s*[0-9]+|(?:\s*/\s*[0-9]+)?)|[½⅓⅔¼¾⅛⅜⅝⅞])',
    ).firstMatch(a);
    if (mPrefix != null) {
      final prefix = mPrefix.group(1)!.trim();
      final parsed = _parseAmountToDouble(prefix);
      if (parsed != null) {
        final scaled = _fmtSmart(parsed * mult);
        return a.replaceFirst(mPrefix.group(1)!, scaled).trim();
      }
    }

    final mNum = RegExp(r'^\s*([0-9]+(?:\.\d+)?)').firstMatch(a);
    if (mNum != null) {
      return a
          .replaceFirst(mNum.group(1)!, _fmtSmart(double.parse(mNum.group(1)!) * mult))
          .trim();
    }
    return a;
  }

  String _fmtSmart(double v) {
    if ((v - v.roundToDouble()).abs() < 0.0001) return v.round().toString();
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  String _fmtMultiplier(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? '${s.substring(0, s.length - 2)}x' : '${s}x';
  }

  Widget _heroBackButton({required Color color}) => InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(999),
        child: SvgPicture.asset(
          'assets/images/icons/back-chevron.svg',
          width: 28,
          height: 28,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      );

  Widget _heroStarIcon({required bool isFav, required Color color}) =>
      Icon(isFav ? Icons.star : Icons.star_border, size: 36, color: color);

  Widget _ingredientRow(Map row) {
    final amount = _amountForRow(row);
    final unit = _unitForRow(row);
    final name = (row['name'] ?? '').toString().trim();
    final notes = stripHtml((row['notes'] ?? '').toString()).trim();
    final amountUnit = [amount, unit].where((s) => s.isNotEmpty).join(' ');
    if (amountUnit.isEmpty && name.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: _RText.ingPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_RText.ingRadius),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: _RText.font),
          children: [
            if (amountUnit.isNotEmpty) ...[
              TextSpan(
                text: amountUnit,
                style: _RText.ingAmount.copyWith(color: _RText.ingAmount.color?.withOpacity(0.75)),
              ),
              const TextSpan(text: '  '),
            ],
            TextSpan(text: name, style: _RText.ingName),
            if (notes.isNotEmpty) ...[
              const TextSpan(text: ' '),
              TextSpan(
                text: '($notes)',
                style: _RText.ingNotes.copyWith(color: _RText.ingNotes.color?.withOpacity(0.70)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepCard({required int index, required String text}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFD9E6E5),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 18),
              child: Text('$index', style: _RText.instructionNumber),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Text(text, style: _RText.instructionText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipe = (_data?['recipe'] is Map)
        ? Map<String, dynamic>.from(_data!['recipe'] as Map)
        : null;

    final title =
        (_data?['title']?['rendered'] as String?) ?? (recipe?['name'] as String?) ?? 'Recipe';

    final imageUrl = (recipe?['image_url_full'] ??
            recipe?['image_url'] ??
            recipe?['image'] ??
            recipe?['thumbnail_url'])
        ?.toString();

    final heroUrl = upscaleJetpackImage(imageUrl, w: 1600, h: 900);

    final ingredientsFlat = (recipe?['ingredients_flat'] is List)
        ? (recipe!['ingredients_flat'] as List)
        : const [];

    final canConvert = _hasConvertedSystem2(ingredientsFlat);

    // ✅ Avoid mutating state inside build: if conversions disappear, snap back to metric.
    if (!canConvert && _unitSystem != 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _unitSystem = 1);
      });
    }

    final cleanSteps = (recipe?['instructions_flat'] as List? ?? [])
        .whereType<Map>()
        .map((s) => stripHtml((s['text'] ?? '').toString()))
        .where((t) => t.trim().isNotEmpty)
        .toList();

    const pageBg = Color(0xFFECF3F4);

    if (_loading) {
      return const Scaffold(backgroundColor: pageBg, body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: pageBg,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center, style: _RText.bodySoft),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => _load(forceRefresh: false), child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    const double heroHeight = 380.0;
    const double parallaxStrength = 0.1;
    final user = FirebaseAuth.instance.currentUser;

    final headerColor = _showStickyHeader ? const Color(0xFFECF3F4) : Colors.transparent;
    final iconColor = _showStickyHeader ? AppColors.brandDark : Colors.white;
    final headerShadow =
        _showStickyHeader ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))] : null;
    final statusBarStyle = _showStickyHeader ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: statusBarStyle,
      child: Scaffold(
        backgroundColor: pageBg,
        body: Stack(
          children: [
            Positioned(
              top: -(_scrollY * parallaxStrength),
              left: 0,
              right: 0,
              height: heroHeight,
              child: (imageUrl == null)
                  ? Container(color: const Color(0xFFEFEFEF))
                  : CachedNetworkImage(
                      imageUrl: (heroUrl ?? imageUrl),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      placeholder: (context, url) => Container(color: const Color(0xFFEFEFEF)),
                      errorWidget: (context, url, error) => Container(color: const Color(0xFFEFEFEF)),
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      httpHeaders: const {
                        'User-Agent': 'LittleVeganEatsApp/1.0',
                        'Accept': 'application/json',
                      },
                    ),
            ),
            ScrollConfiguration(
              behavior: const NoBounceScrollBehavior(),
              child: CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: heroHeight - 120)),
                  SliverToBoxAdapter(
                    child: Container(
                      color: Colors.transparent,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFECF3F4),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(28),
                            topRight: Radius.circular(28),
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5)),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title.toUpperCase(), style: _RText.h1),
                              const SizedBox(height: 12),
                              Text(
                                'Prep: ${recipe?['prep_time'] ?? '-'} mins  •  Cook: ${recipe?['cook_time'] ?? '-'} mins',
                                style: _RText.meta,
                              ),
                              const SizedBox(height: 20),
                              _servingPanelCard(context, recipe),
                              const SizedBox(height: 40),

                              Row(
                                children: [
                                  Expanded(child: Text('INGREDIENTS', style: _RText.section)),
                                  const SizedBox(width: 18),
                                  SizedBox(
                                    height: 38,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        textStyle: const TextStyle(
                                          inherit: false,
                                          fontFamily: 'Montserrat',
                                          fontSize: 14,
                                          fontVariations: [FontVariation('wght', 600)],
                                          letterSpacing: 0,
                                        ),
                                      ),
                                      onPressed: () {
                                        final u = FirebaseAuth.instance.currentUser;
                                        if (u == null) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Please sign in to use shopping lists')),
                                          );
                                          return;
                                        }

                                        final ingredients =
                                            _ingredientsToShoppingIngredients(ingredientsFlat);

                                        ShoppingListPickerSheet.open(
                                          context,
                                          recipeId: widget.id,
                                          recipeTitle: title,
                                          ingredients: ingredients,
                                        );
                                      },
                                      child: const Text('Add to shopping list'),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              _unitSystemToggle(show: canConvert, leftLabel: 'METRIC', rightLabel: 'US'),
                              const SizedBox(height: 2),

                              for (final row in ingredientsFlat)
                                if (row is Map && row['type'] == 'group')
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
                                    child: Text(
                                      (row['name'] ?? '').toString().trim(),
                                      style: _RText.title.copyWith(fontSize: 16),
                                    ),
                                  )
                                else if (row is Map)
                                  _ingredientRow(row),

                              _swapsCard(recipe),

                              const SizedBox(height: 40),
                              Text('INSTRUCTIONS', style: _RText.section),
                              const SizedBox(height: 12),
                              for (final entry in cleanSteps.asMap().entries)
                                _stepCard(index: entry.key + 1, text: entry.value),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.brandDark,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: cleanSteps.isEmpty
                                      ? null
                                      : () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => CookModeScreen(title: title, steps: cleanSteps),
                                            ),
                                          ),
                                  child: const Text('START COOKING', style: _RText.servingCta),
                                ),
                              ),

                              _servingSuggestionsCard(recipe),
                              _storageCard(recipe),

                              const SizedBox(height: 40),
                              _nutritionPanel(context, recipe),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: headerColor,
                  gradient: _showStickyHeader
                      ? null
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withOpacity(0.4), Colors.transparent],
                        ),
                  boxShadow: headerShadow,
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(
                      children: [
                        if (!_showStickyHeader)
                          _circleFrostButton(
                            onTap: () => Navigator.of(context).pop(),
                            child: _circleFrostIconWrapper(
                              child: SvgPicture.asset(
                                'assets/images/icons/back-chevron.svg',
                                width: 24,
                                height: 24,
                                fit: BoxFit.contain,
                                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                              ),
                            ),
                          )
                        else
                          _heroBackButton(color: iconColor),
                        const Spacer(),
                        if (user == null) ...[
                          if (!_showStickyHeader)
                            _circleFrostButton(
                              onTap: () {},
                              child: _circleFrostIconWrapper(
                                child: Icon(Icons.star_border, size: 26, color: Colors.white.withOpacity(0.9)),
                              ),
                            )
                          else
                            Icon(Icons.star_border, size: 36, color: iconColor.withOpacity(0.6)),
                        ] else ...[
                          StreamBuilder<bool>(
                            stream: FavoritesService.watchIsFavorite(widget.id),
                            builder: (context, snap) {
                              final isFav = snap.data == true;

                              Future<void> toggleFav() async {
                                final newState = await FavoritesService.toggleFavorite(
                                  recipeId: widget.id,
                                  title: title,
                                  imageUrl: imageUrl,
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(newState ? 'Saved to favourites' : 'Removed from favourites'),
                                  ),
                                );
                              }

                              if (!_showStickyHeader) {
                                return _circleFrostButton(
                                  onTap: toggleFav,
                                  child: _circleFrostIconWrapper(
                                    child: Icon(
                                      isFav ? Icons.star : Icons.star_border,
                                      size: 26,
                                      color: Colors.white.withOpacity(0.95),
                                    ),
                                  ),
                                );
                              }

                              return InkWell(
                                onTap: toggleFav,
                                child: _heroStarIcon(isFav: isFav, color: iconColor),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

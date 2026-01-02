// lib/recipes/recipe_detail_screen.dart
import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import '../utils/text.dart';
import '../utils/images.dart';
import '../recipes/recipe_repository.dart';
import '../recipes/serving_engine.dart';
import '../recipes/favorites_service.dart';
import 'cook_mode_screen.dart';
import '../app/no_bounce_scroll_behavior.dart';

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
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
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
    height: 1.1,
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

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  final ScrollController _scrollCtrl = ScrollController();
  double _scrollY = 0;

  @override
  void initState() {
    super.initState();
    _wireFamilyProfile();
    _load(forceRefresh: false);

    _scrollCtrl.addListener(() {
      if (!mounted) return;
      setState(() {
        _scrollY = _scrollCtrl.offset;
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _wireFamilyProfile() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _profileSub?.cancel();
      if (user == null) return;
      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      _profileSub = docRef.snapshots().listen((snap) {
        final data = snap.data();
        if (data == null) return;
        final adults = (data['adults'] as List?) ?? const [];
        final children = (data['children'] as List?) ?? const [];
        final adultCount =
            adults.where((e) => e is Map && (e['name'] ?? '').toString().trim().isNotEmpty).length;
        final kidCount =
            children.where((e) => e is Map && (e['name'] ?? '').toString().trim().isNotEmpty).length;
        final nextAdults = adultCount > 0 ? adultCount : 1;
        final nextKids = kidCount;
        if (!mounted) return;
        if (nextAdults != _profileAdults || nextKids != _profileKids) {
          setState(() {
            final prevProfileAdults = _profileAdults;
            final prevProfileKids = _profileKids;
            _profileAdults = nextAdults;
            _profileKids = nextKids;
            if (_adults == prevProfileAdults) _adults = _profileAdults;
            if (_kids == prevProfileKids) _kids = _profileKids;
          });
        }
      });
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

  // ===========================================================================
  // 🟢 WIDGETS
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

  Widget _swapsCard(Map<String, dynamic>? recipe) {
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
                          style: _RText.body.copyWith(
                            color: AppColors.brandDark,
                            fontWeight: FontWeight.w500,
                          ),
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
        _card(child: Text(text, style: _RText.body.copyWith(height: 1.25))),
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
        _card(child: Text(text, style: _RText.body.copyWith(height: 1.25))),
      ],
    );
  }

  // ===========================================================================

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

  // ✅ NEW: nicer labels for 0.5 batch
  String _multiplierLabel(double v) {
    if ((v - 0.5).abs() < 0.0001) return 'Half batch';
    return '${_fmtMultiplier(v)} batch';
  }

  String _ctaLabel(double v) {
    if ((v - 0.5).abs() < 0.0001) return 'MAKE HALF BATCH';
    return 'UPDATE INGREDIENTS (${_fmtMultiplier(v).toUpperCase()})';
  }

  Widget _servingPanelCard(BuildContext context, Map<String, dynamic>? recipe) {
    final advice = _safeAdvice(recipe);
    if (advice == null) return const SizedBox.shrink();

    final needsMore = advice.multiplierRaw > 1.0;
    final showHalf = advice.canHalf && !needsMore;

    final recommended = showHalf ? 0.5 : advice.recommendedMultiplier;
    final showRecommended = recommended != null && (needsMore || showHalf);
    final showHiddenSection = showRecommended || _scale != 1.0;

    final servingsRaw = (recipe?['servings'] ?? recipe?['servings_number'] ?? recipe?['servings_amount']);
    final servingsText = (servingsRaw == null) ? null : servingsRaw.toString().trim();

    final itemsPerPersonRaw = recipe?['items_per_person'];
    final itemsPerPerson = (itemsPerPersonRaw == null) ? null : itemsPerPersonRaw.toString().trim();
    final perPersonSuffix =
        (itemsPerPerson == null || itemsPerPerson.isEmpty) ? null : '($itemsPerPerson items per person)';

    final bannerHeadline = needsMore
        ? (advice.headline.isNotEmpty ? advice.headline : 'You may want to make more')
        : (showHalf ? "You'll have leftovers" : (advice.headline.isNotEmpty ? advice.headline : 'Perfect for your family'));

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (servingsText != null && servingsText.isNotEmpty) ...[
            Text('This recipe makes $servingsText', style: _RText.servingTop),
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
                Expanded(
                  child: Text(
                    bannerHeadline,
                    style: _RText.servingBanner,
                  ),
                ),
              ],
            ),
          ),

          

          const SizedBox(height: 20),
          Divider(color: Colors.black.withOpacity(0.08), height: 1),
          const SizedBox(height: 20),
          Text(
            advice.detailLine.trim().isNotEmpty ? advice.detailLine : 'Your family needs more',
            style: _RText.servingMid,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _peopleStepperCard(
                  label: 'Adults',
                  value: _adults,
                  onChanged: (v) => setState(() => _adults = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _peopleStepperCard(
                  label: 'Children',
                  value: _kids,
                  onChanged: (v) => setState(() => _kids = v),
                ),
              ),
            ],
          ),

          if (showHiddenSection) ...[
            const SizedBox(height: 20),
            Divider(color: Colors.black.withOpacity(0.08), height: 1),
            const SizedBox(height: 20),
          ],

          if (showRecommended) ...[
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _applyScale(recommended!),
                child: Text(
                  _ctaLabel(recommended!),
                  style: _RText.servingCta,
                ),
              ),
            ),
          ] else if (_scale != 1.0) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _applyScale(1.0),
                child: const Text('RESET INGREDIENTS', style: _RText.servingCta),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ESTIMATED NUTRITION', style: _RText.section),
        const SizedBox(height: 12),
        Text('Based on one serving', style: _RText.chip),
        const SizedBox(height: 12),
        _card(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: SizedBox()),
                  SizedBox(width: 86, child: Text('Adult', textAlign: TextAlign.right, style: _RText.chip)),
                  const SizedBox(width: 12),
                  SizedBox(width: 86, child: Text('Child', textAlign: TextAlign.right, style: _RText.chip)),
                ],
              ),
              const SizedBox(height: 8),
              Divider(height: 1, thickness: 1, color: Colors.black.withOpacity(0.06)),
              const SizedBox(height: 8),
              for (int i = 0; i < rows.length; i++)
                if (rows[i]['v'] != null)
                  Builder(builder: (context) {
                    final r = rows[i];
                    final isSub = r['sub'] == true;
                    bool nextIsSub = false;
                    bool nextExists = false;
                    for (int j = i + 1; j < rows.length; j++) {
                      if (rows[j]['v'] == null) continue;
                      nextExists = true;
                      nextIsSub = rows[j]['sub'] == true;
                      break;
                    }
                    final showDivider = isSub || !nextIsSub;
                    return Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 4, bottom: isSub ? 4 : 4, left: isSub ? 16 : 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isSub ? ' - ${r['l']}' : r['l'] as String,
                                  style: isSub
                                      ? _RText.bodySoft.copyWith(fontWeight: FontWeight.w500, fontSize: 14)
                                      : _RText.bodySoft.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 86,
                                child: Text(
                                  _scaleNutritionString(r['v'], 1.0),
                                  textAlign: TextAlign.right,
                                  style: isSub
                                      ? _RText.body.copyWith(fontWeight: FontWeight.w500, fontSize: 14)
                                      : _RText.body.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 86,
                                child: Text(
                                  _scaleNutritionString(r['v'], 0.5),
                                  textAlign: TextAlign.right,
                                  style: isSub
                                      ? _RText.body.copyWith(fontWeight: FontWeight.w500, fontSize: 14)
                                      : _RText.body.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showDivider && nextExists) ...[
                          const SizedBox(height: 6),
                          Divider(height: 1, thickness: 1, color: Colors.black.withOpacity(0.06)),
                          const SizedBox(height: 6),
                        ],
                      ],
                    );
                  }),
              const SizedBox(height: 8),
              Divider(height: 1, thickness: 1, color: Colors.black.withOpacity(0.06)),
              const SizedBox(height: 20),
              Text('Child values are estimated at 0.5 adult serving', style: _RText.chip),
            ],
          ),
        ),
      ],
    );
  }

  String _scaledAmount(String rawAmount, double mult) {
    final a = rawAmount.trim();
    if (a.isEmpty || mult == 1.0) return a;
    final mX =
        RegExp(r'^\s*([0-9]+(?:\.\d+)?)(\s*x\s*)$', caseSensitive: false).firstMatch(a);
    if (mX != null) return '${_fmtSmart(double.parse(mX.group(1)!) * mult)} x';
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

  Widget _heroBackButton() => InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(999),
        child: SvgPicture.asset(
          'assets/images/icons/back-chevron.svg',
          width: 28,
          height: 28,
          fit: BoxFit.contain,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );

  Widget _heroStarIcon({required bool isFav}) =>
      Icon(isFav ? Icons.star : Icons.star_border, size: 36, color: Colors.white);

  Widget _ingredientRow(Map row) {
    final amount = _scaledAmount((row['amount'] ?? '').toString(), _scale);
    final unit = (row['unit'] ?? '').toString().trim();
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
              const TextSpan(text: '  ')
            ],
            TextSpan(text: name, style: _RText.ingName),
            if (notes.isNotEmpty) ...[
              const TextSpan(text: ' '),
              TextSpan(
                text: '($notes)',
                style: _RText.ingNotes.copyWith(color: _RText.ingNotes.color?.withOpacity(0.70)),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _stepCard({required int index, required String text}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFD9E6E5),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
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
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipe =
        (_data?['recipe'] is Map) ? Map<String, dynamic>.from(_data!['recipe'] as Map) : null;
    final title = (_data?['title']?['rendered'] as String?) ??
        (recipe?['name'] as String?) ??
        'Recipe';
    final imageUrl = (recipe?['image_url_full'] ??
            recipe?['image_url'] ??
            recipe?['image'] ??
            recipe?['thumbnail_url'])
        ?.toString();
    final heroUrl = upscaleJetpackImage(imageUrl, w: 1600, h: 900);
    final ingredientsFlat =
        (recipe?['ingredients_flat'] is List) ? (recipe!['ingredients_flat'] as List) : const [];
    final cleanSteps = (recipe?['instructions_flat'] as List? ?? [])
        .whereType<Map>()
        .map((s) => stripHtml((s['text'] ?? '').toString()))
        .where((t) => t.trim().isNotEmpty)
        .toList();

    const pageBg = Color(0xFFECF3F4);
    if (_loading) {
      return const Scaffold(
        backgroundColor: pageBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: pageBg,
        body: SafeArea(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, textAlign: TextAlign.center, style: _RText.bodySoft),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => _load(forceRefresh: false), child: const Text('Retry')),
            ]),
          ),
        ),
      );
    }

    const double heroHeight = 380.0;
    const double parallaxStrength = 0.1;
    final user = FirebaseAuth.instance.currentUser;

    return ScrollConfiguration(
      behavior: const NoBounceScrollBehavior(),
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
                  ? Container(
                      color: const Color(0xFFEFEFEF),
                      child: const Icon(Icons.image_outlined),
                    )
                  : Image.network(
                      heroUrl ?? imageUrl,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
            ),
            CustomScrollView(
              controller: _scrollCtrl,
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.4), Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: Row(
                          children: [
                            _heroBackButton(),
                            const Spacer(),
                            if (user == null)
                              const Icon(Icons.star_border, size: 36, color: Color(0xCCFFFFFF))
                            else
                              StreamBuilder<bool>(
                                stream: FavoritesService.watchIsFavorite(widget.id),
                                builder: (context, snap) {
                                  final isFav = snap.data == true;
                                  return InkWell(
                                    onTap: () async {
                                      final newState = await FavoritesService.toggleFavorite(
                                        recipeId: widget.id,
                                        title: title,
                                        imageUrl: imageUrl,
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            newState ? 'Saved to favourites' : 'Removed from favourites',
                                          ),
                                        ),
                                      );
                                    },
                                    child: _heroStarIcon(isFav: isFav),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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
                            Text('INGREDIENTS', style: _RText.section),
                            const SizedBox(height: 12),
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
          ],
        ),
      ),
    );
  }
}

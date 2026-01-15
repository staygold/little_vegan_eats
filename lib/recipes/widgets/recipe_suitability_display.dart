import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

enum RecipeSuitabilityVariant {
  card, // default: keep existing card styling EXACTLY
  detail, // opt-in: slightly bigger for detail screen
}

class RecipeSuitabilityDisplay extends StatelessWidget {
  const RecipeSuitabilityDisplay({
    super.key,
    this.tags = const [],
    this.allergyStatus,
    this.ageWarning,
    this.childNames = const [],

    /// ✅ Adults + kids (for “Safe for [name]” fallback)
    this.householdNames = const [],

    this.variant = RecipeSuitabilityVariant.card, // ✅ default preserves cards
  });

  final List<String> tags;
  final String? allergyStatus;
  final String? ageWarning;
  final List<String> childNames;
  final List<String> householdNames;

  final RecipeSuitabilityVariant variant;

  // ---------------------------------------------------------------------------
  // STYLE TOKENS (card = current, detail = slightly bigger/roomier)
  // ---------------------------------------------------------------------------
  bool get _isDetail => variant == RecipeSuitabilityVariant.detail;

  double get _iconSize => _isDetail ? 16 : 14;
  double get _textSize => _isDetail ? 13 : 12;
  double get _lineHeight => _isDetail ? 1.35 : 1.3;

  double get _chipFontSize => _isDetail ? 11 : 10;
  EdgeInsets get _chipPadding => _isDetail
      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
      : const EdgeInsets.symmetric(horizontal: 6, vertical: 2);

  double get _chipSpacing => _isDetail ? 6 : 4;
  double get _chipRunSpacing => _isDetail ? 6 : 4;

  double get _rowIconGap => _isDetail ? 6 : 4;

  int get _maxLines => _isDetail ? 2 : 1;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    final bool hasChildren = childNames.isNotEmpty;

    // -----------------------------------------------------------------------
    // 1) AGE TAG CHIPS (only if kids exist)
    // -----------------------------------------------------------------------
    if (hasChildren) {
      final visibleTags = tags.where((t) {
        final s = t.toLowerCase();
        return RegExp(r'\d+\s*[mMyY]|first\s*foods?|first|food',
                caseSensitive: false)
            .hasMatch(s);
      }).take(2).toList();

      if (visibleTags.isNotEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(
            spacing: _chipSpacing,
            runSpacing: _chipRunSpacing,
            children: visibleTags.map((t) => _buildTagChip(context, t)).toList(),
          ),
        ));
      }
    }

    // -----------------------------------------------------------------------
    // 2) ALLERGY STATUS ROW
    //    ✅ If it comes through as plain "safe", rewrite to "Safe for [names]"
    // -----------------------------------------------------------------------
    final String? allergyText = _normaliseAllergyText();
    if (allergyText != null && allergyText.isNotEmpty) {
      final s = allergyText.toLowerCase();
      final isSwap = s.contains('swap');
      final isUnsafe = s.contains('contains') || s.contains('not suitable');

      IconData icon = Icons.check_circle;
      Color color = Colors.green;

      if (isSwap) {
        icon = Icons.published_with_changes;
        color = Colors.amber;
      } else if (isUnsafe) {
        icon = Icons.cancel;
        color = Colors.red;
      } else {
        icon = Icons.grain; // distinct for allergy-safe
        color = Colors.green;
      }

      rows.add(_buildIconText(
        context,
        icon,
        color,
        allergyText,
        isWarning: isSwap || isUnsafe,
      ));
    }

    // -----------------------------------------------------------------------
    // 3) AGE STATUS ROW (only if kids exist)
    // -----------------------------------------------------------------------
    if (hasChildren) {
      if (rows.isNotEmpty && allergyText != null) {
        rows.add(const SizedBox(height: 2));
      }

      if (ageWarning != null && ageWarning!.isNotEmpty) {
        rows.add(_buildIconText(
          context,
          Icons.child_care,
          Colors.amber,
          ageWarning!,
          isWarning: true,
        ));
      } else {
        // ✅ If you have kids and no warning, we show positive child line
        final nameText = childNames.isNotEmpty
            ? 'Suitable for ${_formatChildNames()}'
            : 'Suitable for children';

        rows.add(_buildIconText(
          context,
          Icons.child_care,
          Colors.green,
          nameText,
        ));
      }
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  // If allergyStatus comes through as "safe"/"Safe", rewrite using householdNames.
  String? _normaliseAllergyText() {
    final raw = allergyStatus?.trim();
    if (raw == null || raw.isEmpty) return null;

    final lower = raw.toLowerCase();

    final isBareSafe = lower == 'safe' || lower == 'safe.' || lower == 'safe!';
    if (!isBareSafe) return raw;

    final who = _formatHouseholdNames();
    if (who == null || who.isEmpty) return 'Safe';

    return 'Safe for $who';
  }

  String _formatChildNames() {
    final names = childNames.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (names.isEmpty) return "children";
    if (names.length == 1) return names.first;
    if (names.length == 2) return "${names[0]} & ${names[1]}";
    final last = names.last;
    final others = names.sublist(0, names.length - 1).join(', ');
    return "$others & $last";
  }

  String? _formatHouseholdNames() {
    final names =
        householdNames.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (names.isEmpty) return null;
    if (names.length == 1) return names.first;
    if (names.length == 2) return "${names[0]} & ${names[1]}";
    final last = names.last;
    final others = names.sublist(0, names.length - 1).join(', ');
    return "$others & $last";
  }

  Widget _buildTagChip(BuildContext context, String label) {
    return Container(
      padding: _chipPadding,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: _chipFontSize,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary.withOpacity(0.7),
        ),
      ),
    );
  }

  Widget _buildIconText(
    BuildContext context,
    IconData icon,
    Color color,
    String text, {
    bool isWarning = false,
  }) {
    return RichText(
      maxLines: _maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
              fontSize: _textSize,
              fontWeight: FontWeight.w500,
              height: _lineHeight,
            ),
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: _rowIconGap),
              child: Icon(icon, size: _iconSize, color: color),
            ),
          ),
          TextSpan(
            text: text,
            style: isWarning ? TextStyle(color: AppColors.textPrimary) : null,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class RecipeSuitabilityDisplay extends StatelessWidget {
  const RecipeSuitabilityDisplay({
    super.key,
    this.tags = const [],
    this.allergyStatus,
    this.ageWarning,
    this.childNames = const [],
  });

  final List<String> tags;
  final String? allergyStatus;
  final String? ageWarning;
  final List<String> childNames;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    // 1. AGE TAG CHIPS (e.g. 6m+)
    final visibleTags = tags.where((t) {
      final s = t.toLowerCase();
      return RegExp(r'\d+[mMyY]|first|food', caseSensitive: false).hasMatch(s);
    }).take(2).toList();

    if (visibleTags.isNotEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: visibleTags.map((t) => _buildTagChip(context, t)).toList(),
        ),
      ));
    }

    // 2. ALLERGY STATUS ROW
    if (allergyStatus != null && allergyStatus!.isNotEmpty) {
      final s = allergyStatus!.toLowerCase();
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
        icon = Icons.grain; // Distinct icon for allergy safe
      }

      rows.add(_buildIconText(
        context,
        icon,
        color,
        allergyStatus!,
        isWarning: isSwap || isUnsafe,
      ));
    }

    // 3. AGE STATUS ROW (Updated Logic)
    // Always add spacing if we had an allergy row
    if (rows.isNotEmpty && allergyStatus != null) {
      rows.add(const SizedBox(height: 2));
    }

    if (ageWarning != null && ageWarning!.isNotEmpty) {
      // ⚠️ Negative Warning (Always show)
      rows.add(_buildIconText(
        context,
        Icons.child_care,
        Colors.amber,
        ageWarning!,
        isWarning: true,
      ));
    } else {
      // ✅ Positive Affirmation (Always show)
      // Fallback to "Suitable for children" if names aren't provided
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

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  String _formatChildNames() {
    if (childNames.isEmpty) return "children";
    if (childNames.length == 1) return childNames.first;
    if (childNames.length == 2) return "${childNames[0]} & ${childNames[1]}";
    final last = childNames.last;
    final others = childNames.sublist(0, childNames.length - 1).join(', ');
    return "$others & $last";
  }

  Widget _buildTagChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary.withOpacity(0.7),
        ),
      ),
    );
  }

  Widget _buildIconText(BuildContext context, IconData icon, Color color, String text, {bool isWarning = false}) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.3, 
        ),
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(icon, size: 14, color: color),
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
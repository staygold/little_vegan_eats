import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    this.autofocus = false,

    // layout
    this.height = 60,
    this.horizontalPadding = 16,

    // typography
    this.fontSize = 16,
    this.fontWeightValue = 600, // semi-bold
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;

  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  final bool autofocus;
  final double height;
  final double horizontalPadding;

  final double fontSize;
  final double fontWeightValue;

  @override
  Widget build(BuildContext context) {
    const iconColor = Color.fromRGBO(4, 66, 70, 0.6); // #044246 @ 60%

    final hasText = controller.text.trim().isNotEmpty;

    final textStyle = TextStyle(
      fontFamily: 'Montserrat',
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      fontVariations: [FontVariation('wght', fontWeightValue)],
      height: 1.0,
      letterSpacing: 0,
      color: AppColors.brandDark,
    );

    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          // ✅ SEARCH ICON — NOW ON THE LEFT
          const Icon(
            Icons.search,
            size: 28,
            color: iconColor,
          ),

          const SizedBox(width: 8),

          // ✅ TEXT FIELD
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: textStyle,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: textStyle,
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          // ✅ CLEAR BUTTON STAYS ON RIGHT
          if (hasText)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
                onClear();
              },
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Icon(
                  Icons.close,
                  size: 20,
                  color: iconColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

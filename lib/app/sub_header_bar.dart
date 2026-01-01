import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SubHeaderBar extends StatelessWidget {
  const SubHeaderBar({
    super.key,
    required this.title,
    this.onBack,
    this.backgroundColor = const Color(0xFFEAF3F1),
    this.padding = const EdgeInsets.fromLTRB(16, 24, 16, 16),
  });

  final String title;
  final VoidCallback? onBack;
  final Color backgroundColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      padding: padding, // ✅ page padding only
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ✅ Icon sits directly on the left padding
          InkWell(
            onTap: onBack ?? () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(999),
            child: SvgPicture.asset(
              'assets/images/icons/back-chevron.svg',
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(
                Color(0xFF005A4F),
                BlendMode.srcIn,
              ),
            ),
          ),

          const SizedBox(width: 16), // gap between icon + title (as before)

          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                fontVariations: [FontVariation('wght', 800)],
                height: 1.0,
                letterSpacing: 0.0,
                color: Color(0xFF005A4F),
              ),
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

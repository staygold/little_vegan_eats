import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SubHeaderBar extends StatelessWidget {
  const SubHeaderBar({
    super.key,
    required this.title,
    this.onBack,
    this.backgroundColor = const Color(0xFFEAF3F1),
  });

  final String title;
  final VoidCallback? onBack;
  final Color backgroundColor;

  void _goBack(BuildContext context) {
    final cb = onBack ?? () => Navigator.of(context).pop();
    cb();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Material(
        color: backgroundColor,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 12),
          child: SizedBox(
            height: 44, // consistent bar height
            child: InkWell(
              onTap: () => _goBack(context),

              // ✅ now the tap target is the actual visible content width
              borderRadius: BorderRadius.circular(12),
              splashFactory: NoSplash.splashFactory,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,

              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/images/icons/back-chevron.svg',
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF005A4F),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // ✅ title stays visible, row is still fully tappable
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // REQUIRED for status bar styling
import 'package:flutter_svg/flutter_svg.dart';

class TopHeaderBar extends StatelessWidget {
  final VoidCallback onFamilyTap;

  const TopHeaderBar({
    super.key,
    required this.onFamilyTap,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    const bg = Color(0xFF005A4F);
    const pillBg = Colors.white;
    const pillText = Color(0xFF044246);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status bar icons (iOS)
      value: SystemUiOverlayStyle.light,
      child: Container(
        color: bg,
        height: topInset + 68,
        padding: EdgeInsets.fromLTRB(16, topInset + 10, 16, 12),
        child: Row(
          children: [
            // LVE logo
            SvgPicture.asset(
              'assets/images/LVE.svg',
              height: 44,
              fit: BoxFit.contain,
              placeholderBuilder: (_) =>
                  const SizedBox(height: 44, width: 44),
            ),

            const Spacer(),

            // Family pill
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onFamilyTap,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.10),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Family',
                      style: TextStyle(
                        color: pillText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SvgPicture.asset(
                      'assets/images/icons/family.svg',
                      width: 18,
                      height: 18,
                      colorFilter: const ColorFilter.mode(
                        pillText,
                        BlendMode.srcIn,
                      ),
                      placeholderBuilder: (_) =>
                          const SizedBox(width: 18, height: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

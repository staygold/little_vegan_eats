import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TopHeaderBar extends StatelessWidget {
  const TopHeaderBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.only(left: 20, right: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2F3).withOpacity(0.9),
      ),
      alignment: Alignment.centerLeft,
      child: SvgPicture.asset(
        'assets/images/LVE.svg',
        height: 44,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const SizedBox(
          height: 44,
          width: 44,
        ),
      ),
    );
  }
}

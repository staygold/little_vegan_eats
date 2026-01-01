// lib/app/no_bounce_scroll_behavior.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class NoBounceScrollBehavior extends MaterialScrollBehavior {
  const NoBounceScrollBehavior();

  // ✅ apply clamping everywhere (kills bounce/rubber-band)
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  // ✅ important for macOS (trackpad/mouse) to ensure consistent behavior
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };

  // ✅ remove glow/indicator too (harmless on iOS/macOS)
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  // optional: if you also want no scrollbars anywhere
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

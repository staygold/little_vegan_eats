// lib/utils/text.dart
import 'package:html/parser.dart' as html_parser;

/// Canonical text normaliser for all WP / CMS strings.
///
/// - Decodes HTML entities (&#038;, &amp;, &nbsp; etc)
/// - Strips HTML tags
/// - Collapses non-breaking spaces
/// - Safe to call multiple times
String stripHtml(String input) {
  if (input.isEmpty) return input;

  // parseFragment decodes entities + strips tags
  final decoded = html_parser.parseFragment(input).text ?? '';

  // normalise spacing
  return decoded.replaceAll('\u00A0', ' ').trim();
}

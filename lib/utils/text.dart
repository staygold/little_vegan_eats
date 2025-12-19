import 'package:html/parser.dart' as html_parser;

String stripHtml(String input) {
  final first = html_parser.parseFragment(input).text ?? '';
  final second = html_parser.parseFragment(first).text ?? '';
  final cleaned = second.replaceAll(RegExp(r'<[^>]*>'), '');
  return cleaned.replaceAll('\u00A0', ' ').trim();
}

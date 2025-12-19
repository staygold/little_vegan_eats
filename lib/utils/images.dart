String? upscaleJetpackImage(String? url, {int w = 1200, int h = 675}) {
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  final qp = Map<String, String>.from(uri.queryParameters);
  qp['fit'] = '$w,$h'; // Jetpack i0.wp.com uses fit=W,H
  return uri.replace(queryParameters: qp).toString();
}

String fallbackFromJetpack(String url) {
  const prefix = 'https://i0.wp.com/';
  if (!url.startsWith(prefix)) return url;

  final rest = url.substring(prefix.length); // "littleveganeats.co/..."
  final slash = rest.indexOf('/');
  if (slash == -1) return url;

  final pathAndQuery = rest.substring(slash);
  return 'https://littleveganeats.co$pathAndQuery';
}
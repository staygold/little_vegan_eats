// lib/resources/resource.dart
class Resource {
  final int id;
  final String slug;
  final String title;
  final String excerptHtml;
  final String contentHtml;
  final int featuredMedia;
  final DateTime modified;

  // ✅ ACF payload
  final Map<String, dynamic> acf;

  Resource({
    required this.id,
    required this.slug,
    required this.title,
    required this.excerptHtml,
    required this.contentHtml,
    required this.featuredMedia,
    required this.modified,
    required this.acf,
  });

  factory Resource.fromJson(Map<String, dynamic> json) {
    final acfRaw = json['acf'];

    return Resource(
      id: (json['id'] ?? 0) as int,
      slug: (json['slug'] ?? '') as String,
      title: (json['title']?['rendered'] ?? '') as String,
      excerptHtml: (json['excerpt']?['rendered'] ?? '') as String,
      contentHtml: (json['content']?['rendered'] ?? '') as String,
      featuredMedia: (json['featured_media'] ?? 0) as int,
      modified: DateTime.tryParse((json['modified'] ?? '') as String) ??
          DateTime.fromMillisecondsSinceEpoch(0),

      // ✅ robust: handles Map, {}, null, []
      acf: (acfRaw is Map)
          ? (acfRaw as Map).cast<String, dynamic>()
          : <String, dynamic>{},
    );
  }
}

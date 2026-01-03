import 'package:dio/dio.dart';

class ResourcesApi {
  final Dio dio;

  ResourcesApi({Dio? dio})
      : dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  static const _fields =
      'id,slug,title,excerpt,content,featured_media,modified,acf';

  Future<List<Map<String, dynamic>>> fetchResources({
    int perPage = 50,
    int page = 1,
  }) async {
    final res = await dio.get(
      'https://littleveganeats.co/wp-json/wp/v2/resource',
      queryParameters: {
        'per_page': perPage,
        'page': page,
        '_fields': _fields,
      },
      options: Options(
        headers: {
          'Accept': 'application/json',
        },
      ),
    );

    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchResource(int id) async {
    final res = await dio.get(
      'https://littleveganeats.co/wp-json/wp/v2/resource/$id',
      queryParameters: {
        '_fields': _fields,
      },
      options: Options(
        headers: {
          'Accept': 'application/json',
        },
      ),
    );

    return (res.data as Map).cast<String, dynamic>();
  }
}

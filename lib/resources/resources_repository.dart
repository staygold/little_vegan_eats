import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import 'resource.dart';
import 'resources_api.dart';

class ResourcesRepository {
  static const _boxName = 'resources_cache_v1';
  static const _keyList = 'list_json';
  static const _keyLastSync = 'last_sync_ms';

  final ResourcesApi api;

  ResourcesRepository({ResourcesApi? api}) : api = api ?? ResourcesApi();

  Future<Box> _box() => Hive.openBox(_boxName);

  Future<List<Resource>> getResources({
    bool forceRefresh = false,
    Duration maxAge = const Duration(hours: 12),
    int perPage = 50,
    int maxPages = 5, // safety: 5 * 50 = 250 resources max
  }) async {
    final box = await _box();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastSyncMs = (box.get(_keyLastSync) as int?) ?? 0;

    final isStale = nowMs - lastSyncMs > maxAge.inMilliseconds;
    final hasCache = box.get(_keyList) != null;

    if (!forceRefresh && hasCache && !isStale) {
      final cached = box.get(_keyList) as String;
      final raw = (jsonDecode(cached) as List).cast<Map<String, dynamic>>();
      final items = raw.map(Resource.fromJson).toList();
      items.sort((a, b) => b.modified.compareTo(a.modified));
      return items;
    }

    // ✅ Fetch pages until we run out (or hit maxPages)
    final List<Map<String, dynamic>> all = [];
    for (var page = 1; page <= maxPages; page++) {
      final batch = await api.fetchResources(perPage: perPage, page: page);

      all.addAll(batch);

      // if returned less than perPage, we're done
      if (batch.length < perPage) break;
    }

    await box.put(_keyList, jsonEncode(all));
    await box.put(_keyLastSync, nowMs);

    final items = all.map(Resource.fromJson).toList();
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  }

  /// Optional: handy for debugging / admin actions
  Future<void> clearCache() async {
    final box = await _box();
    await box.delete(_keyList);
    await box.delete(_keyLastSync);
  }

  /// Optional: safe error message extraction
  static String describeError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      return code != null ? 'Network error ($code)' : 'Network error';
    }
    return 'Something went wrong';
  }
}

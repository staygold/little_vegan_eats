import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'recipe_cache.dart';

class RecipeRepository {
  RecipeRepository._();

  static final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'LittleVeganEatsApp/1.0',
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static const int _perPage = 50;

  /// ✅ “More instant on open”
  /// - We still load cache instantly
  /// - But we will run a lightweight staleness check at most once per minute
  static const Duration _minCheckInterval = Duration(minutes: 1);

  /// Prevent multiple refreshes running at once (e.g. multiple screens)
  static Future<void>? _refreshInFlight;

  /// Stored alongside the cached recipes in the same Hive box.
  static const String _boxName = 'recipe_cache_box';
  static const String _keyLastCheckedAtMs = 'recipes_last_checked_at_ms';
  static const String _keyLatestModified = 'recipes_latest_modified';

  /// Loads cached recipes instantly.
  /// - If cache exists, returns immediately.
  /// - Optionally refreshes in background (throttled).
  /// - If no cache, fetches everything and caches it.
  ///
  /// ✅ Pull-to-refresh should use:
  /// ensureRecipesLoaded(backgroundRefresh: false, forceRefresh: true)
  static Future<List<Map<String, dynamic>>> ensureRecipesLoaded({
    bool backgroundRefresh = true,
    bool forceRefresh = false,
  }) async {
    final cached = await RecipeCache.load();

    if (cached.isNotEmpty) {
      if (backgroundRefresh) {
        // Don't block boot; refresh quietly.
        unawaited(_refreshIfStale(
          cachedLength: cached.length,
          force: forceRefresh,
        ));
        return cached;
      } else {
        await _refreshIfStale(
          cachedLength: cached.length,
          force: forceRefresh,
        );
        final updated = await RecipeCache.load();
        return updated.isNotEmpty ? updated : cached;
      }
    }

    // Cache empty -> fetch everything (blocking) and save.
    final fresh = await fetchAllRecipesFromWp();
    if (fresh.isNotEmpty) {
      await RecipeCache.save(fresh);

      final latest = _latestModifiedFromList(fresh);
      if (latest != null) {
        await _writeLatestModified(latest);
      }
      await _writeLastCheckedAt(DateTime.now());
    }
    return fresh;
  }

  /// Stale detection:
  /// - Uses count mismatch OR latest modified mismatch.
  /// - Throttled so we don’t check too often (unless force=true).
  static Future<void> _refreshIfStale({
    required int cachedLength,
    bool force = false,
  }) async {
    // If already refreshing, wait for the same in-flight refresh.
    if (_refreshInFlight != null) return _refreshInFlight!;

    _refreshInFlight = () async {
      try {
        if (!force) {
          final lastChecked = await _readLastCheckedAt();
          if (lastChecked != null) {
            final age = DateTime.now().difference(lastChecked);
            if (age < _minCheckInterval) return;
          }
        }

        // Lightweight check (1 item):
        final signal = await _fetchStalenessSignal();
        if (signal == null) return;

        final cachedLatestModified = await _readLatestModified();

        final countChanged =
            (signal.total != null && signal.total != cachedLength);

        final modifiedChanged = (signal.latestModified != null &&
            cachedLatestModified != null &&
            signal.latestModified != cachedLatestModified);

        // If we don't have a baseline yet, establish it once.
        final needBaselineModified =
            (cachedLatestModified == null && signal.latestModified != null);

        if (force || countChanged || modifiedChanged || needBaselineModified) {
          final fresh = await fetchAllRecipesFromWp();
          if (fresh.isNotEmpty) {
            await RecipeCache.save(fresh);

            final latest = _latestModifiedFromList(fresh) ?? signal.latestModified;
            if (latest != null) {
              await _writeLatestModified(latest);
            }
          } else {
            // If the refresh returns empty, keep existing cache.
          }
        } else {
          // No refresh needed; still update baseline if missing.
          if (cachedLatestModified == null && signal.latestModified != null) {
            await _writeLatestModified(signal.latestModified!);
          }
        }

        await _writeLastCheckedAt(DateTime.now());
      } catch (_) {
        // Network error: keep cache.
      } finally {
        _refreshInFlight = null;
      }
    }();

    return _refreshInFlight!;
  }

  /// Fetch minimal staleness signal:
  /// - x-wp-total header (count)
  /// - latest modified (by requesting most recently modified recipe if supported)
  static Future<_StalenessSignal?> _fetchStalenessSignal() async {
    try {
      final res = await _dio.get(
        'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe',
        queryParameters: {
          'per_page': 1,
          'page': 1,
          // Try to get most recently modified item first:
          'orderby': 'modified',
          'order': 'desc',
          // Reduce payload if supported (safe if ignored):
          '_fields': 'id,modified',
        },
      );

      final totalStr = res.headers.value('x-wp-total');
      final total = int.tryParse(totalStr ?? '');

      String? latestModified;
      final data = res.data;
      if (data is List && data.isNotEmpty && data.first is Map) {
        final m = (data.first as Map)['modified'];
        if (m is String && m.trim().isNotEmpty) {
          latestModified = m.trim();
        }
      }

      if (total == null && latestModified == null) return null;

      return _StalenessSignal(total: total, latestModified: latestModified);
    } catch (_) {
      return null;
    }
  }

  /// Full download of all recipes (paged)
  static Future<List<Map<String, dynamic>>> fetchAllRecipesFromWp() async {
    final out = <Map<String, dynamic>>[];

    int page = 1;
    int? totalPages;

    while (true) {
      try {
        final res = await _dio.get(
          'https://littleveganeats.co/wp-json/wp/v2/wprm_recipe',
          queryParameters: {
            'per_page': _perPage,
            'page': page,
            // If supported and desired:
            // 'status': 'publish',
          },
        );

        totalPages ??= int.tryParse(res.headers.value('x-wp-totalpages') ?? '');

        final data = res.data;
        if (data is! List) break;

        for (final item in data) {
          if (item is Map) {
            out.add(Map<String, dynamic>.from(item));
          }
        }

        if (totalPages != null) {
          if (page >= totalPages) break;
        } else {
          // Fallback if headers are missing:
          if (data.length < _perPage) break;
        }

        page += 1;
      } on DioException catch (e) {
        // WP returns 400 when page is out of range.
        final code = e.response?.statusCode;
        if (code == 400) break;
        rethrow;
      }
    }

    return out;
  }

  // ----------------------------
  // Metadata helpers
  // ----------------------------

  static String? _latestModifiedFromList(List<Map<String, dynamic>> list) {
    // ISO timestamps sort lexicographically.
    String? maxIso;
    for (final r in list) {
      final m = r['modified'];
      if (m is! String || m.trim().isEmpty) continue;
      final iso = m.trim();
      if (maxIso == null || iso.compareTo(maxIso) > 0) {
        maxIso = iso;
      }
    }
    return maxIso;
  }

  static Future<Box<dynamic>> _metaBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox<dynamic>(_boxName);
    }
    return Hive.box<dynamic>(_boxName);
  }

  static Future<void> _writeLastCheckedAt(DateTime dt) async {
    final box = await _metaBox();
    await box.put(_keyLastCheckedAtMs, dt.millisecondsSinceEpoch);
  }

  static Future<DateTime?> _readLastCheckedAt() async {
    final box = await _metaBox();
    final v = box.get(_keyLastCheckedAtMs);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  static Future<void> _writeLatestModified(String iso) async {
    final box = await _metaBox();
    await box.put(_keyLatestModified, iso);
  }

  static Future<String?> _readLatestModified() async {
    final box = await _metaBox();
    final v = box.get(_keyLatestModified);
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }
}

class _StalenessSignal {
  final int? total;
  final String? latestModified;

  _StalenessSignal({
    required this.total,
    required this.latestModified,
  });
}

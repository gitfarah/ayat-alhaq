import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage/mushaf_storage.dart';

/// A single ayah's tappable hit-region on a Mushaf page, in the SVG's
/// own coordinate space (viewBox units — the caller scales these
/// against the rendered SvgPicture's actual on-screen size).
class AyahHitRegion {
  final int surahNumber;
  final int ayahNumber;
  final double x;
  final double y;

  /// The polygon split into its closed sub-rings. The dataset writes
  /// one sub-rectangle per text LINE the ayah occupies
  /// ("M ... Z M ... Z"), so a multi-line ayah is several disjoint
  /// rings — treating all points as one ring would produce a bogus
  /// shape bridging the lines.
  final List<List<double>> rings;

  AyahHitRegion({
    required this.surahNumber,
    required this.ayahNumber,
    required this.x,
    required this.y,
    required this.rings,
  });

  factory AyahHitRegion.fromJson(Map<String, dynamic> json) {
    // Polygon may come as raw points ("x1,y1 x2,y2 ...") or as an SVG
    // path string ("M x y L x y ... Z M ... Z"). Split on M/Z into
    // sub-rings, keeping only the numbers within each.
    final poly = json['polygon'] as String;
    final rings = <List<double>>[];
    for (final part in poly.split(RegExp(r'[MmZz]'))) {
      final nums = part
          .split(RegExp(r'[,\sLlHhVv]+'))
          .where((s) => s.isNotEmpty)
          .map((s) => double.tryParse(s))
          .whereType<double>()
          .toList();
      if (nums.length >= 6) rings.add(nums);
    }
    return AyahHitRegion(
      surahNumber: json['surahNumber'],
      ayahNumber: json['ayahNumber'],
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      rings: rings,
    );
  }

  /// Whether ([px], [py]) — in viewBox coordinates — lies inside this
  /// ayah's polygon outline. An overall bounding box is NOT suitable
  /// for hit-testing or painting: an ayah spanning several lines has
  /// one sub-rectangle per line, and its bounding box would overlap
  /// the neighbouring ayahs on shared lines. Ray casting is run per
  /// sub-ring; the rings are disjoint, so any hit counts.
  bool containsPoint(double px, double py) {
    for (final ring in rings) {
      final n = ring.length ~/ 2;
      if (n < 3) continue;
      var inside = false;
      for (var i = 0, j = n - 1; i < n; j = i++) {
        final xi = ring[i * 2], yi = ring[i * 2 + 1];
        final xj = ring[j * 2], yj = ring[j * 2 + 1];
        if (((yi > py) != (yj > py)) &&
            (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) {
          inside = !inside;
        }
      }
      if (inside) return true;
    }
    return false;
  }
}

class MushafPageData {
  final int pageNumber;
  final String svgContent;
  final List<AyahHitRegion> ayahRegions;
  final double viewBoxWidth;
  final double viewBoxHeight;

  MushafPageData({
    required this.pageNumber,
    required this.svgContent,
    required this.ayahRegions,
    required this.viewBoxWidth,
    required this.viewBoxHeight,
  });
}

/// Fetches Mushaf page SVGs + ayah tap-region JSON from
/// quranpedia/quran-svg, caching both through [MushafFileStorage] —
/// real files on mobile/desktop (large capacity, supports downloading
/// the entire 604-page Mushaf for full offline use), or a small rolling
/// SharedPreferences cache on web (browser storage quotas can't hold
/// the whole Mushaf, so only the last few visited pages stay cached).
class MushafSvgService {
  static const String _svgBaseUrl =
      'https://raw.githubusercontent.com/quranpedia/quran-svg/main/mushafs/hafs/kfqc/svg';
  static const String _jsonBaseUrl =
      'https://raw.githubusercontent.com/quranpedia/quran-svg/main/mushafs/hafs/kfqc/json';

  static const int totalPages = 604;

  /// Whether this platform can realistically store the entire Mushaf
  /// offline (true on mobile/desktop, false on web).
  static bool get supportsFullOfflineDownload =>
      MushafFileStorage.supportsFullOfflineDownload;

  static final Map<int, MushafPageData> _memoryCache = {};

  static String _padded(int page) => page.toString().padLeft(3, '0');

  static Future<bool> isCached(int page) async {
    if (_memoryCache.containsKey(page)) return true;
    return MushafFileStorage.hasPage(page);
  }

  /// Loads a page: memory cache -> disk/web cache -> network, in order.
  static Future<MushafPageData> getPage(int page) async {
    if (_memoryCache.containsKey(page)) {
      return _memoryCache[page]!;
    }

    final cachedSvg = await MushafFileStorage.readSvg(page);
    final cachedJson = await MushafFileStorage.readJson(page);

    String svgContent;
    String jsonContent;

    if (cachedSvg != null && cachedJson != null) {
      svgContent = cachedSvg;
      jsonContent = cachedJson;
    } else {
      final client = http.Client();
      try {
        final results = await Future.wait([
          client.get(Uri.parse('$_svgBaseUrl/${_padded(page)}.svg')),
          client.get(Uri.parse('$_jsonBaseUrl/${_padded(page)}.json')),
        ]).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('انتهت مهلة التحميل، حاول مجدداً'),
        );

        if (results[0].statusCode != 200 || results[1].statusCode != 200) {
          throw Exception('فشل تحميل صفحة المصحف رقم $page');
        }

        svgContent = results[0].body;
        jsonContent = results[1].body;
      } finally {
        client.close();
      }

      try {
        await MushafFileStorage.writePage(page, svgContent, jsonContent);
      } catch (_) {
        // Cache write failed — not fatal, still returned in memory below.
      }
    }

    final regions = (jsonDecode(jsonContent) as List)
        .map((e) => AyahHitRegion.fromJson(e as Map<String, dynamic>))
        .toList();

    final viewBoxMatch =
        RegExp(r'viewBox="0 0 ([\d.]+) ([\d.]+)"').firstMatch(svgContent);
    final vbWidth =
        viewBoxMatch != null ? double.parse(viewBoxMatch.group(1)!) : 235.0;
    final vbHeight =
        viewBoxMatch != null ? double.parse(viewBoxMatch.group(2)!) : 235.0;

    final data = MushafPageData(
      pageNumber: page,
      svgContent: svgContent,
      ayahRegions: regions,
      viewBoxWidth: vbWidth,
      viewBoxHeight: vbHeight,
    );

    _memoryCache[page] = data;
    return data;
  }

  /// Best-effort background preload of a neighbouring page.
  static Future<void> preload(int page) async {
    if (page < 1 || page > totalPages) return;
    try {
      if (_memoryCache.containsKey(page)) return;
      if (await isCached(page)) return;
      await getPage(page);
    } catch (_) {
      // Ignore — this is opportunistic, the real fetch will surface
      // errors if the user navigates here directly.
    }
  }

  // ── Full-Mushaf background download ────────────────────────────────
  //
  // Owned by the SERVICE (not a screen) so navigating away never kills
  // an in-flight download. Pages are fetched by a pool of parallel
  // workers and written straight to storage WITHOUT SVG/JSON parsing —
  // parsing 604 pages on the UI isolate was the main reason the old
  // sequential download felt endless.

  /// (pagesDone, totalPages) while a bulk download runs, null when idle.
  static final ValueNotifier<(int, int)?> bulkProgress =
      ValueNotifier<(int, int)?>(null);

  static bool _bulkCancelled = false;
  static bool get bulkRunning => bulkProgress.value != null;

  static void cancelBulkDownload() => _bulkCancelled = true;

  /// Starts (or resumes) downloading every missing page for full
  /// offline use. Already-cached pages are skipped, so calling this
  /// again after an interruption continues where it left off. No-op if
  /// a bulk download is already running.
  static Future<void> startBulkDownload() async {
    if (bulkRunning || !supportsFullOfflineDownload) return;
    _bulkCancelled = false;

    final cached = (await MushafFileStorage.cachedPages()).toSet();
    final queue = [
      for (var p = 1; p <= totalPages; p++)
        if (!cached.contains(p)) p
    ];
    var done = totalPages - queue.length;
    bulkProgress.value = (done, totalPages);
    if (queue.isEmpty) {
      bulkProgress.value = null;
      return;
    }

    final client = http.Client();
    try {
      const parallel = 8;
      Future<void> worker() async {
        while (queue.isNotEmpty && !_bulkCancelled) {
          final page = queue.removeAt(0);
          try {
            final results = await Future.wait([
              client.get(Uri.parse('$_svgBaseUrl/${_padded(page)}.svg')),
              client.get(Uri.parse('$_jsonBaseUrl/${_padded(page)}.json')),
            ]).timeout(const Duration(seconds: 40));
            if (results[0].statusCode == 200 &&
                results[1].statusCode == 200) {
              await MushafFileStorage.writePage(
                  page, results[0].body, results[1].body);
            }
          } catch (_) {
            // Connection hiccup — the page stays missing and a later
            // resume picks it up.
          }
          done++;
          bulkProgress.value = (done, totalPages);
        }
      }

      await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
    } finally {
      client.close();
      bulkProgress.value = null;
    }
  }

  static Future<List<int>> getCachedPageNumbers() =>
      MushafFileStorage.cachedPages();

  static Future<bool> isFullyDownloaded() async {
    if (!supportsFullOfflineDownload) return false;
    final pages = await MushafFileStorage.cachedPages();
    return pages.length >= totalPages;
  }

  static Future<void> clearDiskCache() async {
    await MushafFileStorage.clearAll();
    _memoryCache.clear();
  }

  static Future<int> getCacheSizeBytes() => MushafFileStorage.totalSizeBytes();
}

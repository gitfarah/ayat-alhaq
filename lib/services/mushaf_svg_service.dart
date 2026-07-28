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

  /// Origin of the viewBox. Zero for Hafs, but Warsh and Qalon pages
  /// start at x = -6, and every ayah polygon is expressed in that same
  /// space — so it has to be subtracted before scaling to the screen.
  final double viewBoxMinX;
  final double viewBoxMinY;

  MushafPageData({
    required this.pageNumber,
    required this.svgContent,
    required this.ayahRegions,
    required this.viewBoxWidth,
    required this.viewBoxHeight,
    this.viewBoxMinX = 0,
    this.viewBoxMinY = 0,
  });
}

/// Fetches Mushaf page SVGs + ayah tap-region JSON from
/// quranpedia/quran-svg, caching both through [MushafFileStorage] —
/// real files on mobile/desktop (large capacity, supports downloading
/// the entire 604-page Mushaf for full offline use), or a small rolling
/// SharedPreferences cache on web (browser storage quotas can't hold
/// the whole Mushaf, so only the last few visited pages stay cached).
/// A Mushaf edition (riwayah). Each is a complete 604-page set with the
/// same file layout, so switching only changes the source folder.
class MushafEdition {
  /// Folder name in the quranpedia repo, also the storage namespace.
  final String id;
  final String nameAr;
  final String nameEn;

  /// One-line note shown under the name in the picker.
  final String hintAr;
  final String hintEn;

  /// True for the reflowing text edition, which is typeset live from
  /// the bundled Quran text instead of being fetched as page artwork.
  /// Nothing about it is downloadable or page-image based.
  final bool isText;

  const MushafEdition(this.id, this.nameAr, this.nameEn,
      {this.hintAr = '', this.hintEn = '', this.isText = false});
}

class MushafSvgService {
  /// The editions offered in the app. The three riwayat share the
  /// `kfqc` page layout; `text` is not artwork at all (see [isText]).
  static const List<MushafEdition> editions = [
    MushafEdition('hafs', 'مصحف حفص', 'Hafs',
        hintAr: 'الرسم العثماني — التخطيط الأصلي',
        hintEn: 'Uthmani script — original page layout'),
    MushafEdition('warsh', 'مصحف ورش', 'Warsh',
        hintAr: 'رواية ورش عن نافع',
        hintEn: 'Riwayat Warsh ʿan Nāfiʿ'),
    MushafEdition('qalon', 'مصحف قالون', 'Qalon',
        hintAr: 'رواية قالون عن نافع',
        hintEn: 'Riwayat Qālūn ʿan Nāfiʿ'),
    MushafEdition('shubah', 'مصحف شعبة', 'Shubah',
        hintAr: 'رواية شعبة عن عاصم',
        hintEn: 'Riwayat Shuʿbah ʿan ʿĀṣim'),
    MushafEdition('douri', 'مصحف الدوري', 'Ad-Duri',
        hintAr: 'رواية الدوري عن أبي عمرو',
        hintEn: 'Riwayat ad-Dūrī ʿan Abī ʿAmr'),
    MushafEdition('text', 'نص متجاوب', 'Reflowing text',
        hintAr: 'يتكيّف مع التكبير وحجم الشاشة',
        hintEn: 'Reflows to the zoom level and screen size',
        isText: true),
  ];

  static const String _repo =
      'https://raw.githubusercontent.com/quranpedia/quran-svg/main/mushafs';

  static MushafEdition _edition = editions.first;
  static MushafEdition get edition => _edition;

  /// Switches edition and re-points storage so cached pages of
  /// different riwayat never mix. The in-memory pages are NOT cleared —
  /// they are keyed by edition, so the previous riwayah's entries are
  /// simply unreachable, and an in-flight preload landing after the
  /// switch cannot be mistaken for the new edition's page.
  static void setEdition(String id) {
    final next = editions.firstWhere((e) => e.id == id,
        orElse: () => editions.first);
    if (next.id == _edition.id) return;
    _edition = next;
    MushafFileStorage.edition = next.id;
  }

  static String get _svgBaseUrl => '$_repo/${_edition.id}/kfqc/svg';
  static String get _jsonBaseUrl => '$_repo/${_edition.id}/kfqc/json';

  static const int totalPages = 604;

  /// Whether this platform can realistically store the entire Mushaf
  /// offline (true on mobile/desktop, false on web).
  /// The reflowing text edition ships inside the app, so there is
  /// nothing to download for it.
  static bool get supportsFullOfflineDownload =>
      !_edition.isText && MushafFileStorage.supportsFullOfflineDownload;

  /// Decoded pages, keyed by "edition:page".
  ///
  /// Keyed by edition, not cleared on switch: preloads for the previous
  /// edition are still in flight when the reader switches, and a plain
  /// page-number key let one of them land AFTER the clear and hand the
  /// old riwayah's artwork straight back to the new edition's request.
  /// That is why a switch only seemed to take effect a page later.
  static final Map<String, MushafPageData> _memoryCache = {};

  static String _cacheKey(int page) => '${_edition.id}:$page';

  static String _padded(int page) => page.toString().padLeft(3, '0');

  static Future<bool> isCached(int page) async {
    if (_memoryCache.containsKey(_cacheKey(page))) return true;
    return MushafFileStorage.hasPage(page);
  }

  /// Loads a page: memory cache -> disk/web cache -> network, in order.
  static Future<MushafPageData> getPage(int page) async {
    if (_memoryCache.containsKey(_cacheKey(page))) {
      return _memoryCache[_cacheKey(page)]!;
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

    // The viewBox origin is NOT always 0 0 — Warsh and Qalon pages are
    // "-6 0 345 550". Parse all four values: the origin is needed to map
    // taps and mark painting into the page's own coordinate space, and
    // matching only "0 0 ..." silently collapsed every page of those
    // editions to the square fallback.
    final vb = RegExp(
            r'viewBox="\s*(-?[\d.]+)[,\s]+(-?[\d.]+)[,\s]+(-?[\d.]+)[,\s]+(-?[\d.]+)\s*"')
        .firstMatch(svgContent);
    double n(int g, double fallback) =>
        vb == null ? fallback : (double.tryParse(vb.group(g)!) ?? fallback);

    final data = MushafPageData(
      pageNumber: page,
      svgContent: svgContent,
      ayahRegions: regions,
      viewBoxMinX: n(1, 0),
      viewBoxMinY: n(2, 0),
      viewBoxWidth: n(3, 235),
      viewBoxHeight: n(4, 235),
    );

    _memoryCache[_cacheKey(page)] = data;
    // Cap the in-memory cache: each page's SVG string is ~0.6 MB, and a
    // swipe through the whole Mushaf must not accumulate 350 MB of RAM.
    // Insertion order ≈ recency here (pages are re-fetched from disk
    // cheaply once evicted).
    while (_memoryCache.length > 12) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    return data;
  }

  /// Best-effort background preload of a neighbouring page.
  static Future<void> preload(int page) async {
    if (page < 1 || page > totalPages) return;
    try {
      if (_memoryCache.containsKey(_cacheKey(page))) return;
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

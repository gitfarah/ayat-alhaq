import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'storage/mushaf_storage.dart';

class MushafV2Word {
  final String glyph;
  final int surah;
  final int ayah;
  final bool isAyahEnd;

  const MushafV2Word(
    this.glyph,
    this.surah,
    this.ayah, {
    this.isAyahEnd = false,
  });

  factory MushafV2Word.fromJson(List<dynamic> json) {
    final key = (json[1] as String).split(':');
    return MushafV2Word(
      json[0] as String,
      int.parse(key[0]),
      int.parse(key[1]),
      isAyahEnd: json.length > 2 && json[2] == 1,
    );
  }
}

enum MushafV2LineType { ayah, surah, basmala }

class MushafV2Line {
  final int number;
  final MushafV2LineType type;
  final bool centered;
  final int? surah;
  final List<MushafV2Word> words;

  const MushafV2Line({
    required this.number,
    required this.type,
    this.centered = false,
    this.surah,
    this.words = const [],
  });

  factory MushafV2Line.fromJson(Map<String, dynamic> json) {
    final type = switch (json['t']) {
      's' => MushafV2LineType.surah,
      'b' => MushafV2LineType.basmala,
      _ => MushafV2LineType.ayah,
    };
    return MushafV2Line(
      number: json['n'] as int,
      type: type,
      centered: json['c'] == 1 ||
          type == MushafV2LineType.surah ||
          type == MushafV2LineType.basmala,
      surah: json['s'] as int?,
      words: [
        for (final word in (json['w'] as List<dynamic>? ?? const []))
          MushafV2Word.fromJson(word as List<dynamic>),
      ],
    );
  }

  String get glyphs => words.map((word) => word.glyph).join();
}

class MushafV2Page {
  final int pageNumber;
  final List<MushafV2Line> lines;
  final String fontFamily;
  final String surahFontFamily;
  final String bismillahFontFamily;
  final bool usesColorFont;

  const MushafV2Page({
    required this.pageNumber,
    required this.lines,
    required this.fontFamily,
    required this.surahFontFamily,
    required this.bismillahFontFamily,
    required this.usesColorFont,
  });
}

class _MushafGlyphConfig {
  final String id;
  final String cacheKey;
  final String layoutAsset;
  final String fontBase;
  final String fontLabel;
  final bool usesColorFont;

  const _MushafGlyphConfig({
    required this.id,
    required this.cacheKey,
    required this.layoutAsset,
    required this.fontBase,
    required this.fontLabel,
    this.usesColorFont = false,
  });
}

/// QUL's KFGQPC page layouts plus their official page-specific fonts.
/// Layout metadata ships with the app; fonts are fetched per page and cached
/// in separate V1/V2/V4 namespaces so switching editions can never mix glyphs.
class MushafV2Service {
  static const int totalPages = 604;
  static const bool supportsFullOfflineDownload =
      MushafFileStorage.supportsFullOfflineDownload;
  static const String surahNameFontFamily = 'QUL_Surah_Name_V4';
  static const String bismillahNameFontFamily = 'QUL_Bismillah';
  static const _configs = <String, _MushafGlyphConfig>{
    'hafs': _MushafGlyphConfig(
      id: 'hafs',
      cacheKey: 'v4',
      layoutAsset: 'assets/quran/mushaf_v4_1441h_layout.json',
      fontBase:
          'https://static-cdn.tarteel.ai/qul/fonts/quran_fonts/v4-tajweed/ttf',
      fontLabel: 'KFGQPC V4',
      usesColorFont: true,
    ),
    'madinah1421': _MushafGlyphConfig(
      id: 'madinah1421',
      cacheKey: 'v2',
      layoutAsset: 'assets/quran/mushaf_v2_1421h_layout.json',
      fontBase: 'https://static-cdn.tarteel.ai/qul/fonts/quran_fonts/v2/ttf',
      fontLabel: 'KFGQPC V2',
    ),
    'madinah1405': _MushafGlyphConfig(
      id: 'madinah1405',
      cacheKey: 'v1',
      layoutAsset: 'assets/quran/mushaf_v1_1405h_layout.json',
      fontBase:
          'https://static-cdn.tarteel.ai/qul/fonts/quran_fonts/v1-optimized/ttf',
      fontLabel: 'KFGQPC V1',
    ),
  };

  static final Map<String, Future<List<dynamic>>> _layoutFutures = {};
  static Future<void>? _surahFontFuture;
  static final Map<String, Future<MushafV2Page>> _pageFutures = {};
  static final Map<String, String> _loadedFamilies = {};
  static final ValueNotifier<({String editionId, int done, int total})?>
      bulkProgress = ValueNotifier(null);
  static bool _bulkCancelled = false;

  static bool bulkRunningFor(String editionId) =>
      bulkProgress.value?.editionId == editionId;

  static void cancelBulkDownload() => _bulkCancelled = true;

  static _MushafGlyphConfig _config(String editionId) =>
      _configs[editionId] ?? _configs['hafs']!;

  static Future<List<dynamic>> _layout(_MushafGlyphConfig config) =>
      _layoutFutures[config.id] ??=
          rootBundle.loadString(config.layoutAsset).then((raw) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final pages = decoded['pages'] as List<dynamic>;
        if (pages.length != totalPages) {
          throw FormatException('Incomplete ${config.fontLabel} layout');
        }
        return pages;
      });

  static Future<bool> isCached(int page, {required String editionId}) async {
    final config = _config(editionId);
    final key = '${config.id}:$page';
    return _loadedFamilies.containsKey(key) ||
        await MushafFontStorage.read(config.cacheKey, page) != null;
  }

  static Future<MushafV2Page> getPage(int page,
      {bool retry = false, required String editionId}) {
    if (page < 1 || page > totalPages) {
      return Future.error(RangeError.range(page, 1, totalPages, 'page'));
    }
    final config = _config(editionId);
    final key = '${config.id}:$page';
    if (retry) _pageFutures.remove(key);
    return _pageFutures[key] ??= _loadPage(page, config);
  }

  static Future<MushafV2Page> _loadPage(
      int page, _MushafGlyphConfig config) async {
    final pages = await _layout(config);
    final raw = pages[page - 1] as Map<String, dynamic>;
    final lines = [
      for (final line in raw['l'] as List<dynamic>)
        MushafV2Line.fromJson(line as Map<String, dynamic>),
    ];
    final results = await Future.wait<Object?>([
      _ensureFont(page, lines, config),
      _ensureSurahFont(),
    ]);
    final family = results.first! as String;
    return MushafV2Page(
      pageNumber: page,
      lines: lines,
      fontFamily: family,
      surahFontFamily: surahNameFontFamily,
      bismillahFontFamily: bismillahNameFontFamily,
      usesColorFont: config.usesColorFont,
    );
  }

  static Future<void> _ensureSurahFont() => _surahFontFuture ??= () async {
        final surahLoader = FontLoader(surahNameFontFamily)
          ..addFont(rootBundle.load('assets/fonts/qul_surah_name_v4.ttf'));
        final bismillahLoader = FontLoader(bismillahNameFontFamily)
          ..addFont(rootBundle.load('assets/fonts/qul_bismillah.ttf'));
        await Future.wait([surahLoader.load(), bismillahLoader.load()]);
      }();
  static Future<String> _ensureFont(
      int page, List<MushafV2Line> lines, _MushafGlyphConfig config) async {
    final key = '${config.id}:$page';
    final loaded = _loadedFamilies[key];
    if (loaded != null) return loaded;

    var bytes = await MushafFontStorage.read(config.cacheKey, page);
    var fromCache = bytes != null;
    if (bytes == null || !_looksLikeFont(bytes)) {
      if (bytes != null) {
        await MushafFontStorage.remove(config.cacheKey, page);
      }
      bytes = await _downloadFont(page, config);
      fromCache = false;
    }

    try {
      final family = await _registerAndVerify(page, bytes, lines, config);
      _loadedFamilies[key] = family;
      if (!fromCache) {
        await MushafFontStorage.write(config.cacheKey, page, bytes);
      }
      return family;
    } catch (_) {
      if (fromCache) {
        await MushafFontStorage.remove(config.cacheKey, page);
        final fresh = await _downloadFont(page, config);
        final family = await _registerAndVerify(page, fresh, lines, config);
        _loadedFamilies[key] = family;
        await MushafFontStorage.write(config.cacheKey, page, fresh);
        return family;
      }
      rethrow;
    }
  }

  static bool _looksLikeFont(Uint8List bytes) {
    if (bytes.length < 10000) return false;
    final tag = String.fromCharCodes(bytes.take(4));
    final trueType =
        bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0;
    return trueType || tag == 'OTTO' || tag == 'true';
  }

  static Future<Uint8List> _downloadFont(
      int page, _MushafGlyphConfig config) async {
    final uri = Uri.parse('${config.fontBase}/p$page.ttf?v=3.1');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 || !_looksLikeFont(response.bodyBytes)) {
      throw Exception('${config.fontLabel} page font is unavailable');
    }
    return response.bodyBytes;
  }

  static Future<String> _registerAndVerify(
    int page,
    Uint8List bytes,
    List<MushafV2Line> lines,
    _MushafGlyphConfig config,
  ) async {
    final stamp = '${bytes.length}_${bytes[16]}${bytes[bytes.length - 17]}';
    final family = 'KFGQPC_${config.cacheKey.toUpperCase()}_${page}_$stamp';
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();

    final samples = lines
        .where((line) => line.type == MushafV2LineType.ayah)
        .take(4)
        .map((line) => line.glyphs)
        .where((text) => text.isNotEmpty)
        .toList();
    if (samples.isEmpty) {
      throw FormatException('Empty ${config.fontLabel} page');
    }

    double width(String text, String font) {
      final painter = TextPainter(
        textDirection: TextDirection.rtl,
        text: TextSpan(
          text: text,
          style: TextStyle(fontFamily: font, fontSize: 40, height: 1),
        ),
      )..layout();
      return painter.width;
    }

    var differsFromFallback = false;
    for (final sample in samples) {
      final actual = width(sample, family);
      final fallback = width(sample, '__missing_qcf_glyph_family__');
      if ((actual - fallback).abs() > fallback * 0.04) {
        differsFromFallback = true;
        break;
      }
    }
    if (!differsFromFallback) {
      throw Exception('${config.fontLabel} font was not activated');
    }

    final full = lines
        .where((line) => line.type == MushafV2LineType.ayah && !line.centered)
        .map((line) => width(line.glyphs, family))
        .where((value) => value > 0)
        .toList();
    if (full.length >= 4) {
      final minWidth = full.reduce((a, b) => a < b ? a : b);
      final maxWidth = full.reduce((a, b) => a > b ? a : b);
      if (maxWidth / minWidth > 1.14) {
        throw Exception('${config.fontLabel} page/font mismatch');
      }
    }
    return family;
  }

  static Future<void> preload(int page, {required String editionId}) async {
    if (page < 1 || page > totalPages) return;
    try {
      await getPage(page, editionId: editionId);
    } catch (_) {
      // The visible page owns error reporting and retry UI.
    }
  }

  /// Downloads every page-specific font for one QUL edition. Fonts are
  /// written straight to disk without registering all 604 families, keeping
  /// memory flat while making the complete Mushaf available offline.
  static Future<void> startBulkDownload(String editionId) async {
    if (!supportsFullOfflineDownload || bulkProgress.value != null) return;
    final config = _config(editionId);
    _bulkCancelled = false;
    final cached =
        (await MushafFontStorage.cachedPages(config.cacheKey)).toSet();
    final missing = <int>[
      for (var page = 1; page <= totalPages; page++)
        if (!cached.contains(page)) page,
    ];
    var done = totalPages - missing.length;
    bulkProgress.value = (editionId: editionId, done: done, total: totalPages);
    if (missing.isEmpty) {
      bulkProgress.value = null;
      return;
    }

    try {
      final queue = List<int>.of(missing);
      Future<void> worker() async {
        while (queue.isNotEmpty && !_bulkCancelled) {
          final page = queue.removeLast();
          try {
            final bytes = await _downloadFont(page, config);
            if (_bulkCancelled) break;
            await MushafFontStorage.write(config.cacheKey, page, bytes);
          } catch (_) {
            // Leave failed pages missing so the next run resumes them.
          }
          done++;
          bulkProgress.value =
              (editionId: editionId, done: done, total: totalPages);
        }
      }

      await Future.wait(List.generate(4, (_) => worker()));
    } finally {
      bulkProgress.value = null;
    }
  }

  static Future<bool> isFullyDownloaded(String editionId) async {
    final config = _config(editionId);
    return (await MushafFontStorage.cachedPages(config.cacheKey)).length >=
        totalPages;
  }

  @visibleForTesting
  static void resetForTesting() {
    _layoutFutures.clear();
    _pageFutures.clear();
    _loadedFamilies.clear();
  }
}

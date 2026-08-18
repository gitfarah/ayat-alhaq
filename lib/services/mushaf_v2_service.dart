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

enum MushafBlockKind { ayah, surahHeader, basmala }

/// A page re-cut at AYAH boundaries instead of printed line ends — what
/// the ayah-by-ayah reader lays out (see MushafReaderScreen).
///
/// The print packs whatever fits on a line, so one line can hold the end
/// of one ayah and the start of the next, and one ayah can run over
/// three lines. For a surface that gives each ayah its own block (and
/// room for a translation under it), those line breaks are noise: what
/// matters is which glyphs belong to which verse, which every word
/// carries in its own surah:ayah tag.
class MushafBlock {
  final MushafBlockKind kind;

  /// 0 on a basmala, which belongs to no single surah's text.
  final int surah;

  /// 0 on anything that is not an ayah.
  final int ayah;

  /// Empty on a header or basmala — those are set from their own
  /// ligature fonts, not from the page's word glyphs.
  final String glyphs;

  const MushafBlock({
    required this.kind,
    this.surah = 0,
    this.ayah = 0,
    this.glyphs = '',
  });
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

  /// This page's content in reading order, with each ayah joined back
  /// into one run however the print split it across lines, and surah
  /// headers and basmalas kept in place between them.
  List<MushafBlock> get blocks {
    final out = <MushafBlock>[];
    int? surah;
    int? ayah;
    final buffer = StringBuffer();

    void flush() {
      if (surah != null && buffer.isNotEmpty) {
        out.add(MushafBlock(
          kind: MushafBlockKind.ayah,
          surah: surah!,
          ayah: ayah!,
          glyphs: buffer.toString(),
        ));
      }
      buffer.clear();
      surah = null;
      ayah = null;
    }

    for (final line in lines) {
      switch (line.type) {
        case MushafV2LineType.surah:
          flush();
          if (line.surah != null) {
            out.add(MushafBlock(
                kind: MushafBlockKind.surahHeader, surah: line.surah!));
          }
        case MushafV2LineType.basmala:
          flush();
          out.add(const MushafBlock(kind: MushafBlockKind.basmala));
        case MushafV2LineType.ayah:
          for (final word in line.words) {
            // A new verse starts a new block even mid-line, which is
            // exactly the case cropping a printed page could never get
            // right.
            if (surah != word.surah || ayah != word.ayah) {
              flush();
              surah = word.surah;
              ayah = word.ayah;
            }
            buffer.write(word.glyph);
          }
      }
    }
    flush();
    return out;
  }
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
    // The same V4 layout and the same calligraphy as 'hafs', cut WITHOUT
    // the COLR/CPAL tajweed layers — what the tajweed switch turns the
    // glyph reader back to. It has to be its own edition rather than a
    // flag on 'hafs': the two cuts are different files under the same
    // page number, so they need separate cache namespaces and separate
    // registered families or one would silently serve the other.
    'hafs_plain': _MushafGlyphConfig(
      id: 'hafs_plain',
      cacheKey: 'v4plain',
      layoutAsset: 'assets/quran/mushaf_v4_1441h_layout.json',
      fontBase: 'https://static-cdn.tarteel.ai/qul/fonts/quran_fonts/v4/ttf',
      fontLabel: 'KFGQPC V4 (plain)',
    ),
    // 'madinah1421' (KFGQPC V2, 1421H) used to sit here — removed from
    // the edition picker (mushaf_svg_service.dart's `editions` list) as
    // no longer needed, and dropped from this map too: an id that can
    // never be selected has no reason to keep a live config entry. Any
    // STALE persisted selection still resolves safely — _config's own
    // `?? _configs['hafs']!` fallback below. The bundled layout asset
    // itself (assets/quran/mushaf_v2_1421h_layout.json) and its own
    // structural test are left alone; deleting bundled data is a
    // separate call from taking the edition out of the app.
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

  /// Which edition actually draws [editionId] with tajweed colouring
  /// [tajweed] or without it.
  ///
  /// Only V4 ships both cuts. V1 and V2 are plain-only, so for those the
  /// switch has nothing to choose between and the edition is returned
  /// unchanged rather than falling back to a V4 that would silently
  /// change which Mushaf the reader is looking at.
  static String editionFor(String editionId, {required bool tajweed}) {
    if (editionId == 'hafs' || editionId == 'hafs_plain') {
      return tajweed ? 'hafs' : 'hafs_plain';
    }
    return editionId;
  }

  /// Whether [editionId] has a tajweed-coloured cut at all — i.e.
  /// whether showing the reader a tajweed switch would mean anything.
  static bool hasTajweedCut(String editionId) =>
      editionId == 'hafs' || editionId == 'hafs_plain';

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
      {bool retry = false,
      required String editionId,
      bool darkPalette = false}) {
    if (page < 1 || page > totalPages) {
      return Future.error(RangeError.range(page, 1, totalPages, 'page'));
    }
    final config = _config(editionId);
    // The palette is part of the IDENTITY of the loaded font, not a
    // style laid over it: a colour font carries its own colours, so
    // light and dark are two separately registered families built from
    // the same file. Keyed apart here, or one ground would be served
    // the other's ink.
    final key = '${config.id}:$page:${darkPalette ? 'd' : 'l'}';
    if (retry) _pageFutures.remove(key);
    return _pageFutures[key] ??= _loadPage(page, config, darkPalette);
  }

  static Future<MushafV2Page> _loadPage(
      int page, _MushafGlyphConfig config, bool darkPalette) async {
    final pages = await _layout(config);
    final raw = pages[page - 1] as Map<String, dynamic>;
    final lines = [
      for (final line in raw['l'] as List<dynamic>)
        MushafV2Line.fromJson(line as Map<String, dynamic>),
    ];
    final results = await Future.wait<Object?>([
      _ensureFont(page, lines, config, darkPalette),
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

  /// Only the Bismillah face still needs loading here. The surah-name
  /// font ([surahNameFontFamily]) moved into pubspec.yaml when the app's
  /// index and reader started setting their titles in it too: those show
  /// surah names before any Mushaf page has been opened, so a font that
  /// only arrives with the first page load would be too late for them.
  static Future<void> _ensureSurahFont() => _surahFontFuture ??= () async {
        final bismillahLoader = FontLoader(bismillahNameFontFamily)
          ..addFont(rootBundle.load('assets/fonts/qul_bismillah.ttf'));
        await bismillahLoader.load();
      }();
  static Future<String> _ensureFont(int page, List<MushafV2Line> lines,
      _MushafGlyphConfig config, bool darkPalette) async {
    final key = '${config.id}:$page:${darkPalette ? 'd' : 'l'}';
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
      final family =
          await _registerAndVerify(page, bytes, lines, config, darkPalette);
      _loadedFamilies[key] = family;
      if (!fromCache) {
        await MushafFontStorage.write(config.cacheKey, page, bytes);
      }
      return family;
    } catch (_) {
      if (fromCache) {
        await MushafFontStorage.remove(config.cacheKey, page);
        final fresh = await _downloadFont(page, config);
        final family =
            await _registerAndVerify(page, fresh, lines, config, darkPalette);
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

  /// Repoints a colour font's DEFAULT palette at the palette meant for a
  /// dark ground, returning a patched copy (the original is what stays
  /// cached on disk).
  ///
  /// The KFGQPC tajweed fonts ship six CPAL palettes: 0 is the tajweed
  /// set drawn for a light page — its base letter colour is #000000 —
  /// and 1 is the same set for a dark one, base letter #ffffff. Without
  /// this, dark mode drew the verse in black on black, and the ayah
  /// medallion lost the two black sides of its frame.
  ///
  /// A colour font paints from its own palette and IGNORES the caller's
  /// TextStyle colour, so this cannot be fixed by asking for white ink.
  /// Flutter also has no equivalent of CSS `font-palette`, so the choice
  /// has to be made in the font file itself — and it is a two-byte one:
  /// CPAL indexes each palette by where its colour records start, so
  /// pointing entry 0 at palette 1's first record swaps the whole
  /// palette without moving, resizing or rewriting a single colour.
  static Uint8List? _repaletteForDark(Uint8List bytes) {
    try {
      final data = ByteData.sublistView(bytes);
      final numTables = data.getUint16(4);
      var cpal = -1;
      for (var i = 0; i < numTables; i++) {
        final rec = 12 + i * 16;
        if (String.fromCharCodes(bytes, rec, rec + 4) == 'CPAL') {
          cpal = data.getUint32(rec + 8);
          break;
        }
      }
      if (cpal < 0) return null;

      final numEntries = data.getUint16(cpal + 2);
      final numPalettes = data.getUint16(cpal + 4);
      // Palette 1 is the dark-ground cut by KFGQPC's own convention; a
      // font that does not carry one is left exactly as it is rather
      // than guessed at.
      if (numPalettes < 2) return null;
      final darkStart = data.getUint16(cpal + 12 + 2);
      final firstRecord = data.getUint32(cpal + 8);

      final patched = Uint8List.fromList(bytes);
      ByteData.sublistView(patched).setUint16(cpal + 12, darkStart);

      // KFGQPC's own dark palette sets the PLAIN letter (no tajweed
      // rule applies — most of a page) to pure #FFFFFF. On this app's
      // true-black reading surface that reads visibly heavier than
      // every other piece of dark-mode text, which is deliberately set
      // in a softened off-white (AppColors.darkText) for exactly this
      // reason: pure white on pure black is a known case of perceived
      // over-bolding (halation) that pure black on white does not
      // suffer the mirror of.
      //
      // Checked by hand against the real font: entries 0, 13 and 14 are
      // that "no rule" ink in BOTH palettes — 13/14 sit within one unit
      // of 0 in each (they are the plain-page ink and the plain sides
      // of the ayah-medallion frame) — while every entry in between is
      // its own distinct tajweed-rule hue. Only that ink trio is
      // retuned; the rule colours a reader relies on to tell one
      // tajweed rule from another are left exactly as KFGQPC ships
      // them.
      const softWhite = (r: 0xF2, g: 0xF0, b: 0xED); // == AppColors.darkText
      for (final entry in [0, 13, 14]) {
        if (entry >= numEntries) continue;
        final o = cpal + firstRecord + (darkStart + entry) * 4;
        // CPAL colour records are BGRA.
        patched[o] = softWhite.b;
        patched[o + 1] = softWhite.g;
        patched[o + 2] = softWhite.r;
        // Alpha (o + 3) is left exactly as the font shipped it.
      }
      return patched;
    } catch (_) {
      // A font this cannot be read out of still renders — in its own
      // light palette, which is what it did before this existed.
      return null;
    }
  }

  static Future<String> _registerAndVerify(
    int page,
    Uint8List bytes,
    List<MushafV2Line> lines,
    _MushafGlyphConfig config,
    bool darkPalette,
  ) async {
    final stamp = '${bytes.length}_${bytes[16]}${bytes[bytes.length - 17]}';
    final palette =
        darkPalette && config.usesColorFont ? _repaletteForDark(bytes) : null;
    // The ground is in the family name because the two palettes are two
    // registered fonts; sharing a name would let whichever loaded first
    // answer for both.
    final family = 'KFGQPC_${config.cacheKey.toUpperCase()}_${page}_$stamp'
        '${palette != null ? '_dark' : ''}';
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(palette ?? bytes)));
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

  static Future<void> preload(int page,
      {required String editionId, bool darkPalette = false}) async {
    if (page < 1 || page > totalPages) return;
    try {
      await getPage(page, editionId: editionId, darkPalette: darkPalette);
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
  @visibleForTesting
  static Uint8List? repaletteForDarkForTesting(Uint8List bytes) =>
      _repaletteForDark(bytes);

  static void resetForTesting() {
    _layoutFutures.clear();
    _pageFutures.clear();
    _loadedFamilies.clear();
  }
}

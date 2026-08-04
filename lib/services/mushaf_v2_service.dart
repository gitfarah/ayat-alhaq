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

  const MushafV2Page({
    required this.pageNumber,
    required this.lines,
    required this.fontFamily,
    required this.surahFontFamily,
    required this.bismillahFontFamily,
  });
}

/// QUL's 1421H layout plus its official page-specific KFGQPC V2 fonts.
/// Layout metadata ships with the app; fonts are fetched per page and cached.
class MushafV2Service {
  static const int totalPages = 604;
  static const String surahNameFontFamily = 'QUL_Surah_Name_V4';
  static const String bismillahNameFontFamily = 'QUL_Bismillah';
  static const _layoutAsset = 'assets/quran/mushaf_v2_1421h_layout.json';
  static const _fontBase =
      'https://static-cdn.tarteel.ai/qul/fonts/quran_fonts/v2/ttf';

  static Future<List<dynamic>>? _layoutFuture;
  static Future<void>? _surahFontFuture;
  static final Map<int, Future<MushafV2Page>> _pageFutures = {};
  static final Map<int, String> _loadedFamilies = {};

  static Future<List<dynamic>> _layout() =>
      _layoutFuture ??= rootBundle.loadString(_layoutAsset).then((raw) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final pages = decoded['pages'] as List<dynamic>;
        if (pages.length != totalPages) {
          throw const FormatException('Incomplete QUL V2 layout');
        }
        return pages;
      });

  static Future<bool> isCached(int page) async =>
      _loadedFamilies.containsKey(page) ||
      await MushafFontStorage.read(page) != null;

  static Future<MushafV2Page> getPage(int page, {bool retry = false}) {
    if (page < 1 || page > totalPages) {
      return Future.error(RangeError.range(page, 1, totalPages, 'page'));
    }
    if (retry) _pageFutures.remove(page);
    return _pageFutures[page] ??= _loadPage(page);
  }

  static Future<MushafV2Page> _loadPage(int page) async {
    final pages = await _layout();
    final raw = pages[page - 1] as Map<String, dynamic>;
    final lines = [
      for (final line in raw['l'] as List<dynamic>)
        MushafV2Line.fromJson(line as Map<String, dynamic>),
    ];
    final results = await Future.wait<Object?>([
      _ensureFont(page, lines),
      _ensureSurahFont(),
    ]);
    final family = results.first! as String;
    return MushafV2Page(
      pageNumber: page,
      lines: lines,
      fontFamily: family,
      surahFontFamily: surahNameFontFamily,
      bismillahFontFamily: bismillahNameFontFamily,
    );
  }

  static Future<void> _ensureSurahFont() => _surahFontFuture ??= () async {
        final surahLoader = FontLoader(surahNameFontFamily)
          ..addFont(rootBundle.load('assets/fonts/qul_surah_name_v4.ttf'));
        final bismillahLoader = FontLoader(bismillahNameFontFamily)
          ..addFont(rootBundle.load('assets/fonts/qul_bismillah.ttf'));
        await Future.wait([surahLoader.load(), bismillahLoader.load()]);
      }();
  static Future<String> _ensureFont(int page, List<MushafV2Line> lines) async {
    final loaded = _loadedFamilies[page];
    if (loaded != null) return loaded;

    var bytes = await MushafFontStorage.read(page);
    var fromCache = bytes != null;
    if (bytes == null || !_looksLikeFont(bytes)) {
      if (bytes != null) await MushafFontStorage.remove(page);
      bytes = await _downloadFont(page);
      fromCache = false;
    }

    try {
      final family = await _registerAndVerify(page, bytes, lines);
      _loadedFamilies[page] = family;
      if (!fromCache) await MushafFontStorage.write(page, bytes);
      return family;
    } catch (_) {
      if (fromCache) {
        await MushafFontStorage.remove(page);
        final fresh = await _downloadFont(page);
        final family = await _registerAndVerify(page, fresh, lines);
        _loadedFamilies[page] = family;
        await MushafFontStorage.write(page, fresh);
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

  static Future<Uint8List> _downloadFont(int page) async {
    final uri = Uri.parse('$_fontBase/p$page.ttf?v=3.1');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 || !_looksLikeFont(response.bodyBytes)) {
      throw Exception('KFGQPC V2 page font is unavailable');
    }
    return response.bodyBytes;
  }

  static Future<String> _registerAndVerify(
    int page,
    Uint8List bytes,
    List<MushafV2Line> lines,
  ) async {
    // A new family per byte revision prevents a rejected cached font from
    // poisoning the FontLoader name for the remainder of the app run.
    final stamp = '${bytes.length}_${bytes[16]}${bytes[bytes.length - 17]}';
    final family = 'KFGQPC_V2_${page}_$stamp';
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();

    final samples = lines
        .where((line) => line.type == MushafV2LineType.ayah)
        .take(4)
        .map((line) => line.glyphs)
        .where((text) => text.isNotEmpty)
        .toList();
    if (samples.isEmpty) throw const FormatException('Empty V2 page');

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

    // Private-use glyphs become identical tofu boxes when Flutter did not
    // activate the font. A deliberately absent family detects that fallback.
    var differsFromFallback = false;
    for (final sample in samples) {
      final actual = width(sample, family);
      final fallback = width(sample, '__missing_qcf_v2_family__');
      if ((actual - fallback).abs() > fallback * 0.04) {
        differsFromFallback = true;
        break;
      }
    }
    if (!differsFromFallback) {
      throw Exception('KFGQPC V2 font was not activated');
    }

    // Every full line in a QCF page font has one printed measure. Large
    // variance means fallback or a mismatched font—the old tablet failure.
    final full = lines
        .where((line) => line.type == MushafV2LineType.ayah && !line.centered)
        .map((line) => width(line.glyphs, family))
        .where((value) => value > 0)
        .toList();
    if (full.length >= 4) {
      final minWidth = full.reduce((a, b) => a < b ? a : b);
      final maxWidth = full.reduce((a, b) => a > b ? a : b);
      if (maxWidth / minWidth > 1.14) {
        throw Exception('KFGQPC V2 page/font mismatch');
      }
    }
    return family;
  }

  static Future<void> preload(int page) async {
    if (page < 1 || page > totalPages) return;
    try {
      await getPage(page);
    } catch (_) {
      // The visible page owns error reporting and retry UI.
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _layoutFuture = null;
    _pageFutures.clear();
    _loadedFamilies.clear();
  }
}

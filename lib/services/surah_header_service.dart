import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Where a surah's name is printed on a Mushaf page, in the page SVG's
/// own viewBox coordinates.
///
/// The quranpedia page artwork draws the surah name as plain glyphs with
/// no ornamental banner around it (unlike a printed Mushaf). These bands
/// were measured once, offline, from the rendered pages — so at runtime
/// the app can paint the traditional decorated frame behind the name.
class SurahHeaderBand {
  final int surah;
  final int page;

  /// Vertical ink extent of the surah-name line, in viewBox units.
  final double top;
  final double bottom;

  const SurahHeaderBand({
    required this.surah,
    required this.page,
    required this.top,
    required this.bottom,
  });

  double get height => bottom - top;
}

/// Loads the measured surah-header bands and serves them per page.
///
/// Each riwayah breaks its lines differently, so a surah's name sits at a
/// different height on the same page number in each one — every edition
/// therefore carries its own measured set.
class SurahHeaderService {
  static final Map<String, Map<int, List<SurahHeaderBand>>> _byEdition = {};

  static const Map<String, String> _assets = {
    'hafs': 'assets/quran/surah_headers.json',
    'warsh': 'assets/quran/surah_headers_warsh.json',
    'qalon': 'assets/quran/surah_headers_qalon.json',
  };

  /// Editions that have measured bands (the reflowing text edition draws
  /// its own header instead, so it is not one of them).
  static bool has(String edition) => _assets.containsKey(edition);

  /// Bands for [page] in [edition]; empty when no surah starts there, or
  /// while the edition's data is still loading.
  static List<SurahHeaderBand> forPage(int page, {String edition = 'hafs'}) =>
      _byEdition[edition]?[page] ?? const <SurahHeaderBand>[];

  static bool isLoaded([String edition = 'hafs']) =>
      _byEdition.containsKey(edition);

  static Future<void> load([String edition = 'hafs']) async {
    if (_byEdition.containsKey(edition)) return;
    final asset = _assets[edition];
    if (asset == null) {
      _byEdition[edition] = const {};
      return;
    }
    try {
      final raw = await rootBundle.loadString(asset);
      final List list = jsonDecode(raw);
      final map = <int, List<SurahHeaderBand>>{};
      for (final e in list) {
        final band = SurahHeaderBand(
          surah: e['s'] as int,
          page: e['p'] as int,
          top: (e['t'] as num).toDouble(),
          bottom: (e['b'] as num).toDouble(),
        );
        map.putIfAbsent(band.page, () => <SurahHeaderBand>[]).add(band);
      }
      _byEdition[edition] = map;
    } catch (_) {
      // Missing/!valid asset must never break Mushaf reading — the pages
      // simply render without the ornamental frames.
      _byEdition[edition] = const {};
    }
  }
}

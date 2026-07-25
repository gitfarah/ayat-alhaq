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
class SurahHeaderService {
  static Map<int, List<SurahHeaderBand>>? _byPage;

  /// Bands for [page]; empty when no surah starts on that page.
  /// Safe to call before [load] — returns empty until loaded.
  static List<SurahHeaderBand> forPage(int page) =>
      _byPage?[page] ?? const <SurahHeaderBand>[];

  static bool get isLoaded => _byPage != null;

  static Future<void> load() async {
    if (_byPage != null) return;
    try {
      final raw =
          await rootBundle.loadString('assets/quran/surah_headers.json');
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
      _byPage = map;
    } catch (_) {
      // Missing/!valid asset must never break Mushaf reading — the pages
      // simply render without the ornamental frames.
      _byPage = const {};
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One stretch of Mushaf text set in ONE page's own glyph font.
///
/// The KFGQPC page fonts map private-use codepoints to whole WORDS, and
/// each of the 604 pages has its own font with its own mapping — the
/// same codepoint is a different word on a different page. A passage
/// that crosses a page turn is therefore not one string in one font,
/// it is one run per page.
class MushafGlyphRun {
  final String glyphs;
  final String fontFamily;
  const MushafGlyphRun(this.glyphs, this.fontFamily);
}

/// Sets Quran text in the King Fahd Complex's OWN printed glyphs —
/// exactly the calligraphy the Mushaf itself is made of — for whatever
/// specific ayahs a caller asks for, rather than in a reflowing body
/// font (Amiri).
///
/// Built first for the share card (see AyahShareService), which used to
/// CROP the printed page image instead. Cropping could not isolate one
/// ayah: an ayah that begins mid-line shares that line with the ayah
/// before it, so a horizontal cut always carried a neighbour's words
/// along with it. Setting the ayah's own WORDS is exact — the bundled
/// layout tags every word with its surah:ayah — and it is the same
/// calligraphy, because these are the very glyphs the page is made of.
///
/// Deliberately NOT unified with MushafV2Service's page-font cache:
/// that one is tied to a whole PAGE's line structure, and for the
/// 'hafs' edition it downloads the TAJWEED-coloured cut (COLR/CPAL
/// glyphs), because that is what full-page Mushaf mode wants to show.
/// This needs the PLAIN cut — quoting one ayah in tajweed colours
/// picked by a font's own baked-in palette, regardless of what a
/// caller's own styling asks for, would be a different feature. A
/// shared page→font cache would have to store two different fonts
/// under the same page number depending on who asked, which is worse
/// than keeping two small caches.
class MushafGlyphService {
  /// "Plain" is a real choice: QUL publishes both cuts, and the tajweed
  /// one carries COLR/CPAL tables (95 KB for page 2, against 51 KB for
  /// the plain cut, both checked by hand) that would paint the verse in
  /// tajweed colours whatever colour the caller asked for.
  static const String _fontBase =
      'https://static-cdn.tarteel.ai/qul/fonts/quran_fonts/v4/ttf';

  /// Page number → the Flutter font family its glyphs are registered
  /// under, once loaded. Registration is process-wide and permanent, so
  /// this only ever grows, and asking for the same page twice is free.
  static final Map<int, String?> _fonts = {};

  /// The shared verses' own words, grouped into runs of one page's
  /// font each, in reading order — or null if any of it could not be
  /// had: an ayah missing from the layout, a page font that will not
  /// load or does not actually draw its glyphs. Every one of those is
  /// meant to fall back to a caller's own body-font rendering, which is
  /// why this returns null rather than a partial result.
  static Future<List<MushafGlyphRun>?> runsFor(
      int surah, List<int> ayahNumbers) async {
    if (ayahNumbers.isEmpty) return null;
    try {
      final words = await _wordsFor(surah, ayahNumbers.toSet());
      if (words.isEmpty) return null;

      // One run per page, because each page's font maps the same
      // codepoints to different words.
      final runs = <MushafGlyphRun>[];
      final buffer = StringBuffer();
      int? runPage;

      Future<bool> closeRun() async {
        final page = runPage;
        if (page == null || buffer.isEmpty) return true;
        final family = await _fontFor(page);
        if (family == null || !_fontDraws(family, buffer.toString())) {
          return false;
        }
        runs.add(MushafGlyphRun(buffer.toString(), family));
        buffer.clear();
        return true;
      }

      for (final w in words) {
        if (runPage != w.page) {
          if (!await closeRun()) return null;
          runPage = w.page;
        }
        buffer.write(w.glyph);
      }
      if (!await closeRun()) return null;
      return runs.isEmpty ? null : runs;
    } catch (e) {
      debugPrint('Mushaf glyphs: unavailable for $surah:$ayahNumbers ($e)');
      return null;
    }
  }

  /// Reads the requested ayahs' own words out of the bundled Hafs V4
  /// page layout (`assets/quran/mushaf_v4_1441h_layout.json`) — the
  /// same file the app's glyph Mushaf mode already ships and reads.
  static Future<List<({int page, String glyph})>> _wordsFor(
      int surah, Set<int> ayahs) async {
    // Decoded per call rather than cached: the decoded structure is
    // tens of megabytes of Dart objects for a 1.5 MB file, and this is
    // a rare, user-initiated action (opening a sheet, sharing a verse),
    // not a hot path. rootBundle keeps the source STRING cached, so
    // this is a parse, not a disk read.
    final raw =
        await rootBundle.loadString('assets/quran/mushaf_v4_1441h_layout.json');
    final pages =
        (jsonDecode(raw) as Map<String, dynamic>)['pages'] as List<dynamic>;

    final out = <({int page, String glyph})>[];
    for (final p in pages) {
      final pageNum = p['p'] as int;
      for (final line in p['l'] as List<dynamic>) {
        final words = line['w'] as List<dynamic>?;
        if (words == null) continue;
        for (final w in words) {
          final parts = (w[1] as String).split(':');
          if (int.parse(parts[0]) != surah) continue;
          if (!ayahs.contains(int.parse(parts[1]))) continue;
          out.add((page: pageNum, glyph: w[0] as String));
        }
      }
    }
    return out;
  }

  /// The family name for [page]'s glyph font, or null if it cannot be
  /// had or does not activate. Cheapest source first: memory, this
  /// service's own cache folder, then the network.
  static Future<String?> _fontFor(int page) async {
    if (_fonts.containsKey(page)) return _fonts[page];
    try {
      Uint8List? bytes;
      Directory? dir;
      if (!kIsWeb) {
        final docs = await getApplicationDocumentsDirectory();
        dir = Directory('${docs.path}/mushaf_v4_plain_fonts');
        final f = File('${dir.path}/p$page.ttf');
        if (await f.exists()) {
          final cached = await f.readAsBytes();
          if (_looksLikeFont(cached)) bytes = cached;
        }
      }

      if (bytes == null) {
        final res = await http
            .get(Uri.parse('$_fontBase/p$page.ttf?v=3.1'))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200 || !_looksLikeFont(res.bodyBytes)) {
          return _fonts[page] = null;
        }
        bytes = res.bodyBytes;
        if (dir != null) {
          try {
            dir.createSync(recursive: true);
            await File('${dir.path}/p$page.ttf').writeAsBytes(bytes);
          } catch (_) {
            // Cache write failed — this call still works once.
          }
        }
      }

      // The length is in the family name so a re-downloaded or changed
      // font can never be masked by an already-registered family.
      final family = 'MushafV4Plain_${page}_${bytes.length}';
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
      return _fonts[page] = family;
    } catch (e) {
      debugPrint('Mushaf glyphs: page font $page unavailable ($e)');
      return _fonts[page] = null;
    }
  }

  static bool _looksLikeFont(Uint8List bytes) {
    if (bytes.length < 10000) return false;
    final tag = String.fromCharCodes(bytes.take(4));
    final trueType =
        bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0;
    return trueType || tag == 'OTTO' || tag == 'true';
  }

  /// Whether [family] actually draws [sample], rather than silently
  /// falling through to a system face.
  ///
  /// These glyphs live in the private use area, so a font that failed
  /// to register does not throw — it renders tofu, or nothing, and a
  /// caller would show the verse missing. Comparing the drawn width
  /// against a family that certainly does not exist is the same check
  /// MushafV2Service makes before trusting a page font.
  static bool _fontDraws(String family, String sample) {
    double widthIn(String f) {
      final p = ui.ParagraphBuilder(ui.ParagraphStyle(
        textDirection: TextDirection.rtl,
        fontFamily: f,
        fontSize: 40,
      ))
        ..addText(sample);
      return (p.build()
            ..layout(const ui.ParagraphConstraints(width: double.infinity)))
          .maxIntrinsicWidth;
    }

    final drawn = widthIn(family);
    final missing = widthIn('__no_such_family_for_mushaf_glyphs__');
    if (drawn <= 0) return false;
    return (drawn - missing).abs() > missing * 0.04;
  }
}

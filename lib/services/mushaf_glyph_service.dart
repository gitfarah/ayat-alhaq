import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:http/http.dart' as http;

import 'storage/mushaf_storage.dart';

/// One printed line of a glyph-rendered Mushaf page.
class GlyphLine {
  /// 's' surah header, 'b' basmalah, 'a' ayah text.
  final String type;

  /// The line's glyphs as a string. Each character is a codepoint in
  /// THIS PAGE's own font — the same code means a different shape on a
  /// different page, which is why the font is per page.
  final String text;

  /// Which ayah each stretch of [text] belongs to, as
  /// (surah, ayah, startIndex, length). Empty on header lines.
  final List<List<int>> spans;

  /// Whether this line is set in the shared Basmalah/surah-name font
  /// rather than the page's own. Ayah text lives in the page font;
  /// surah headers and the Basmalah are drawn from QCF_BSML, and using
  /// the wrong one turns them into unrelated words.
  final bool usesSharedFont;

  const GlyphLine(this.type, this.text, this.spans, this.usesSharedFont);

  bool get isHeader => type == 's';
  bool get isBasmalah => type == 'b';
}

/// Typesets the KFGQPC V1 (1405H) Mushaf from its own page fonts.
///
/// This is a different animal from [MushafSvgService]: there is no page
/// artwork. Each page has a font of its own in which the glyph codes
/// spell out that page's lines, so the page is real text — it stays
/// crisp at any zoom, and the text layout hands back the position of
/// every ayah for free, which is what tapping and highlighting need.
///
/// The layout comes from the quran.com-images database (see
/// tools/build_v1_layout.js); the fonts come from QUL's CDN, one file
/// per page, fetched on demand and cached like page artwork is.
class MushafGlyphService {
  /// Where the per-page fonts come from. Overridable so a local build
  /// can serve them from somewhere else; note that the CDN sends no
  /// CORS header, so a WEB build cannot fetch them — this edition is
  /// for the mobile app.
  static String fontBaseUrl =
      'https://static-cdn.tarteel.ai/qul/fonts/quran_fonts/v1/ttf';

  /// Font family name for a page. Registered at runtime once its file
  /// has been fetched.
  static String familyFor(int page) => 'QCF_P$page';

  /// The shared font that carries the surah-name bands and the
  /// Basmalah. Bundled rather than downloaded — it is one small file
  /// used by every page.
  static const String sharedFamily = 'QCF_BSML';

  static Map<int, List<GlyphLine>>? _layout;

  static bool get isLayoutLoaded => _layout != null;

  /// Pages whose font is registered with the engine. Flutter has no way
  /// to UNREGISTER a font, so this only ever grows — see [loadedFonts].
  static final Set<int> _fontsReady = <int>{};

  static int get loadedFonts => _fontsReady.length;

  static bool hasFont(int page) => _fontsReady.contains(page);

  /// In-flight font loads, so two widgets asking for the same page
  /// during one frame don't both download it.
  static final Map<int, Future<bool>> _inFlight = {};

  static Future<void> loadLayout() async {
    if (_layout != null) return;
    try {
      final raw =
          await rootBundle.loadString('assets/quran/mushaf_v1_layout.json');
      final Map<String, dynamic> decoded = jsonDecode(raw);
      _layout = {
        for (final e in decoded.entries)
          int.parse(e.key): [
            for (final line in e.value as List)
              GlyphLine(
                line['t'] as String,
                line['x'] as String,
                [
                  for (final s in (line['v'] as List? ?? const []))
                    (s as List).cast<int>(),
                ],
                line['f'] == 'b',
              ),
          ],
      };
    } catch (_) {
      // Reading must never break because this edition's data is
      // missing — the edition simply reports no pages.
      _layout = const {};
    }
  }

  /// The lines of [page], or empty until [loadLayout] has run.
  static List<GlyphLine> linesOf(int page) =>
      _layout?[page] ?? const <GlyphLine>[];

  /// Fetches and registers the page's font. Returns whether the family
  /// is usable; false means the page cannot be typeset yet.
  static Future<bool> ensureFont(int page) {
    if (_fontsReady.contains(page)) return Future.value(true);
    return _inFlight[page] ??= _loadFont(page).whenComplete(() {
      _inFlight.remove(page);
    });
  }

  static Future<bool> _loadFont(int page) async {
    try {
      Uint8List? bytes = await MushafFontStorage.read(page);
      if (bytes == null) {
        final res = await http
            .get(Uri.parse('$fontBaseUrl/p$page.ttf'))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) return false;
        bytes = res.bodyBytes;
        await MushafFontStorage.write(page, bytes);
      }
      final loader = FontLoader(familyFor(page))
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      _fontsReady.add(page);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pulls the fonts for the pages around [page] so a page turn does
  /// not wait on a download. Opportunistic: failures are ignored.
  static void preload(int page) {
    for (final p in [page + 1, page - 1]) {
      if (p >= 1 && p <= 604 && !_fontsReady.contains(p)) ensureFont(p);
    }
  }

  static Future<int> cachedFontCount() => MushafFontStorage.cachedCount();

  static Future<void> clearFontCache() async {
    await MushafFontStorage.clear();
    // The registered families stay registered; Flutter cannot unload a
    // font. They are rebuilt from disk or network on the next launch.
  }
}

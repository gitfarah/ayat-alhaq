import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart' show TextDirection;
import 'package:http/http.dart' as http;

import '../models/quran_page_meta.dart';
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

  /// Indices into [text] of the end-of-ayah medallions on this line.
  final Set<int> endMarks;

  /// Whether this line is set in the shared Basmalah/surah-name font
  /// rather than the page's own. Ayah text lives in the page font;
  /// surah headers and the Basmalah are drawn from QCF_BSML, and using
  /// the wrong one turns them into unrelated words.
  final bool usesSharedFont;

  /// Set on a header line: the surah it introduces. The source data's
  /// own header glyphs (see [text]) draw a plain, unvoweled name — the
  /// font was authored that way — so the header is set from
  /// [MushafGlyphService.voweledSurahName] instead, and this is how the
  /// renderer knows which name that is.
  final int? surahNumber;

  const GlyphLine(this.type, this.text, this.spans, this.endMarks,
      this.usesSharedFont, this.surahNumber);

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

  /// A header line's OWN glyphs (see [GlyphLine.text]) draw the surah
  /// name without tashkeel — that is simply how QCF_BSML was authored
  /// for this pair of glyphs, not a loading fault: the SAME font renders
  /// the Basmalah on the very same lines with its tashkeel intact. So
  /// the header is set from [QuranPageMeta.voweledSurahName] instead, in
  /// the bundled Uthmani font that already carries every mark correctly.
  static String voweledSurahName(int n) => QuranPageMeta.voweledSurahName(n);

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

  /// Pages whose font could not be made to draw. Tracked separately from
  /// "not ready yet" so the reader is told the page cannot be typeset
  /// instead of watching a spinner that will never finish — or, far
  /// worse, being shown the page in the WRONG script (see [_familyDraws]).
  static final Set<int> _fontsFailed = <int>{};

  static bool hasFailed(int page) => _fontsFailed.contains(page);

  /// Forgets a failure so the reader's retry actually retries.
  static void clearFailure(int page) => _fontsFailed.remove(page);

  /// A usable TrueType/OpenType file starts with one of these tags. A
  /// truncated or half-written cache file is the likeliest reason a page
  /// font stops working, and it must never reach [FontLoader].
  static bool _looksLikeFont(Uint8List b) {
    if (b.length < 4096) return false;
    final tag = ByteData.view(b.buffer, b.offsetInBytes).getUint32(0);
    return tag == 0x00010000 || // TrueType outlines
        tag == 0x4F54544F || // 'OTTO' — CFF outlines
        tag == 0x74727565 || // 'true'
        tag == 0x74746366; // 'ttcf' — collection
  }

  /// Whether [family] is genuinely being used to draw [probe].
  ///
  /// This is the check the edition was missing, and the reason a page
  /// could come out looking like readable Arabic in the wrong shapes.
  /// The V1 layout is written in Arabic Presentation Forms-A
  /// (U+FB50…), which are REAL assigned codepoints — so when the page
  /// font is absent the engine does not draw empty boxes, it quietly
  /// falls back to any font that covers that block and renders ordinary
  /// Arabic letters. The result reads as text, so nothing looks broken,
  /// but the lines are not the printed page's lines at all.
  ///
  /// Measuring the same string against a family that cannot exist gives
  /// the width of that fallback. If the real family measures the same,
  /// it is the fallback, and the font has NOT been applied.
  static bool _familyDraws(String family, String probe) {
    double widthOf(String f) {
      final p = TextPainter(
        textDirection: TextDirection.rtl,
        text: TextSpan(
            text: probe, style: TextStyle(fontFamily: f, fontSize: 100)),
      )..layout();
      return p.width;
    }

    final real = widthOf(family);
    if (real <= 0) return false;
    return (real - widthOf('__mushaf_absent_family__')).abs() > 0.5;
  }

  /// A stretch of this page's own glyph codes to test the font with.
  static String _probeFor(int page) {
    for (final line in linesOf(page)) {
      if (!line.usesSharedFont && line.text.trim().isNotEmpty) return line.text;
    }
    return '';
  }

  /// In-flight font loads, so two widgets asking for the same page
  /// during one frame don't both download it.
  static final Map<int, Future<bool>> _inFlight = {};

  static Future<void> loadLayout() async {
    if (_layout != null) return;
    try {
      final raw =
          await rootBundle.loadString('assets/quran/mushaf_v1_layout.json');
      final Map<String, dynamic> decoded = jsonDecode(raw);
      final pages = decoded.keys.map(int.parse).toList()..sort();

      // Flattened in page/line order, so a header sitting on the LAST
      // line of one page (a real position in this layout — a title can
      // land at the foot of the page before the surah it names) can
      // still find the surah beginning on the next.
      final flat = <(int page, Map<String, dynamic> line)>[
        for (final p in pages)
          for (final line in decoded['$p'] as List)
            (p, line as Map<String, dynamic>),
      ];

      // A header line's OWN glyphs draw a plain, unvoweled name — see
      // [MushafGlyphService.voweledSurahName] for why — so which surah
      // it names is worked out here instead: the first ayah span that
      // appears after it.
      final headerSurah = List<int?>.filled(flat.length, null);
      for (var i = 0; i < flat.length; i++) {
        if (flat[i].$2['t'] != 's') continue;
        for (var j = i + 1; j < flat.length; j++) {
          final v = flat[j].$2['v'] as List?;
          if (v != null && v.isNotEmpty) {
            headerSurah[i] = (v.first as List)[0] as int;
            break;
          }
        }
      }

      _layout = {};
      for (var i = 0; i < flat.length; i++) {
        final (page, line) = flat[i];
        (_layout![page] ??= []).add(GlyphLine(
          line['t'] as String,
          line['x'] as String,
          [
            for (final s in (line['v'] as List? ?? const []))
              (s as List).cast<int>(),
          ],
          {
            for (final k in (line['e'] as List? ?? const [])) k as int,
          },
          line['f'] == 'b',
          headerSurah[i],
        ));
      }
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

  /// Fetches, registers and then PROVES the page's font.
  ///
  /// Two passes: the first will use a cached file if there is one, the
  /// second always refetches. A page font that registers but does not
  /// draw is treated exactly like a missing one — the cached copy is
  /// binned and the download retried — because a font that does not draw
  /// is what puts the page on screen in the wrong script.
  static Future<bool> _loadFont(int page) async {
    // The probe is written in the page's own glyph codes, so the layout
    // has to be in before the font can be verified.
    await loadLayout();
    final probe = _probeFor(page);
    final family = familyFor(page);

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        Uint8List? bytes =
            attempt == 0 ? await MushafFontStorage.read(page) : null;
        if (bytes != null && !_looksLikeFont(bytes)) {
          await MushafFontStorage.remove(page);
          bytes = null;
        }
        if (bytes == null) {
          final res = await http
              .get(Uri.parse('$fontBaseUrl/p$page.ttf'))
              .timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) continue;
          bytes = res.bodyBytes;
          if (!_looksLikeFont(bytes)) continue;
          await MushafFontStorage.write(page, bytes);
        }

        await (FontLoader(family)
              ..addFont(Future.value(ByteData.view(bytes.buffer))))
            .load();

        // No probe means no layout for this page, so there is nothing to
        // typeset and nothing to verify against.
        if (probe.isEmpty || _familyDraws(family, probe)) {
          _fontsReady.add(page);
          _fontsFailed.remove(page);
          return true;
        }
        // Registered, but the engine is still drawing the fallback. The
        // cached file is the usual culprit, so drop it and refetch once.
        await MushafFontStorage.remove(page);
      } catch (_) {
        // Fall through to the next attempt.
      }
    }

    _fontsFailed.add(page);
    return false;
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

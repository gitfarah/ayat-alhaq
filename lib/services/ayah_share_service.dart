import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart' show SvgStringLoader, vg;
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';
import 'mushaf_svg_service.dart' show AyahHitRegion;

/// One verse of a shared run: its number within the surah, its text, and
/// the translation of THAT verse when one was asked for.
class ShareVerse {
  final int number;
  final String text;
  final String? translation;
  const ShareVerse(this.number, this.text, {this.translation});
}

/// One ayah — or a RUN of consecutive ayahs — packaged for sharing,
/// with where it sits and optionally the tafsir the reader was looking
/// at.
class ShareableAyah {
  final int surahNumber;
  final String surahName;
  final int ayahNumber;
  final String ayahText;

  /// The verses AFTER the first, when the reader chose to share a run.
  /// Empty for the ordinary single-ayah share, which is why the first
  /// verse still lives in [ayahNumber]/[ayahText]: every existing
  /// caller shares exactly one.
  final List<ShareVerse> moreVerses;

  /// The FIRST verse's translation, and the language it is in. The rest
  /// of a run carry their own on [ShareVerse.translation], so a shared
  /// passage is translated verse by verse rather than as one blob.
  final String? translationText;
  final String? translationName;

  /// Whether that language is written right-to-left (Urdu, Farsi), so
  /// the card sets it the way it is read.
  final bool translationRtl;

  /// Tafsir body and the edition it came from. Both null when the
  /// reader is sharing the verse on its own.
  ///
  /// Only ever the FIRST verse's tafsir — see [ShareCardLimits].
  final String? tafsirText;
  final String? tafsirName;

  const ShareableAyah({
    required this.surahNumber,
    required this.surahName,
    required this.ayahNumber,
    required this.ayahText,
    this.moreVerses = const [],
    this.translationText,
    this.translationName,
    this.translationRtl = false,
    this.tafsirText,
    this.tafsirName,
  });

  bool get hasTafsir => (tafsirText?.trim().isNotEmpty ?? false);

  /// True when ANY verse of the run carries a translation — a run can
  /// be part-translated if the edition is missing a verse.
  bool get hasTranslation =>
      (translationText?.trim().isNotEmpty ?? false) ||
      moreVerses.any((v) => v.translation?.trim().isNotEmpty ?? false);

  /// Every verse in the run, in order.
  List<ShareVerse> get verses => [
        ShareVerse(ayahNumber, ayahText, translation: translationText),
        ...moreVerses
      ];

  int get verseCount => 1 + moreVerses.length;

  /// The last ayah number in the run.
  int get lastAyahNumber =>
      moreVerses.isEmpty ? ayahNumber : moreVerses.last.number;

  /// "الآية ٣" for one verse, "الآيات ٣ - ٧" for a run.
  String get referenceLabel => verseCount == 1
      ? 'الآية ${_arabicDigits(ayahNumber)}'
      : 'الآيات ${_arabicDigits(ayahNumber)} - ${_arabicDigits(lastAyahNumber)}';
}

String _arabicDigits(int n) {
  const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return n.toString().split('').map((c) => d[int.parse(c)]).join();
}

/// The ground a shared card is drawn on.
///
/// Every colour the card uses comes from here rather than from the app
/// theme, because the card is not looked at inside the app: it is
/// looked at in someone else's chat, on someone else's screen. A reader
/// who wants a verse on black gets it on black regardless of the theme
/// they happen to be reading in.
class ShareCardStyle {
  /// Stable id, saved in settings and used as the l10n key suffix.
  final String id;

  /// Ground, top to bottom.
  final Color top, bottom;

  /// The verse, the tafsir body, and the app name in the footer.
  final Color ink;

  /// Frame, surah band rules, ayah numbers and the reference line.
  final Color gold;

  /// Fill behind the surah name's cartouche, and the band around it.
  final Color bandFill, bandInner;

  const ShareCardStyle({
    required this.id,
    required this.top,
    required this.bottom,
    required this.ink,
    required this.gold,
    required this.bandFill,
    required this.bandInner,
  });
}

/// The grounds offered in the share sheet, in the order they appear.
/// [kShareBackgrounds.first] is the default and the one every card was
/// drawn on before there was a choice.
const List<ShareCardStyle> kShareBackgrounds = [
  ShareCardStyle(
    id: 'emerald',
    top: AppColors.primaryContainer,
    bottom: AppColors.primary,
    ink: Colors.white,
    gold: AppColors.gold,
    bandFill: Color(0xFF16342A),
    bandInner: AppColors.primary,
  ),
  // The one that was asked for. True black rather than a very dark
  // grey: on an OLED screen the card then has no edges at all, which is
  // the whole appeal.
  ShareCardStyle(
    id: 'black',
    top: Color(0xFF000000),
    bottom: Color(0xFF000000),
    ink: Color(0xFFF5F2EA),
    gold: Color(0xFFD4AF37),
    bandFill: Color(0xFF0B0B0B),
    bandInner: Color(0xFF000000),
  ),
  ShareCardStyle(
    id: 'midnight',
    top: Color(0xFF0B1533),
    bottom: Color(0xFF152449),
    ink: Color(0xFFF2F4FB),
    gold: Color(0xFFC9B071),
    bandFill: Color(0xFF0A1128),
    bandInner: Color(0xFF101C3D),
  ),
  // A light card, for a verse that is going to be printed or set on a
  // pale background — the only one with dark ink.
  ShareCardStyle(
    id: 'parchment',
    top: Color(0xFFFBF4E4),
    bottom: Color(0xFFF2E7CF),
    ink: Color(0xFF2A2418),
    gold: Color(0xFF8A6B25),
    bandFill: Color(0xFFF6EDD8),
    bandInner: Color(0xFFFBF4E4),
  ),
];

ShareCardStyle shareBackgroundById(String? id) => kShareBackgrounds.firstWhere(
      (b) => b.id == id,
      orElse: () => kShareBackgrounds.first,
    );

/// How tall a card may get before it is worth warning about.
class ShareCardLimits {
  /// A card taller than this many times its own width arrives in a chat
  /// as a thin strip: the messenger scales it to fit the bubble WIDTH,
  /// so every extra verse makes all of them smaller rather than making
  /// the card longer. Four screens' worth is where a verse stops being
  /// readable in the preview.
  static const double tallAspect = 4.0;
}

/// One page's worth of a crop: the page picture, and the slice of it in
/// the page's own coordinate space that the shared verses occupy.
class _MushafStrip {
  final ui.Picture picture;
  final double vbMinX, vbMinY, vbW;
  final double top, height;

  const _MushafStrip({
    required this.picture,
    required this.vbMinX,
    required this.vbMinY,
    required this.vbW,
    required this.top,
    required this.height,
  });

  /// Height per unit of width once the strip is scaled to fill a card
  /// column edge to edge, the way a printed line always is.
  double get aspect => height / vbW;
}

/// The REAL printed Hafs V4 page art for a shared verse or run — one
/// strip per PAGE the run crosses, in reading order.
///
/// A run is nearly always one strip; it becomes two when the passage
/// runs over a page turn, and the strips are then stacked with a small
/// gap rather than butted together, because they are genuinely two
/// different leaves of the Mushaf and pretending otherwise would
/// invent a line-break that does not exist.
class _MushafCrop {
  final List<_MushafStrip> strips;
  const _MushafCrop(this.strips);

  /// Card pixels between stacked page-strips.
  static const double gap = 26.0;

  double heightFor(double width) {
    var h = 0.0;
    for (final s in strips) {
      h += width * s.aspect;
    }
    return h + gap * (strips.length - 1);
  }
}

/// Offline surah:ayah → Hafs V4 page-number lookup, built once from the
/// SAME bundled layout the app already ships for the QCF glyph-text
/// pipeline (`assets/quran/mushaf_v4_1441h_layout.json`) — no network
/// needed just to find which page an ayah starts on.
///
/// Also flags every ayah that SPANS a page break. A crop is a strip of
/// ONE page; an ayah whose tail lands on the next page would come out
/// silently truncated, which is a far worse failure than not offering
/// the real-page card at all. [MushafCrop] refuses those and the caller
/// falls back to the text-rendered card, which has no such limit.
class _V4PageIndex {
  static Future<({Map<int, int> firstPage, Set<int> spansPageBreak})>? _future;

  static int _key(int surah, int ayah) => surah * 1000 + ayah;

  static Future<({Map<int, int> firstPage, Set<int> spansPageBreak})> _load() {
    return _future ??= () async {
      final raw = await rootBundle
          .loadString('assets/quran/mushaf_v4_1441h_layout.json');
      final pages =
          (jsonDecode(raw) as Map<String, dynamic>)['pages'] as List<dynamic>;

      final firstPage = <int, int>{};
      final pagesForKey = <int, Set<int>>{};
      for (final p in pages) {
        final pageNum = p['p'] as int;
        for (final line in p['l'] as List<dynamic>) {
          final words = line['w'] as List<dynamic>?;
          if (words == null) continue;
          for (final w in words) {
            final parts = (w[1] as String).split(':');
            final key = _key(int.parse(parts[0]), int.parse(parts[1]));
            firstPage.putIfAbsent(key, () => pageNum);
            (pagesForKey[key] ??= {}).add(pageNum);
          }
        }
      }
      final spans = {
        for (final e in pagesForKey.entries)
          if (e.value.length > 1) e.key
      };
      return (firstPage: firstPage, spansPageBreak: spans);
    }();
  }

  /// The page an ayah STARTS on, or null if it is not in the layout
  /// (should not happen for a real Quranic reference) or it spans a
  /// page break — either way, the caller should fall back to text.
  static Future<int?> singlePageOf(int surah, int ayah) async {
    final idx = await _load();
    final key = _key(surah, ayah);
    if (idx.spansPageBreak.contains(key)) return null;
    return idx.firstPage[key];
  }
}

/// Turns an ayah into something the OS share sheet can carry: either
/// plain text, or a rendered card image with the app's name and logo.
class AyahShareService {
  static const String _appName = 'آيات الحق';

  /// The lookup string the surah-name font turns into surah [n]'s
  /// calligraphic title. Nothing else in that font renders, so getting
  /// this wrong leaves the band silently empty rather than wrong.
  static String surahNameGlyph(int n) => 'surah${n.toString().padLeft(3, '0')}';

  static String _ar(int n) => _arabicDigits(n);

  /// The plain-text form. Ornate Quranic brackets around the verse, the
  /// reference beneath it, then the tafsir when one was asked for —
  /// the layout someone would expect pasted into a chat.
  ///
  /// A RUN of verses is quoted as the Mushaf sets it: one pair of
  /// brackets around the whole passage, with each verse's number after
  /// it, rather than a stack of separately-bracketed lines.
  static String buildText(ShareableAyah a) {
    final quoted = a.verseCount == 1
        ? a.ayahText
        : a.verses.map((v) => '${v.text} ﴿${_ar(v.number)}﴾').join(' ');
    final b = StringBuffer()
      ..writeln('﴿$quoted﴾')
      ..writeln(
          '[${a.surahName} — ${a.verseCount == 1 ? _ar(a.ayahNumber) : '${_ar(a.ayahNumber)}-${_ar(a.lastAyahNumber)}'}]');
    // The translation follows the Arabic and precedes any tafsir: it is
    // the same words in another language, so it belongs against the
    // verse, not filed under commentary.
    if (a.hasTranslation) {
      b
        ..writeln()
        ..writeln('${a.translationName ?? ''}:'.trim());
      for (final v in a.verses) {
        final t = v.translation?.trim();
        if (t == null || t.isEmpty) continue;
        b.writeln(a.verseCount == 1 ? t : '(${v.number}) $t');
      }
    }
    if (a.hasTafsir) {
      b
        ..writeln()
        ..writeln('${a.tafsirName ?? 'التفسير'}:')
        ..writeln(a.tafsirText!.trim());
    }
    b
      ..writeln()
      ..write('— $_appName');
    return b.toString();
  }

  /// Where the share sheet should appear to come from.
  ///
  /// iOS REQUIRES this: Apple validates the origin rect on iPhone too,
  /// not just on iPad, and a missing or zero-sized rect makes the share
  /// sheet fail silently — the call returns as if it worked and nothing
  /// is ever presented. Callers pass the rect of the control that was
  /// tapped; [_safeOrigin] is the last-resort fallback.
  @visibleForTesting
  static Rect safeOrigin(Rect? origin) => _safeOrigin(origin);

  static Rect _safeOrigin(Rect? origin) {
    if (origin != null && origin.width > 0 && origin.height > 0) {
      return origin;
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }

  static Future<void> shareText(ShareableAyah a, {Rect? origin}) =>
      SharePlus.instance.share(ShareParams(
        text: buildText(a),
        subject: '${a.surahName} ${_ar(a.ayahNumber)}',
        sharePositionOrigin: _safeOrigin(origin),
      ));

  /// How tall the card will be, relative to its own width, WITHOUT
  /// rasterising it.
  ///
  /// Shares the layout pass with [renderCard], so the number the share
  /// sheet warns on is the height the reader will really get rather
  /// than a guess from character counts — which would be badly wrong
  /// either way round, since one ayah of Al-Baqarah runs longer than
  /// twenty of Al-Ikhlas.
  static double cardAspect(ShareableAyah a, {ShareCardStyle? style}) =>
      _CardLayout(a, style ?? kShareBackgrounds.first).height / _width;

  /// Whether the card is tall enough that a messenger will shrink it to
  /// an unreadable strip. Drives the hint in the share sheet.
  static bool isCardTooTall(ShareableAyah a, {ShareCardStyle? style}) =>
      cardAspect(a, style: style) > ShareCardLimits.tallAspect;

  /// Renders the card off-screen and hands the PNG to the share sheet.
  ///
  /// Drawn straight onto a canvas rather than screenshotting a widget:
  /// the card must look the same whatever the reader's theme, font size
  /// or screen is, and nothing about it is on screen to capture.
  static Future<void> shareImage(ShareableAyah a,
      {Rect? origin, ShareCardStyle? style}) async {
    final bytes = await renderCard(a, style: style);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}ayah_${a.surahNumber}_${a.ayahNumber}.png');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: '${a.surahName} — ${_ar(a.ayahNumber)}',
      sharePositionOrigin: _safeOrigin(origin),
    ));
  }

  /// Writes the card straight into the device's photo library, under an
  /// album of the app's own — for a reader who wants to keep the verse
  /// rather than send it on.
  ///
  /// Throws [GalException] when the user denies photo access, which the
  /// caller turns into a message rather than a silent no-op.
  static Future<void> saveImageToGallery(ShareableAyah a,
      {ShareCardStyle? style}) async {
    final bytes = await renderCard(a, style: style);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}ayah_${a.surahNumber}_${a.ayahNumber}.png');
    await file.writeAsBytes(bytes, flush: true);
    await Gal.putImage(file.path, album: _appName);
  }

  /// The card's fixed pixel width. Height follows the content.
  static const double _width = 1080.0;

  /// The shareable card as PNG bytes. Public so a widget test can
  /// assert it renders without touching the platform share sheet.
  static Future<Uint8List> renderCard(ShareableAyah a,
      {ShareCardStyle? style}) async {
    final s = style ?? kShareBackgrounds.first;
    // Tried first, and quietly dropped for anything it cannot safely
    // handle yet (a run, a page-spanning ayah, no cache and no
    // network) — see [_tryMushafCrop]. Every one of those falls back
    // to the same Amiri-set verse the card has always used.
    final crop = await _tryMushafCrop(a);
    final l = _CardLayout(a, s, crop: crop);
    final height = l.height;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(_width, height);

    // The chosen ground, with a soft vertical lift so the card reads as
    // a surface rather than a flat rectangle. On black the two stops
    // are equal, which is the point: no gradient, no edges.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, height),
          [s.top, s.bottom],
        ),
    );

    // Hairline gold frame, inset like a Mushaf page border.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(24, 24, _width - 48, height - 48),
          const Radius.circular(28)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = s.gold.withValues(alpha: 0.55),
    );

    var y = _CardLayout.margin;

    // ── Surah banner
    //
    // The ornament is sized around the NAME's own ink, exactly as it is
    // on a page: maxIntrinsicWidth is the name's true drawn width, not
    // the full column the paragraph was laid out in.
    final bandRect = Rect.fromLTWH(
        _CardLayout.margin, y, _CardLayout.contentWidth, l.bannerHeight);
    await _paintSuraBorder(canvas, s, bandRect);
    // Centred in the border's own clear cartouche, not in the band as a
    // whole — the ornament is not symmetrical top to bottom.
    final clear = _CardLayout.clearBoxIn(bandRect);
    canvas.drawParagraph(
        l.surahTitle,
        Offset(_CardLayout.margin,
            clear.top + (clear.height - l.surahTitle.height) / 2));
    y += l.bannerHeight + _CardLayout.gapAfterBanner;

    if (l.mushafCrop != null) {
      _drawMushafCrop(canvas, l.mushafCrop!, s, Offset(_CardLayout.margin, y),
          width: _CardLayout.contentWidth);
    } else {
      canvas.drawParagraph(l.verse!, Offset(_CardLayout.margin, y));
    }
    y += l.verseHeight + _CardLayout.gapAfterVerse;
    canvas.drawParagraph(l.reference, Offset(_CardLayout.margin, y));
    y += l.reference.height;

    // A gold hairline separates each block that is NOT the Quran from
    // the verse above it.
    void rule() {
      canvas.drawRect(
        Rect.fromLTWH(_CardLayout.margin + _CardLayout.contentWidth * 0.25, y,
            _CardLayout.contentWidth * 0.5, 1),
        Paint()..color = s.gold.withValues(alpha: 0.45),
      );
    }

    if (l.translationBody != null) {
      y += _CardLayout.gapBeforeRule;
      rule();
      y += 1 + _CardLayout.gapAfterRule;
      canvas.drawParagraph(l.translationTitle!, Offset(_CardLayout.margin, y));
      y += l.translationTitle!.height + _CardLayout.gapTafsirTitle;
      canvas.drawParagraph(l.translationBody!, Offset(_CardLayout.margin, y));
      y += l.translationBody!.height;
    }

    if (l.tafsirBody != null) {
      y += _CardLayout.gapBeforeRule;
      rule();
      y += 1 + _CardLayout.gapAfterRule;
      canvas.drawParagraph(l.tafsirTitle!, Offset(_CardLayout.margin, y));
      y += l.tafsirTitle!.height + _CardLayout.gapTafsirTitle;
      canvas.drawParagraph(l.tafsirBody!, Offset(_CardLayout.margin, y));
      y += l.tafsirBody!.height;
    }

    // ── Footer.
    //
    // The app's own mark sits on the READING edge (right, with the card
    // set in Arabic) and Apple's badge at the far left, so the two
    // never crowd each other however wide the card's type runs.
    y += _CardLayout.gapBeforeRule;
    final footerTop = y;
    const logoSize = 84.0;
    final logo = await _loadLogo();
    const brandRight = _width - _CardLayout.margin;

    // The app's WORDMARK rather than its name typed out, so the card is
    // signed the way everything else the app puts its name on is.
    final wordmark = await _loadWordmark();
    double markLeft = brandRight;
    if (wordmark != null) {
      // The mark is a LOCKUP — the Arabic name over a Latin subtitle —
      // so its height is shared between two lines of type. Sized off
      // the logo tile beside it rather than off the old name's cap
      // height, or the subtitle comes out as a smudge.
      const markHeight = 88.0;
      final markWidth = wordmark.width * markHeight / wordmark.height;
      markLeft = brandRight - markWidth;
      final dst = Rect.fromLTWH(markLeft,
          footerTop + (logoSize - markHeight) / 2, markWidth, markHeight);
      // The artwork is light-on-transparent, so on the one LIGHT ground
      // it would be all but invisible. There it is drawn as a
      // silhouette in the card's own ink instead — the lockup keeps its
      // shape, and the reader gets something they can actually see.
      final onLight = s.ink.computeLuminance() < 0.5;
      canvas.drawImageRect(
        wordmark,
        Rect.fromLTWH(
            0, 0, wordmark.width.toDouble(), wordmark.height.toDouble()),
        dst,
        Paint()
          ..colorFilter =
              onLight ? ColorFilter.mode(s.ink, BlendMode.srcIn) : null,
      );
    } else {
      // No wordmark: fall back to the name set in type. The paragraph
      // is right-ALIGNED inside a box far wider than the name, so it
      // must be positioned by that box's width — offsetting by the ink
      // width instead pushes it clean off the card.
      canvas.drawParagraph(
          l.brand, Offset(brandRight - l.brand.width, footerTop + 14));
      markLeft = brandRight - l.brand.maxIntrinsicWidth;
    }

    if (logo != null) {
      final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
              markLeft - 20 - logoSize, footerTop, logoSize, logoSize),
          const Radius.circular(18));
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        rrect.outerRect,
        Paint(),
      );
      canvas.restore();
    }
    await _paintAppStoreBadge(canvas, s,
        left: _CardLayout.margin, footerTop: footerTop, boxHeight: logoSize);

    final picture = recorder.endRecording();
    final image = await picture.toImage(_width.round(), height.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// Apple's "Download on the App Store" badge, bottom-left.
  ///
  /// Drawn from Apple's own SVG and only ever SCALED — never recoloured,
  /// re-typeset, stretched or re-framed, all of which Apple's identity
  /// guidelines forbid. Nothing is added behind it either: the artwork
  /// Apple ships already carries its own light hairline border, so it
  /// separates itself from every one of these grounds, black included.
  ///
  /// A missing or unparseable badge costs the reader nothing but the
  /// badge — the card is still the point.
  static Future<void> _paintAppStoreBadge(
    Canvas canvas,
    ShareCardStyle style, {
    required double left,
    required double footerTop,
    required double boxHeight,
  }) async {
    final badge = await _loadBadge();
    if (badge == null) return;

    // Scaled from the card's WIDTH, not to a fixed pixel size, so the
    // badge keeps the same visual weight whatever the card grows to —
    // and clamped, so a very long passage can never leave it either
    // hair-thin or overbearing.
    final targetWidth =
        (_width * 0.235).clamp(200.0, _CardLayout.contentWidth * 0.4);
    final scale = targetWidth / badge.size.width;
    final targetHeight = badge.size.height * scale;
    // Sits on the same optical line as the app mark opposite it.
    final top = footerTop + (boxHeight - targetHeight) / 2;

    canvas.save();
    canvas.translate(left, top);
    canvas.scale(scale);
    canvas.drawPicture(badge.picture);
    canvas.restore();
  }

  /// Fixed source: Hafs V4 only, plain print. The four riwayat
  /// (Warsh/Qalon/Shubah/Douri) do not share this page layout, and a
  /// reader sharing from one of them gets the SAME V4 crop everyone
  /// else does rather than a mismatched one from their own edition —
  /// the ayah is the point, not which print it was tapped from.
  ///
  /// "Plain print" is not a choice made here: quranpedia's V4 SVG has
  /// exactly one fill colour in the whole page (#231f20, checked by
  /// hand). Tajweed colouring in this app is a runtime overlay applied
  /// only to the REFLOWING text view; the page artwork was never
  /// coloured to begin with, so there is nothing to strip.
  ///
  /// jsDelivr's GitHub mirror, NOT raw.githubusercontent.com directly.
  /// Found the hard way: a fresh install has no cached V4 pages, so the
  /// very first share of an uncached page always needs this fetch to
  /// succeed — and raw.githubusercontent.com answered every request
  /// with 429 for a stretch while this was being tested, silently
  /// falling every share back to the Amiri card with no error surfaced
  /// anywhere. jsDelivr serves byte-identical content (checked) from a
  /// CDN built for exactly this traffic pattern and was not rate-
  /// limited at the same moment raw.githubusercontent.com was.
  static const String _v4Repo =
      'https://cdn.jsdelivr.net/gh/quranpedia/quran-svg@main/mushafs/hafs/kfqc';

  /// Tried only if jsDelivr itself fails — the exact host that turned
  /// out to be the problem, but a second independent source is cheap
  /// insurance against jsDelivr having its own bad day, and costs
  /// nothing when the first attempt succeeds, which is the normal case.
  static const String _v4RepoFallback =
      'https://raw.githubusercontent.com/quranpedia/quran-svg/main/mushafs/hafs/kfqc';

  static String _pad3(int n) => n.toString().padLeft(3, '0');

  static final Map<int, (String svg, String json)> _v4PageMemCache = {};

  /// The raw SVG + region JSON for a Hafs V4 page, cheapest source
  /// first:
  ///  1. memory, if this session already fetched it;
  ///  2. the READER'S OWN Mushaf cache, read-only — most readers on the
  ///     default edition already have some or all of these 604 pages on
  ///     disk from ordinary browsing or a bulk download, so a share
  ///     often costs nothing;
  ///  3. this feature's OWN cache folder, separate from the reader's —
  ///     writing here rather than into their cache means a share can
  ///     never race a bulk-download clear or an edition switch;
  ///  4. the network, cached into (3) for next time.
  /// Null if none of that produces both files — offline with an
  /// uncached page, most likely — and the caller falls back to text.
  static Future<(String svg, String json)?> _loadV4PageRaw(int page) async {
    final cached = _v4PageMemCache[page];
    if (cached != null) return cached;

    Future<(String, String)?> tryDir(Directory dir) async {
      final svgF = File('${dir.path}/${_pad3(page)}.svg');
      final jsonF = File('${dir.path}/${_pad3(page)}.json');
      if (await svgF.exists() && await jsonF.exists()) {
        return (await svgF.readAsString(), await jsonF.readAsString());
      }
      return null;
    }

    try {
      if (!kIsWeb) {
        final docs = await getApplicationDocumentsDirectory();
        final readerCache =
            await tryDir(Directory('${docs.path}/mushaf_pages/hafs'));
        if (readerCache != null) {
          _v4PageMemCache[page] = readerCache;
          return readerCache;
        }
        final ownCache =
            await tryDir(Directory('${docs.path}/share_card_v4_cache'));
        if (ownCache != null) {
          _v4PageMemCache[page] = ownCache;
          return ownCache;
        }
      }

      Future<(String, String)?> fetchFrom(String repo) async {
        final results = await Future.wait([
          http.get(Uri.parse('$repo/svg/${_pad3(page)}.svg')),
          http.get(Uri.parse('$repo/json/${_pad3(page)}.json')),
        ]).timeout(const Duration(seconds: 12));
        if (results[0].statusCode != 200 || results[1].statusCode != 200) {
          return null;
        }
        return (results[0].body, results[1].body);
      }

      final pair = await fetchFrom(_v4Repo) ?? await fetchFrom(_v4RepoFallback);
      if (pair == null) return null;
      _v4PageMemCache[page] = pair;

      if (!kIsWeb) {
        try {
          final docs = await getApplicationDocumentsDirectory();
          final dir = Directory('${docs.path}/share_card_v4_cache')
            ..createSync(recursive: true);
          await File('${dir.path}/${_pad3(page)}.svg').writeAsString(pair.$1);
          await File('${dir.path}/${_pad3(page)}.json').writeAsString(pair.$2);
        } catch (_) {
          // Cache write failed — the page still shares fine this once.
        }
      }
      return pair;
    } catch (e) {
      debugPrint('share card: Hafs V4 page $page unavailable ($e)');
      return null;
    }
  }

  /// The most pages one shared run will be cropped from. A passage
  /// long enough to cross this many leaves is already far past the
  /// height at which a messenger shrinks the card to a strip, so it
  /// takes the text card instead of costing several page fetches.
  static const int _maxCropPages = 3;

  /// The crop for a verse or a run, or null if anything about it is not
  /// safe to use — an ayah missing from the layout, missing region
  /// data, too many pages, or no network/cache for a page. Every one of
  /// those falls back to the text-rendered verse, which always works.
  static Future<_MushafCrop?> _tryMushafCrop(ShareableAyah a) async {
    try {
      // Group the run's verses by the page they sit on, in reading
      // order. Nearly always one page; two when the passage crosses a
      // page turn.
      final byPage = <int, List<int>>{};
      for (final v in a.verses) {
        final page = await _V4PageIndex.singlePageOf(a.surahNumber, v.number);
        if (page == null) return null;
        (byPage[page] ??= []).add(v.number);
      }
      if (byPage.isEmpty || byPage.length > _maxCropPages) return null;

      final pages = byPage.keys.toList()..sort();
      final strips = <_MushafStrip>[];
      for (final page in pages) {
        final strip = await _stripFor(a.surahNumber, byPage[page]!, page);
        if (strip == null) return null;
        strips.add(strip);
      }
      return _MushafCrop(strips);
    } catch (e) {
      debugPrint('share card: Mushaf crop unavailable ($e)');
      return null;
    }
  }

  /// One page's strip: the lines [ayahs] occupy on [page], cut on the
  /// cleanest rows the print offers.
  static Future<_MushafStrip?> _stripFor(
      int surah, List<int> ayahs, int page) async {
    final raw = await _loadV4PageRaw(page);
    if (raw == null) return null;
    final (svgContent, jsonContent) = raw;

    final regions = (jsonDecode(jsonContent) as List)
        .map((e) => AyahHitRegion.fromJson(e as Map<String, dynamic>))
        .toList();

    // Every y the shared verses touch, and every y everything else on
    // the page touches. The polygons are staircases, so their corner
    // y-values are exactly the print's line boundaries.
    final ourYs = <double>{};
    final otherYs = <double>{};
    for (final r in regions) {
      final mine = r.surahNumber == surah && ayahs.contains(r.ayahNumber);
      for (final ring in r.rings) {
        for (var i = 1; i < ring.length; i += 2) {
          (mine ? ourYs : otherYs).add(ring[i]);
        }
      }
    }
    if (ourYs.isEmpty) return null;

    final sorted = ourYs.toList()..sort();
    final minY = sorted.first;
    final maxY = sorted.last;
    if (maxY <= minY) return null;

    final vb = RegExp(
            r'viewBox="\s*(-?[\d.]+)[,\s]+(-?[\d.]+)[,\s]+(-?[\d.]+)[,\s]+(-?[\d.]+)\s*"')
        .firstMatch(svgContent);
    double n(int g, double f) =>
        vb == null ? f : (double.tryParse(vb.group(g)!) ?? f);
    final vbMinX = n(1, 0), vbMinY = n(2, 0), vbW = n(3, 235);

    // A band's TOP is trustworthy; its BOTTOM is not.
    //
    // Measured on the shipped fixtures: on page 2 ayah 4's band ends at
    // y=160.15, but ayah 5's band — the next line — already begins at
    // 158.53, and the damma and صلے that ride high above ayah 5's
    // letters sit in between. Cutting on ayah 4's own bottom therefore
    // drags those two marks along, which is exactly the "harakat from
    // the line below" in the report. On page 3 the same pair reads
    // 82.11 and 82.37: the bottom UNDERSHOOTS instead. The bottoms
    // disagree with each other by up to a mark's height; the tops
    // agree with the print every time.
    //
    // So the strip ends where the NEXT line begins, taken from that
    // line's own band top, and only falls back to our own bottom when
    // there is no next line (last verses on the page, nothing below to
    // bleed in).
    //
    // Rasterising and cutting on the emptiest row was tried in between
    // and is worse: page 2 has NO empty row between those lines — the
    // profile bottoms out at 12-14 lit pixels and never reaches zero —
    // so "emptiest" picked y=162.0, further into ayah 5 than the
    // nominal bottom it was meant to improve on.
    final epsilon = vbW * 0.01;
    final ourLastLineTop =
        sorted.length >= 2 ? sorted[sorted.length - 2] : minY;
    double? nextLineTop;
    for (final y in otherYs) {
      if (y > ourLastLineTop + epsilon &&
          (nextLineTop == null || y < nextLineTop)) {
        nextLineTop = y;
      }
    }
    final top = minY;
    final bottom = nextLineTop ?? maxY;
    if (bottom <= top) return null;

    final info = await vg.loadPicture(SvgStringLoader(svgContent), null);
    return _MushafStrip(
      picture: info.picture,
      vbMinX: vbMinX,
      vbMinY: vbMinY,
      vbW: vbW,
      top: top,
      height: bottom - top,
    );
  }

  /// Draws the crop into the card, each page-strip scaled to fill
  /// [width] edge to edge — the way a printed line always is — and
  /// recoloured to the card's own ink so it reads on all four grounds.
  ///
  /// The FULL page picture is handed in every time (cropping happens
  /// only via clip + transform here, not by pre-slicing the picture):
  /// Skia clips cheaply, and it is one `drawPicture` call either way.
  static void _drawMushafCrop(
      Canvas canvas, _MushafCrop crop, ShareCardStyle style, Offset dst,
      {required double width}) {
    var y = dst.dy;
    for (final strip in crop.strips) {
      final scale = width / strip.vbW;
      final height = strip.height * scale;
      canvas.save();
      canvas.translate(dst.dx, y);
      canvas.clipRect(Rect.fromLTWH(0, 0, width, height));
      canvas.translate(0, -strip.top * scale);
      canvas.scale(scale);
      canvas.translate(-strip.vbMinX, -strip.vbMinY);
      canvas.saveLayer(null,
          Paint()..colorFilter = ColorFilter.mode(style.ink, BlendMode.srcIn));
      canvas.drawPicture(strip.picture);
      canvas.restore();
      canvas.restore();
      y += height + _MushafCrop.gap;
    }
  }

  /// The ornamental sura band the surah name is headed with.
  ///
  /// "Sura border" by Hadysylmy, from Wikipedia, CC BY-SA 4.0. It is a
  /// single monochrome path, so it is tinted to each card's gold with a
  /// srcIn layer rather than being redrawn — and because that tinting
  /// makes every drawn frame a DERIVATIVE, the licence travels with the
  /// app: see the About screen's credits, which name the author and the
  /// licence. Do not drop that credit without also dropping this asset.
  static Future<void> _paintSuraBorder(
      Canvas canvas, ShareCardStyle style, Rect band) async {
    final border = await _loadSuraBorder();
    if (border == null) return;
    canvas.save();
    canvas.translate(band.left, band.top);
    canvas.scale(band.width / border.size.width);
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, border.size.width, border.size.height),
      Paint()..colorFilter = ColorFilter.mode(style.gold, BlendMode.srcIn),
    );
    canvas.drawPicture(border.picture);
    canvas.restore();
    canvas.restore();
  }

  static ui.Picture? _borderPicture;
  static Size? _borderSize;

  static Future<({ui.Picture picture, Size size})?> _loadSuraBorder() async {
    if (_borderPicture != null && _borderSize != null) {
      return (picture: _borderPicture!, size: _borderSize!);
    }
    try {
      final raw = await rootBundle.loadString('assets/icon/sura_border.svg');
      final info = await vg.loadPicture(SvgStringLoader(raw), null);
      _borderPicture = info.picture;
      _borderSize = info.size;
      return (picture: info.picture, size: info.size);
    } catch (e) {
      debugPrint('share card: sura border unavailable ($e)');
      return null;
    }
  }

  static ui.Picture? _badgePicture;
  static Size? _badgeSize;

  static Future<({ui.Picture picture, Size size})?> _loadBadge() async {
    if (_badgePicture != null && _badgeSize != null) {
      return (picture: _badgePicture!, size: _badgeSize!);
    }
    try {
      final raw =
          await rootBundle.loadString('assets/icon/app_store_badge.svg');
      final info = await vg.loadPicture(SvgStringLoader(raw), null);
      _badgePicture = info.picture;
      _badgeSize = info.size;
      return (picture: info.picture, size: info.size);
    } catch (e) {
      debugPrint('share card: App Store badge unavailable ($e)');
      return null;
    }
  }

  static ui.Image? _logoCache;
  static ui.Image? _wordmarkCache;

  static Future<ui.Image?> _loadLogo() async =>
      _logoCache ??= await _loadImage('assets/icon/app_icon.png');

  static Future<ui.Image?> _loadWordmark() async =>
      _wordmarkCache ??= await _loadImage('assets/icon/wordmark.png');

  static Future<ui.Image?> _loadImage(String asset) async {
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    } catch (e) {
      // A missing mark must not cost the reader the whole card.
      debugPrint('share card: $asset unavailable ($e)');
      return null;
    }
  }

  static ui.Paragraph paragraph(
    String text, {
    required String fontFamily,
    required double fontSize,
    required double height,
    required Color color,
    required TextAlign align,
    required double maxWidth,
    bool bold = false,
    bool rtl = true,
    List<ui.FontFeature>? fontFeatures,
  }) =>
      _paragraph(text,
          fontFamily: fontFamily,
          fontSize: fontSize,
          height: height,
          color: color,
          align: align,
          maxWidth: maxWidth,
          bold: bold,
          rtl: rtl,
          fontFeatures: fontFeatures);

  static ui.Paragraph _paragraph(
    String text, {
    required String fontFamily,
    required double fontSize,
    required double height,
    required Color color,
    required TextAlign align,
    required double maxWidth,
    bool bold = false,
    bool rtl = true,
    List<ui.FontFeature>? fontFeatures,
  }) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: align,
      // The card is an Arabic object, so everything defaults to RTL —
      // but a Latin-script translation laid out RTL puts its full stops
      // on the wrong end of every line.
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: height,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    ))
      ..pushStyle(ui.TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: height,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontFeatures: fontFeatures,
      ))
      ..addText(text);
    return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }
}

/// Everything about a card that depends on its CONTENT: the laid-out
/// paragraphs and the height they add up to.
///
/// Split out from the drawing so the share sheet can ask how tall a card
/// will be before one is ever rendered. The warning about a run of
/// verses running too long is then the height the reader will really
/// get, measured by the same code that draws it — not a guess from
/// character counts, which would be badly wrong in both directions.
class _CardLayout {
  static const double margin = 64.0;
  static const double contentWidth = AyahShareService._width - margin * 2;

  static const double gapAfterBanner = 52.0;
  static const double gapAfterVerse = 30.0;
  static const double gapBeforeRule = 48.0;
  static const double gapAfterRule = 42.0;
  static const double gapTafsirTitle = 22.0;
  static const double footerHeight = 104.0;

  // Type is sized for a card read at THUMBNAIL size in a chat, not on a
  // page: an early cut was laid out at reading sizes and came out
  // unreadable once a messenger scaled the image down to a bubble.
  //
  // The surah name asks for far more than a text face would at the same
  // apparent weight — the name font's ink sits well inside its em box —
  // and the tafsir is the block people actually read at length, so both
  // are set larger than the rest.
  /// The sura border's own proportions, from its viewBox (16320x2000),
  /// and the clear cartouche inside it as fractions of the band. The
  /// name is sized to THAT box, not to the band: the ornament fills
  /// everything either side of it.
  static const double borderAspect = 16320 / 2000;
  static const Rect borderClear = Rect.fromLTRB(0.265, 0.08, 0.735, 0.89);

  /// Roughly how much of the surah-name font's EM BOX its ink actually
  /// fills, vertically. The face sets its calligraphy small inside a
  /// tall box, so a name sized to a box that matches the cartouche
  /// comes out about this fraction of the cartouche's height.
  static const double inkInEm = 0.62;

  static Rect clearBoxIn(Rect band) => Rect.fromLTRB(
        band.left + band.width * borderClear.left,
        band.top + band.height * borderClear.top,
        band.left + band.width * borderClear.right,
        band.top + band.height * borderClear.bottom,
      );

  static const double wantedBannerTitleSize = 132.0;
  static const double verseSize = 74.0;
  static const double referenceSize = 44.0;
  static const double tafsirTitleSize = 48.0;
  static const double tafsirBodySize = 54.0;
  static const double translationSize = 50.0;
  static const double ayahMarkSize = 52.0;

  final ui.Paragraph surahTitle;

  /// Null when [mushafCrop] is what gets drawn instead — the two are
  /// mutually exclusive, and [verseHeight] is the one either side of
  /// the drawing code should actually read.
  final ui.Paragraph? verse;
  final _MushafCrop? mushafCrop;
  final double verseHeight;

  final ui.Paragraph reference;
  final ui.Paragraph? translationTitle;
  final ui.Paragraph? translationBody;
  final ui.Paragraph? tafsirTitle;
  final ui.Paragraph? tafsirBody;

  /// Drawn only when the wordmark image cannot be had.
  final ui.Paragraph brand;

  /// The size the name was actually SET at — see the constructor.
  final double bannerTitleSize;
  final double bannerHeight;
  final double height;

  factory _CardLayout(ShareableAyah a, ShareCardStyle s, {_MushafCrop? crop}) {
    // The name is SET, not typed: "surah005" is a ligature in the
    // surah-name font and comes out as the calligraphic
    // "سُورَةُ المَائِدَة" a printed Mushaf heads its pages with.
    //
    // Laid out across the FULL content width so the paragraph's centre
    // coincides with the band's; at a narrower width it was centred
    // inside its own box and sat off-centre in the cartouche.
    ui.Paragraph setName(double size) => AyahShareService.paragraph(
          AyahShareService.surahNameGlyph(a.surahNumber),
          fontFamily: 'SurahNameV2',
          fontSize: size,
          height: 1.0,
          color: s.gold,
          align: TextAlign.center,
          maxWidth: contentWidth,
          fontFeatures: const [ui.FontFeature.enable('liga')],
        );

    // The band is the ornamental sura border, whose height follows from
    // its own proportions once it spans the column.
    const bannerHeight = contentWidth / borderAspect;
    final clear =
        clearBoxIn(const Rect.fromLTWH(0, 0, contentWidth, bannerHeight));

    // One ligature cannot wrap, so an oversized name does not reflow —
    // it runs off the card. So: set it as large as the cartouche is
    // TALL, then, if the drawn ink is too wide for the cartouche, set
    // it again smaller by exactly the overflow. Every name comes out as
    // large as it can be inside the frame, and the long ones
    // (المطففين, المؤمنون) shrink only as much as they must.
    // Sized against the cartouche's height TIMES inkInEm, not against
    // it directly: this face draws its ink well inside its em box, so
    // fitting the box to the cartouche left the cartouche looking half
    // empty and the name smaller than it had been before the border
    // existed. Measured off the rendered card, not guessed.
    var titleSize = math.min(wantedBannerTitleSize, clear.height / inkInEm);
    var title = setName(titleSize);
    if (title.maxIntrinsicWidth > clear.width) {
      titleSize *= clear.width / title.maxIntrinsicWidth;
      title = setName(titleSize);
    }

    // Real Mushaf art when it is available and safe (see
    // [AyahShareService._tryMushafCrop]); the Amiri-set paragraph
    // otherwise. Exactly one of [verse]/[mushafCrop] is non-null.
    final verse = crop == null ? _verses(a, s) : null;
    final verseHeight =
        crop != null ? crop.heightFor(contentWidth) : verse!.height;
    final reference = AyahShareService.paragraph(
      a.referenceLabel,
      fontFamily: 'QuranHafs',
      fontSize: referenceSize,
      height: 1.4,
      color: s.gold,
      align: TextAlign.center,
      maxWidth: contentWidth,
    );
    // The translation, verse by verse. Set in the app's UI face rather
    // than the Quran face — it is not Quran, and setting it in the same
    // hand would say that it is.
    final translationTitle = a.hasTranslation
        ? AyahShareService.paragraph(
            a.translationName ?? '',
            fontFamily: '.SF Pro Text',
            fontSize: tafsirTitleSize,
            height: 1.4,
            color: s.gold,
            align: TextAlign.center,
            maxWidth: contentWidth,
            bold: true,
          )
        : null;
    final translationBody = a.hasTranslation
        ? AyahShareService.paragraph(
            [
              for (final v in a.verses)
                if ((v.translation?.trim() ?? '').isNotEmpty)
                  a.verseCount == 1
                      ? v.translation!.trim()
                      : '(${v.number}) ${v.translation!.trim()}'
            ].join('\n'),
            fontFamily: '.SF Pro Text',
            fontSize: translationSize,
            height: 1.6,
            color: s.ink.withValues(alpha: 0.94),
            // Follows the language: a Latin-script translation reads
            // from the left, Urdu from the right.
            align: a.translationRtl ? TextAlign.right : TextAlign.left,
            maxWidth: contentWidth,
            rtl: a.translationRtl,
          )
        : null;
    final tafsirTitle = a.hasTafsir
        ? AyahShareService.paragraph(
            a.tafsirName ?? 'التفسير',
            fontFamily: '.SF Pro Text',
            fontSize: tafsirTitleSize,
            height: 1.4,
            color: s.gold,
            align: TextAlign.center,
            maxWidth: contentWidth,
            bold: true,
          )
        : null;
    final tafsirBody = a.hasTafsir
        ? AyahShareService.paragraph(
            a.tafsirText!.trim(),
            fontFamily: '.SF Pro Text',
            fontSize: tafsirBodySize,
            height: 1.7,
            color: s.ink.withValues(alpha: 0.94),
            align: TextAlign.right,
            maxWidth: contentWidth,
          )
        : null;
    final brand = AyahShareService.paragraph(
      AyahShareService._appName,
      fontFamily: 'QuranHafs',
      fontSize: 42,
      height: 1.3,
      color: s.ink,
      align: TextAlign.right,
      maxWidth: contentWidth - 120,
    );

    var height = margin +
        bannerHeight +
        gapAfterBanner +
        verseHeight +
        gapAfterVerse +
        reference.height;
    if (translationBody != null) {
      height += gapBeforeRule +
          1 +
          gapAfterRule +
          translationTitle!.height +
          gapTafsirTitle +
          translationBody.height;
    }
    if (tafsirBody != null) {
      height += gapBeforeRule +
          1 +
          gapAfterRule +
          tafsirTitle!.height +
          gapTafsirTitle +
          tafsirBody.height;
    }
    height += gapBeforeRule + footerHeight + margin * 0.4;

    return _CardLayout._(
      surahTitle: title,
      verse: verse,
      mushafCrop: crop,
      verseHeight: verseHeight,
      reference: reference,
      translationTitle: translationTitle,
      translationBody: translationBody,
      tafsirTitle: tafsirTitle,
      tafsirBody: tafsirBody,
      brand: brand,
      bannerTitleSize: titleSize,
      bannerHeight: bannerHeight,
      height: height,
    );
  }

  /// The verse, or the whole run, in one paragraph.
  ///
  /// A run is set the way the Mushaf sets it — the verses flow on, each
  /// closed by its own number in an ornate medallion — rather than as a
  /// stack of separately bracketed quotes. The medallion is a glyph of
  /// the KFGQPC ayah-mark face, the same one the reflowing reader uses,
  /// so the numbers come out enclosed instead of as bare digits.
  static ui.Paragraph _verses(ShareableAyah a, ShareCardStyle s) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      fontFamily: 'QuranHafs',
      fontSize: verseSize,
      height: 2.0,
    ));
    final verseStyle = ui.TextStyle(
      color: s.ink,
      fontFamily: 'QuranHafs',
      fontSize: verseSize,
      height: 2.0,
    );
    final markStyle = ui.TextStyle(
      color: s.gold,
      fontFamily: 'QuranAyahMark',
      fontSize: ayahMarkSize,
      height: 2.0,
    );

    builder
      ..pushStyle(verseStyle)
      ..addText('﴿');
    final verses = a.verses;
    for (var i = 0; i < verses.length; i++) {
      builder.addText(verses[i].text);
      // A single shared verse keeps its number on the reference line
      // below, where it always was; numbering one verse inline would
      // print it twice.
      if (verses.length > 1) {
        builder
          ..pop()
          ..pushStyle(markStyle)
          ..addText(' ${_arabicDigits(verses[i].number)} ')
          ..pop()
          ..pushStyle(verseStyle);
      }
    }
    builder.addText('﴾');
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: contentWidth));
  }

  const _CardLayout._({
    required this.surahTitle,
    required this.verse,
    required this.mushafCrop,
    required this.verseHeight,
    required this.reference,
    required this.translationTitle,
    required this.translationBody,
    required this.tafsirTitle,
    required this.tafsirBody,
    required this.brand,
    required this.bannerTitleSize,
    required this.bannerHeight,
    required this.height,
  });
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart' show SvgStringLoader, vg;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';
import '../widgets/surah_banner_painter.dart';

/// One verse of a shared run: its number within the surah and its text.
class ShareVerse {
  final int number;
  final String text;
  const ShareVerse(this.number, this.text);
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
    this.tafsirText,
    this.tafsirName,
  });

  bool get hasTafsir => (tafsirText?.trim().isNotEmpty ?? false);

  /// Every verse in the run, in order.
  List<ShareVerse> get verses =>
      [ShareVerse(ayahNumber, ayahText), ...moreVerses];

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
    final l = _CardLayout(a, s);
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
    paintSurahBand(
      canvas,
      band: bandRect,
      ink: Rect.fromCenter(
        center: bandRect.center,
        width: l.surahTitle.maxIntrinsicWidth,
        height: l.bannerTitleSize,
      ),
      // The card's own ground stands in for the page colour, so the
      // band belongs to the card the way it belongs to a leaf.
      palette: SurahBandPalette(
        bandFill: s.bandFill,
        innerFill: s.bandInner,
        rule: s.gold.withValues(alpha: 0.85),
        gold: s.gold,
      ),
    );
    canvas.drawParagraph(
        l.surahTitle,
        Offset(_CardLayout.margin,
            y + (l.bannerHeight - l.surahTitle.height) / 2));
    y += l.bannerHeight + _CardLayout.gapAfterBanner;

    canvas.drawParagraph(l.verse, Offset(_CardLayout.margin, y));
    y += l.verse.height + _CardLayout.gapAfterVerse;
    canvas.drawParagraph(l.reference, Offset(_CardLayout.margin, y));
    y += l.reference.height;

    if (l.tafsirBody != null) {
      y += _CardLayout.gapBeforeRule;
      canvas.drawRect(
        Rect.fromLTWH(_CardLayout.margin + _CardLayout.contentWidth * 0.25, y,
            _CardLayout.contentWidth * 0.5, 1),
        Paint()..color = s.gold.withValues(alpha: 0.45),
      );
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
    // The paragraph is right-ALIGNED inside a box far wider than the
    // name, so it has to be positioned by that box's width — offsetting
    // by the ink width instead pushes the name off the card entirely,
    // which is exactly what it did until it was rendered and looked at.
    final brandInk = l.brand.maxIntrinsicWidth;

    canvas.drawParagraph(
        l.brand, Offset(brandRight - l.brand.width, footerTop + 14));
    if (logo != null) {
      final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(brandRight - brandInk - 20 - logoSize, footerTop,
              logoSize, logoSize),
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

  static Future<ui.Image?> _loadLogo() async {
    if (_logoCache != null) return _logoCache;
    try {
      final data = await rootBundle.load('assets/icon/app_icon.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _logoCache = frame.image;
      return _logoCache;
    } catch (e) {
      // A missing logo must not cost the reader the whole card.
      debugPrint('share card: logo unavailable ($e)');
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
    List<ui.FontFeature>? fontFeatures,
  }) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: align,
      textDirection: TextDirection.rtl,
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
  static const double wantedBannerTitleSize = 132.0;
  static const double verseSize = 74.0;
  static const double referenceSize = 44.0;
  static const double tafsirTitleSize = 48.0;
  static const double tafsirBodySize = 54.0;
  static const double ayahMarkSize = 52.0;

  final ui.Paragraph surahTitle;
  final ui.Paragraph verse;
  final ui.Paragraph reference;
  final ui.Paragraph? tafsirTitle;
  final ui.Paragraph? tafsirBody;
  final ui.Paragraph brand;

  /// The size the name was actually SET at — see the constructor.
  final double bannerTitleSize;
  final double bannerHeight;
  final double height;

  factory _CardLayout(ShareableAyah a, ShareCardStyle s) {
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

    // One ligature cannot wrap, so an oversized name does not reflow —
    // it runs off the card. The long names are the reason this is not
    // simply a constant: set it at the size wanted, and if the drawn
    // ink is wider than the cartouche can hold, set it again smaller by
    // exactly the overflow. Every name is then as large as IT can be.
    var titleSize = wantedBannerTitleSize;
    var title = setName(titleSize);
    const maxInk = contentWidth * 0.78;
    if (title.maxIntrinsicWidth > maxInk) {
      titleSize *= maxInk / title.maxIntrinsicWidth;
      title = setName(titleSize);
    }

    final verse = _verses(a, s);
    final reference = AyahShareService.paragraph(
      a.referenceLabel,
      fontFamily: 'QuranHafs',
      fontSize: referenceSize,
      height: 1.4,
      color: s.gold,
      align: TextAlign.center,
      maxWidth: contentWidth,
    );
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

    // The banner is the SAME ornamental band the Mushaf pages are
    // headed with — cartouche, doubled keyline and end florets.
    final bannerHeight = title.height * 2.0;

    var height = margin +
        bannerHeight +
        gapAfterBanner +
        verse.height +
        gapAfterVerse +
        reference.height;
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
      reference: reference,
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
    required this.reference,
    required this.tafsirTitle,
    required this.tafsirBody,
    required this.brand,
    required this.bannerTitleSize,
    required this.bannerHeight,
    required this.height,
  });
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/quran_page_meta.dart';
import '../theme.dart';
import '../widgets/surah_banner_painter.dart';

/// One ayah packaged for sharing — the verse, where it sits, and
/// optionally the tafsir the reader was looking at.
class ShareableAyah {
  final int surahNumber;
  final String surahName;
  final int ayahNumber;
  final String ayahText;

  /// Tafsir body and the edition it came from. Both null when the
  /// reader is sharing the verse on its own.
  final String? tafsirText;
  final String? tafsirName;

  const ShareableAyah({
    required this.surahNumber,
    required this.surahName,
    required this.ayahNumber,
    required this.ayahText,
    this.tafsirText,
    this.tafsirName,
  });

  bool get hasTafsir => (tafsirText?.trim().isNotEmpty ?? false);
}

/// Turns an ayah into something the OS share sheet can carry: either
/// plain text, or a rendered card image with the app's name and logo.
class AyahShareService {
  static const String _appName = 'آيات الحق';

  static String _ar(int n) {
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

  /// The plain-text form. Ornate Quranic brackets around the verse, the
  /// reference beneath it, then the tafsir when one was asked for —
  /// the layout someone would expect pasted into a chat.
  static String buildText(ShareableAyah a) {
    final b = StringBuffer()
      ..writeln('﴿${a.ayahText}﴾')
      ..writeln('[${a.surahName} — ${_ar(a.ayahNumber)}]');
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

  /// Renders the card off-screen and hands the PNG to the share sheet.
  ///
  /// Drawn straight onto a canvas rather than screenshotting a widget:
  /// the card must look the same whatever the reader's theme, font size
  /// or screen is, and nothing about it is on screen to capture.
  static Future<void> shareImage(ShareableAyah a, {Rect? origin}) async {
    final bytes = await renderCard(a);
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
  static Future<void> saveImageToGallery(ShareableAyah a) async {
    final bytes = await renderCard(a);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}ayah_${a.surahNumber}_${a.ayahNumber}.png');
    await file.writeAsBytes(bytes, flush: true);
    await Gal.putImage(file.path, album: _appName);
  }

  /// The shareable card as PNG bytes. Public so a widget test can
  /// assert it renders without touching the platform share sheet.
  static Future<Uint8List> renderCard(ShareableAyah a) async {
    const width = 1080.0;
    const margin = 64.0;
    const contentWidth = width - margin * 2;

    // Type is sized for a card read at thumbnail size in a chat, not on
    // a page — the first cut was laid out at reading sizes and came out
    // unreadably small once the image was scaled to fit a message.
    const bannerTitleSize = 46.0;
    const verseSize = 74.0;
    const tafsirTitleSize = 40.0;
    const tafsirBodySize = 42.0;

    // Lay every text block out first: the card's height follows its
    // content, so a long tafsir grows the image instead of being cut.
    // The band is read as calligraphy, so it takes the fully voweled
    // name the Mushaf's own title bands use — not the bare navigation
    // label the caller happens to hold, which is what made the card's
    // header look like a different typeface from the page's.
    //
    // Laid out across the FULL content width so the paragraph's centre
    // coincides with the band's; at a narrower width it was centred
    // inside its own box and sat off-centre in the cartouche.
    final surahTitle = _paragraph(
      QuranPageMeta.voweledSurahName(a.surahNumber),
      fontFamily: 'QuranHafs',
      fontSize: bannerTitleSize,
      height: 1.5,
      color: AppColors.gold,
      align: TextAlign.center,
      maxWidth: contentWidth,
    );
    final verse = _paragraph(
      '﴿${a.ayahText}﴾',
      fontFamily: 'QuranHafs',
      fontSize: verseSize,
      height: 2.0,
      color: Colors.white,
      align: TextAlign.center,
      maxWidth: contentWidth,
    );
    // Just the ayah number — the surah is already named in the banner
    // above, and printing it twice on one card reads as a mistake.
    final reference = _paragraph(
      'الآية ${_ar(a.ayahNumber)}',
      fontFamily: 'QuranHafs',
      fontSize: 38,
      height: 1.4,
      color: AppColors.gold,
      align: TextAlign.center,
      maxWidth: contentWidth,
    );
    final tafsirTitle = a.hasTafsir
        ? _paragraph(
            a.tafsirName ?? 'التفسير',
            fontFamily: '.SF Pro Text',
            fontSize: tafsirTitleSize,
            height: 1.4,
            color: AppColors.gold,
            align: TextAlign.center,
            maxWidth: contentWidth,
            bold: true,
          )
        : null;
    final tafsirBody = a.hasTafsir
        ? _paragraph(
            a.tafsirText!.trim(),
            fontFamily: '.SF Pro Text',
            fontSize: tafsirBodySize,
            height: 1.8,
            color: Colors.white.withValues(alpha: 0.94),
            align: TextAlign.right,
            maxWidth: contentWidth,
          )
        : null;
    final brand = _paragraph(
      _appName,
      fontFamily: 'QuranHafs',
      fontSize: 42,
      height: 1.3,
      color: Colors.white,
      align: TextAlign.left,
      maxWidth: contentWidth - 120,
    );

    // The surah banner: the SAME ornamental band the Mushaf pages are
    // headed with — cartouche, doubled keyline and end florets — rather
    // than a plainer plate that only half-matched it.
    final bannerHeight = surahTitle.height * 2.0;

    const gapAfterBanner = 52.0;
    const gapAfterVerse = 30.0;
    const gapBeforeRule = 48.0;
    const gapAfterRule = 42.0;
    const gapTafsirTitle = 22.0;
    const footerHeight = 104.0;

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

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(width, height);

    // Deep-emerald ground with a soft vertical lift, so the card reads
    // as the app's own surface rather than a flat rectangle.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, height),
          const [AppColors.primaryContainer, AppColors.primary],
        ),
    );

    // Hairline gold frame, inset like a Mushaf page border.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(24, 24, width - 48, height - 48),
          const Radius.circular(28)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.gold.withValues(alpha: 0.55),
    );

    var y = margin;

    // ── Surah banner
    //
    // The ornament is sized around the NAME's own ink, exactly as it is
    // on a page: maxIntrinsicWidth is the name's true drawn width, not
    // the full column the paragraph was laid out in.
    final nameWidth = surahTitle.maxIntrinsicWidth;
    final bandRect = Rect.fromLTWH(margin, y, contentWidth, bannerHeight);
    paintSurahBand(
      canvas,
      band: bandRect,
      ink: Rect.fromCenter(
        center: bandRect.center,
        width: nameWidth,
        height: bannerTitleSize,
      ),
      // The card's own deep-emerald ground stands in for the page
      // colour, so the band belongs to the card the way it belongs to
      // a leaf.
      palette: const SurahBandPalette(
        bandFill: Color(0xFF16342A),
        innerFill: AppColors.primary,
        rule: Color(0xFFB99239),
        gold: AppColors.gold,
      ),
    );
    canvas.drawParagraph(
        surahTitle, Offset(margin, y + (bannerHeight - surahTitle.height) / 2));
    y += bannerHeight + gapAfterBanner;

    canvas.drawParagraph(verse, Offset(margin, y));
    y += verse.height + gapAfterVerse;
    canvas.drawParagraph(reference, Offset(margin, y));
    y += reference.height;

    if (tafsirBody != null) {
      y += gapBeforeRule;
      canvas.drawRect(
        Rect.fromLTWH(margin + contentWidth * 0.25, y, contentWidth * 0.5, 1),
        Paint()..color = AppColors.gold.withValues(alpha: 0.45),
      );
      y += 1 + gapAfterRule;
      canvas.drawParagraph(tafsirTitle!, Offset(margin, y));
      y += tafsirTitle.height + gapTafsirTitle;
      canvas.drawParagraph(tafsirBody, Offset(margin, y));
      y += tafsirBody.height;
    }

    // Footer: the logo and the app's name, bottom-left.
    y += gapBeforeRule;
    final logo = await _loadLogo();
    final footerTop = y;
    if (logo != null) {
      const logoSize = 84.0;
      final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(margin, footerTop, logoSize, logoSize),
          const Radius.circular(18));
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(
            0, 0, logo.width.toDouble(), logo.height.toDouble()),
        rrect.outerRect,
        Paint(),
      );
      canvas.restore();
      canvas.drawParagraph(
          brand, Offset(margin + logoSize + 20, footerTop + 14));
    } else {
      canvas.drawParagraph(brand, Offset(margin, footerTop + 14));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.round(), height.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static ui.Image? _logoCache;

  static Future<ui.Image?> _loadLogo() async {
    if (_logoCache != null) return _logoCache;
    try {
      final data = await rootBundle.load('assets/icon/app_icon.png');
      final codec =
          await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _logoCache = frame.image;
      return _logoCache;
    } catch (e) {
      // A missing logo must not cost the reader the whole card.
      debugPrint('share card: logo unavailable ($e)');
      return null;
    }
  }

  static ui.Paragraph _paragraph(
    String text, {
    required String fontFamily,
    required double fontSize,
    required double height,
    required Color color,
    required TextAlign align,
    required double maxWidth,
    bool bold = false,
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
      ))
      ..addText(text);
    return builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
  }
}

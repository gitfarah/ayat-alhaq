import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/quran_page_meta.dart';
import '../theme.dart';

/// The fixed running head and foot of a Mushaf page — the printed
/// furniture a real Mushaf carries on every leaf.
///
/// A printed Mushaf never makes the reader hunt for where they are: the
/// juz and hizb sit in one top corner, the surah in the other, and the
/// page number sits under the text on the OUTER edge of the leaf, so a
/// thumbed-through book shows its numbers along the fore-edge. This file
/// reproduces all three, which is why the app's own page-number bar with
/// its arrows could go: the page carries the information itself now.

/// Arabic-Indic digits — the only numerals that belong on a Mushaf page.
String arabicDigits(int n) {
  const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return n.toString().split('').map((c) => d[int.parse(c)]).join();
}

/// Running head: surah name on the left, juz and hizb on the right,
/// fixed on every page.
class MushafPageHeader extends StatelessWidget {
  final int page;
  final bool isDark;

  /// Height the page layout has reserved. Kept as a fixed band so every
  /// page's text starts at exactly the same height — a head that grew
  /// with a long surah name would make the type jump between pages.
  final double height;

  const MushafPageHeader({
    super.key,
    required this.page,
    required this.isDark,
    this.height = 26,
  });

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final juz = QuranPageMeta.juzForPage(page);
    final hizb = QuranPageMeta.hizbForPage(page);
    final surahs = QuranPageMeta.surahsOnPage(page)
        .map(QuranPageMeta.surahName)
        .join(' • ');

    final style = TextStyle(
      fontFamily: 'Almarai',
      fontSize: math.min(13, height * 0.5),
      color: ink,
      height: 1.2,
    );

    return SizedBox(
      height: height,
      child: Directionality(
        // Laid out left-to-right on purpose: the two ends are pinned by
        // side, not by reading order, and an RTL row would swap them.
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            // Pinned to the two corners, not merely ordered: the surah
            // belongs on the outer edge of the head and the juz on the
            // other, with the gap between them however wide the page is.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // A page can open several short surahs; the names are
              // allowed to shrink rather than push the juz off the edge.
              Flexible(
                child: Text(surahs,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style),
              ),
              const SizedBox(width: 12),
              Text('الجزء ${arabicDigits(juz)}، الحزب ${arabicDigits(hizb)}',
                  textDirection: TextDirection.rtl, maxLines: 1, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// Running foot: the page number in an ornamental frame, pinned to the
/// OUTER edge of the leaf — left for even (verso) pages, right for odd
/// (recto) pages, exactly as a bound Mushaf prints them.
class MushafPageFooter extends StatelessWidget {
  final int page;
  final bool isDark;
  final double height;

  /// Interior colour of the cartouche — the reader's chosen page colour,
  /// so the frame belongs to the paper instead of sitting on top of it.
  final Color? pageColor;

  /// Tapping the number opens the go-to-page dialog: the arrows that
  /// used to do this are gone, so the number has to be the control.
  final VoidCallback? onTap;

  const MushafPageFooter({
    super.key,
    required this.page,
    required this.isDark,
    this.pageColor,
    this.onTap,
    this.height = 30,
  });

  @override
  Widget build(BuildContext context) {
    // Even pages fall on the left of an open Mushaf, odd pages on the
    // right; the number always hugs the outer edge.
    final onLeft = page.isEven;
    final badge = MushafPageBadge(
      page: page,
      isDark: isDark,
      pageColor: pageColor,
      pointLeft: onLeft,
      height: height,
    );

    return SizedBox(
      height: height,
      child: Align(
        alignment: onLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: onTap == null
              ? badge
              : GestureDetector(
                  behavior: HitTestBehavior.opaque, onTap: onTap, child: badge),
        ),
      ),
    );
  }
}

/// The framed page number itself: a lobed cartouche with a floral
/// half-palmette trailing off its outer side.
class MushafPageBadge extends StatelessWidget {
  final int page;
  final bool isDark;
  final Color? pageColor;

  /// Which way the palmette trails — outward, away from the spine.
  final bool pointLeft;
  final double height;

  const MushafPageBadge({
    super.key,
    required this.page,
    required this.isDark,
    required this.pointLeft,
    this.pageColor,
    this.height = 30,
  });

  @override
  Widget build(BuildContext context) {
    final label = arabicDigits(page);
    // The frame is sized to the digits so ٣ and ٦٠٤ both sit centred
    // with the same margins rather than one rattling around.
    final painter = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              fontFamily: 'Almarai',
              fontWeight: FontWeight.bold,
              fontSize: height * 0.42)),
      textDirection: TextDirection.rtl,
    )..layout();

    final boxW = math.max(height * 1.7, painter.width + height * 0.9);
    final tailW = height * 0.95;

    return SizedBox(
      width: boxW + tailW,
      height: height,
      child: CustomPaint(
        painter: _PageBadgePainter(
          isDark: isDark,
          pageColor: pageColor,
          pointLeft: pointLeft,
          boxWidth: boxW,
        ),
        child: Align(
          // Cartouche inboard, palmette outboard.
          alignment: pointLeft ? Alignment.centerRight : Alignment.centerLeft,
          child: SizedBox(
            width: boxW,
            child: Center(
              child: Text(label,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontFamily: 'Almarai',
                      fontWeight: FontWeight.bold,
                      fontSize: height * 0.42,
                      height: 1.0,
                      color: isDark
                          ? AppColors.darkSecondary
                          : const Color(0xFF2E5E44))),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the cartouche and its palmette.
///
/// Hand-drawn rather than a downloaded SVG: the ornament has to take the
/// reader's page colour and the dark-mode palette, and it has to match
/// the surah-name bands already painted on the page ([SurahBannerPainter]
/// uses the same green, gold rule and lobed outline). A fixed piece of
/// clip-art would match neither, and would have to carry its own licence.
class _PageBadgePainter extends CustomPainter {
  final bool isDark;
  final Color? pageColor;
  final bool pointLeft;
  final double boxWidth;

  const _PageBadgePainter({
    required this.isDark,
    required this.pointLeft,
    required this.boxWidth,
    this.pageColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final band = isDark ? const Color(0xFF16342A) : const Color(0xFFD8EADB);
    final inner = pageColor ??
        (isDark ? const Color(0xFF0E241C) : const Color(0xFFFCFBF7));
    final rule = isDark ? const Color(0xFF8FB89A) : const Color(0xFF5E8F6E);
    final gold = isDark ? const Color(0xFFD4AF37) : const Color(0xFFC9A227);

    final h = size.height;
    final stroke = math.max(0.8, h * 0.035);

    // Mirror the whole ornament for a recto page instead of writing the
    // geometry twice.
    canvas.save();
    if (!pointLeft) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    // The palmette occupies the outer strip, the cartouche the rest.
    final tailW = size.width - boxWidth;
    final left = tailW;
    final right = size.width;
    final top = h * 0.12;
    final bottom = h * 0.88;
    final midY = h / 2;

    // ── Cartouche: a rounded band with lobed ends ────────────────────
    final bh = bottom - top;
    final notch = math.min(bh * 0.55, (right - left) * 0.22);
    final shape = Path()
      ..moveTo(left, midY)
      ..quadraticBezierTo(left + notch * 0.45, top, left + notch, top)
      ..lineTo(right - notch, top)
      ..quadraticBezierTo(right - notch * 0.45, top, right, midY)
      ..quadraticBezierTo(right - notch * 0.45, bottom, right - notch, bottom)
      ..lineTo(left + notch, bottom)
      ..quadraticBezierTo(left + notch * 0.45, bottom, left, midY)
      ..close();

    canvas.drawPath(shape, Paint()..color = band);
    canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = rule);

    // A second, smaller cartouche inside the first, filled with the
    // paper's own colour and ruled in gold: the number then sits on the
    // page rather than on a green tablet, which is how the printed
    // frames read, and it keeps the digits legible at any page colour.
    canvas.save();
    canvas.translate((left + right) / 2, midY);
    canvas.scale(0.88, 0.74);
    canvas.translate(-(left + right) / 2, -midY);
    canvas.drawPath(shape, Paint()..color = inner);
    canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (stroke * 0.7) / 0.74
          ..color = gold.withValues(alpha: 0.75));
    canvas.restore();

    // ── Palmette tail-piece ──────────────────────────────────────────
    //
    // A short gold neck out of the cartouche opening into a fan of
    // petals. It has to sit CLOSE to the frame: strung out on a long
    // stem the ornament reads as a plant growing out of the page rather
    // than as the endpiece it is.
    final fanX = tailW * 0.62;
    canvas.drawPath(
        Path()
          ..moveTo(left, midY)
          ..quadraticBezierTo((left + fanX) / 2, midY - h * 0.05, fanX, midY),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.2
          ..strokeCap = StrokeCap.round
          ..color = gold);

    // Petals fan outwards from the neck: a long centre lobe flanked by
    // two shorter ones, the standard three-lobed palmette.
    final petalPaint = Paint()..color = isDark ? gold : rule;
    final petalEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.6
      ..color = gold;
    for (final (angle, reach) in [
      (-0.85, 0.62),
      (0.0, 1.0),
      (0.85, 0.62),
    ]) {
      canvas.save();
      canvas.translate(fanX, midY);
      canvas.rotate(angle);
      final len = fanX * reach;
      final wide = h * 0.17;
      canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(-len * 0.45, -wide, -len, 0)
            ..quadraticBezierTo(-len * 0.45, wide, 0, 0)
            ..close(),
          petalPaint);
      canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(-len * 0.45, -wide, -len, 0)
            ..quadraticBezierTo(-len * 0.45, wide, 0, 0)
            ..close(),
          petalEdge);
      canvas.restore();
    }

    // A gold bead where the neck meets the fan, so the petals read as
    // one piece rather than three loose leaves.
    canvas.drawCircle(
        Offset(fanX, midY), math.max(1.2, h * 0.055), Paint()..color = gold);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PageBadgePainter old) =>
      old.isDark != isDark ||
      old.pageColor != pageColor ||
      old.pointLeft != pointLeft ||
      old.boxWidth != boxWidth;
}

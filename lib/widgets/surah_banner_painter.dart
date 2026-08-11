import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/surah_header_service.dart';

/// The four colours an ornamental surah band is drawn from.
class SurahBandPalette {
  /// The band's ground.
  final Color bandFill;

  /// Inside the cartouche and the heart of each floret — normally the
  /// page colour, so the band belongs to the page instead of sitting
  /// on it.
  final Color innerFill;

  /// The outer keyline.
  final Color rule;

  /// Every ornament, and the finer rules set inside the keyline.
  final Color gold;

  const SurahBandPalette({
    required this.bandFill,
    required this.innerFill,
    required this.rule,
    required this.gold,
  });

  /// What a Mushaf page uses, light or dark.
  factory SurahBandPalette.page({required bool isDark, Color? pageColor}) =>
      SurahBandPalette(
        bandFill:
            isDark ? const Color(0xFF16342A) : const Color(0xFFD8EADB),
        innerFill: pageColor ??
            (isDark ? const Color(0xFF0E241C) : const Color(0xFFFCFBF7)),
        rule: isDark ? const Color(0xFFB99239) : const Color(0xFF8FB89A),
        gold: isDark ? const Color(0xFFD4AF37) : const Color(0xFFC9A227),
      );
}

/// Paints ONE ornamental surah band filling [band], with the inner
/// cartouche sized around the name ink that will sit at [ink].
///
/// Split out of [SurahBannerPainter] so the shareable ayah card can be
/// headed with the very same frame the Mushaf pages carry, instead of a
/// second, plainer plate that only half-matched it.
void paintSurahBand(
  Canvas canvas, {
  required Rect band,
  required Rect ink,
  required SurahBandPalette palette,
}) {
  final left = band.left;
  final right = band.right;
  final top = band.top;
  final bottom = band.bottom;
  final h = band.height;
  if (h <= 0) return;
  final midY = band.center.dy;
  final inkH = ink.height;

  final fillPaint = Paint()..color = palette.bandFill;
  final innerPaint = Paint()..color = palette.innerFill;
  final gold = palette.gold;
  final rulePaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = palette.rule
    ..strokeWidth = math.max(0.7, h * 0.035);
  final goldPaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = gold
    ..strokeWidth = math.max(0.6, h * 0.030);
  final goldSolid = Paint()..color = gold;

  // ── Outer band ────────────────────────────────────────────────
  //
  // Ruled twice, as the printed bands are: a green keyline on the
  // outside and a finer gold one set in from it. A single rule reads
  // as a UI chip; the pair reads as a printed frame.
  final outer =
      RRect.fromLTRBR(left, top, right, bottom, Radius.circular(h * 0.16));
  canvas.drawRRect(outer, fillPaint);
  canvas.drawRRect(outer, rulePaint);

  final keyInset = h * 0.10;
  canvas.drawRRect(
      RRect.fromLTRBR(left + keyInset, top + keyInset, right - keyInset,
          bottom - keyInset, Radius.circular(h * 0.11)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, h * 0.018)
        ..color = gold.withValues(alpha: 0.65));

  // ── Inner cartouche (hexagonal, pointed ends) ─────────────────
  //
  // Sized to the NAME, not to a fixed share of the band. Surah names
  // differ hugely in length (ٱلْأَعْرَاف against ٱلنَّاس) and each
  // riwayah sets them at its own size, so a fixed width either
  // crowded the long ones or left the short ones adrift. The
  // measured ink is centred inside the cartouche by construction.
  final cx = ink.center.dx;
  final maxW = (right - left) * 0.78;
  final cw = math.min(maxW, math.max(ink.width + inkH * 2.6, inkH * 5));
  final cLeft = cx - cw / 2;
  final cRight = cx + cw / 2;
  final inset = h * 0.13;
  final cTop = top + inset;
  final cBottom = bottom - inset;
  final notch = math.min(h * 0.55, cw * 0.10);

  // Softly curved ends (rather than sharp corners) read closer to
  // the lobed cartouches printed in a Mushaf.
  final cartouche = Path()
    ..moveTo(cLeft, midY)
    ..quadraticBezierTo(cLeft + notch * 0.5, cTop, cLeft + notch, cTop)
    ..lineTo(cRight - notch, cTop)
    ..quadraticBezierTo(cRight - notch * 0.5, cTop, cRight, midY)
    ..quadraticBezierTo(cRight - notch * 0.5, cBottom, cRight - notch, cBottom)
    ..lineTo(cLeft + notch, cBottom)
    ..quadraticBezierTo(cLeft + notch * 0.5, cBottom, cLeft, midY)
    ..close();
  canvas.drawPath(cartouche, innerPaint);
  canvas.drawPath(cartouche, goldPaint);

  // A hairline echoing the cartouche just inside it — the same
  // doubling as the outer band, at the scale of the name.
  canvas.save();
  canvas.translate(cx, midY);
  canvas.scale(0.965, 0.80);
  canvas.translate(-cx, -midY);
  canvas.drawPath(
      cartouche,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.4, h * 0.014) / 0.80
        ..color = gold.withValues(alpha: 0.5));
  canvas.restore();

  // ── End ornaments ─────────────────────────────────────────────
  //
  // A floret rather than a lone diamond: a four-petal rosette with a
  // gold bead at its heart and a small lozenge either side of it,
  // which is the filler the printed bands run between the cartouche
  // and the frame.
  final d = h * 0.21;
  for (final (ox, inner) in [
    ((left + cLeft) / 2, cLeft),
    ((right + cRight) / 2, cRight),
  ]) {
    // A hairline along the band's centre, from the frame to the
    // cartouche, with the floret threaded onto it. Without it the
    // end panels read as empty space with a mark dropped in.
    final edge = ox < cx ? left + keyInset : right - keyInset;
    canvas.drawLine(
        Offset(edge + (ox < cx ? h * 0.16 : -h * 0.16), midY),
        Offset(inner + (ox < cx ? -h * 0.10 : h * 0.10), midY),
        Paint()
          ..strokeWidth = math.max(0.4, h * 0.014)
          ..color = gold.withValues(alpha: 0.45));

    // Petals: four teardrops on the diagonals.
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(ox, midY);
      canvas.rotate(math.pi / 4 + i * math.pi / 2);
      canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(d * 0.50, -d * 0.44, d * 1.10, 0)
            ..quadraticBezierTo(d * 0.50, d * 0.44, 0, 0)
            ..close(),
          goldSolid);
      canvas.restore();
    }
    // Heart of the floret, left as the page colour so the petals
    // read as separate leaves rather than a blob.
    canvas.drawCircle(Offset(ox, midY), d * 0.30, innerPaint);
    canvas.drawCircle(
        Offset(ox, midY),
        d * 0.30,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.4, h * 0.016)
          ..color = gold);

    // Lozenge either side, sitting on the band's centre line.
    for (final dx in [-d * 2.1, d * 2.1]) {
      final lz = d * 0.42;
      canvas.drawPath(
          Path()
            ..moveTo(ox + dx, midY - lz)
            ..lineTo(ox + dx + lz * 0.60, midY)
            ..lineTo(ox + dx, midY + lz)
            ..lineTo(ox + dx - lz * 0.60, midY)
            ..close(),
          goldSolid);
    }
  }
}

/// Paints the traditional ornamental frame around each surah name on a
/// Mushaf page.
///
/// It is drawn UNDERNEATH the page SVG, so the surah-name glyphs that
/// the artwork already contains end up sitting inside the frame — the
/// same way a printed Mushaf prints the name inside a decorated band.
class SurahBannerPainter extends CustomPainter {
  final List<SurahHeaderBand> bands;

  /// viewBox → rendered-pixel scale (same factors the ayah overlay uses).
  final double scaleX;
  final double scaleY;
  final bool isDark;

  /// viewBox origin — not every edition's pages start at 0 0.
  final double minX;
  final double minY;

  /// Interior colour of the cartouche — the reader's page colour, so
  /// the band belongs to the page instead of sitting on it.
  final Color? pageColor;

  const SurahBannerPainter({
    required this.bands,
    required this.scaleX,
    required this.scaleY,
    required this.isDark,
    this.minX = 0,
    this.minY = 0,
    this.pageColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    // Palette: soft green band with a gold rule, echoing a printed
    // Mushaf. Dark mode uses deep emerald so the inverted white glyphs
    // stay legible on top.
    final palette =
        SurahBandPalette.page(isDark: isDark, pageColor: pageColor);

    // Side margin matches the text column of the page artwork.
    final left = 6.0 * scaleX;
    final right = size.width - 6.0 * scaleX;

    for (final b in bands) {
      final inkTop = (b.top - minY) * scaleY;
      final inkBottom = (b.bottom - minY) * scaleY;
      final inkH = inkBottom - inkTop;
      if (inkH <= 0) continue;

      // Breathing room so the band reads as a frame, not a highlight.
      final padY = inkH * 0.30;
      paintSurahBand(
        canvas,
        band: Rect.fromLTRB(left, inkTop - padY, right, inkBottom + padY),
        ink: Rect.fromLTRB(
            (b.left - minX) * scaleX, inkTop, (b.right - minX) * scaleX,
            inkBottom),
        palette: palette,
      );
    }
  }

  @override
  bool shouldRepaint(SurahBannerPainter old) =>
      old.scaleX != scaleX ||
      old.scaleY != scaleY ||
      old.isDark != isDark ||
      old.minX != minX ||
      old.minY != minY ||
      old.pageColor != pageColor ||
      old.bands.length != bands.length ||
      (bands.isNotEmpty &&
          old.bands.isNotEmpty &&
          old.bands.first.top != bands.first.top);
}

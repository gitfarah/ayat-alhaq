import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/surah_header_service.dart';

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

  /// How far the band at a given viewBox y has been pushed down, in
  /// rendered pixels. Non-zero when the page's lines are spread to fill
  /// the screen: the frame has to travel with the name it encloses, or
  /// it is left painted over the line above.
  final double Function(double viewBoxY)? shiftY;

  const SurahBannerPainter({
    required this.bands,
    required this.scaleX,
    required this.scaleY,
    required this.isDark,
    this.minX = 0,
    this.minY = 0,
    this.pageColor,
    this.shiftY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    // Palette: soft green band with a gold rule, echoing a printed
    // Mushaf. Dark mode uses deep emerald so the inverted white glyphs
    // stay legible on top.
    final bandFill = isDark ? const Color(0xFF16342A) : const Color(0xFFD8EADB);
    final innerFill = pageColor ??
        (isDark ? const Color(0xFF0E241C) : const Color(0xFFFCFBF7));
    final rule = isDark ? const Color(0xFFB99239) : const Color(0xFF8FB89A);
    final gold = isDark ? const Color(0xFFD4AF37) : const Color(0xFFC9A227);

    final fillPaint = Paint()..color = bandFill;
    final innerPaint = Paint()..color = innerFill;
    final rulePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = rule;
    final goldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = gold;
    final goldSolid = Paint()..color = gold;

    // Side margin matches the text column of the page artwork.
    final left = 6.0 * scaleX;
    final right = size.width - 6.0 * scaleX;

    for (final b in bands) {
      // Measured from the band's MIDDLE so the whole frame moves as one
      // piece even when its top and bottom edges fall either side of a
      // line boundary.
      final shift = shiftY?.call((b.top + b.bottom) / 2) ?? 0;
      final inkTop = (b.top - minY) * scaleY + shift;
      final inkBottom = (b.bottom - minY) * scaleY + shift;
      final inkH = inkBottom - inkTop;
      if (inkH <= 0) continue;

      // Breathing room so the band reads as a frame, not a highlight.
      final padY = inkH * 0.30;
      final top = inkTop - padY;
      final bottom = inkBottom + padY;
      final h = bottom - top;
      final midY = (top + bottom) / 2;

      rulePaint.strokeWidth = math.max(0.7, h * 0.035);
      goldPaint.strokeWidth = math.max(0.6, h * 0.030);

      // ── Outer band ────────────────────────────────────────────────
      final outer =
          RRect.fromLTRBR(left, top, right, bottom, Radius.circular(h * 0.16));
      canvas.drawRRect(outer, fillPaint);
      canvas.drawRRect(outer, rulePaint);

      // ── Inner cartouche (hexagonal, pointed ends) ─────────────────
      //
      // Sized to the NAME, not to a fixed share of the band. Surah names
      // differ hugely in length (ٱلْأَعْرَاف against ٱلنَّاس) and each
      // riwayah sets them at its own size, so a fixed width either
      // crowded the long ones or left the short ones adrift. The
      // measured ink is centred inside the cartouche by construction.
      final inkLeft = (b.left - minX) * scaleX;
      final inkRight = (b.right - minX) * scaleX;
      final cx = (inkLeft + inkRight) / 2;
      final maxW = (right - left) * 0.78;
      final cw =
          math.min(maxW, math.max((inkRight - inkLeft) + inkH * 2.6, inkH * 5));
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
        ..quadraticBezierTo(
            cRight - notch * 0.5, cBottom, cRight - notch, cBottom)
        ..lineTo(cLeft + notch, cBottom)
        ..quadraticBezierTo(cLeft + notch * 0.5, cBottom, cLeft, midY)
        ..close();
      canvas.drawPath(cartouche, innerPaint);
      canvas.drawPath(cartouche, goldPaint);

      // ── End ornaments: a small diamond between the band edge and
      // the cartouche on each side.
      final d = h * 0.16;
      for (final ox in [
        (left + cLeft) / 2,
        (right + cRight) / 2,
      ]) {
        final diamond = Path()
          ..moveTo(ox, midY - d)
          ..lineTo(ox + d, midY)
          ..lineTo(ox, midY + d)
          ..lineTo(ox - d, midY)
          ..close();
        canvas.drawPath(diamond, goldSolid);
      }
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
      old.shiftY != shiftY ||
      old.bands.length != bands.length ||
      (bands.isNotEmpty &&
          old.bands.isNotEmpty &&
          old.bands.first.top != bands.first.top);
}

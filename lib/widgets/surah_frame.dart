import 'package:flutter/material.dart';
import '../theme.dart';

/// Ornamental surah-name header modeled on the decorated cartouches of
/// the printed Mushaf: a gold double-ruled band with scalloped rosette
/// medallions on both ends and the surah name centered inside.
class SurahFrame extends StatelessWidget {
  final String title;
  final bool isDark;
  final double fontSize;

  /// Rendered content to frame instead of [title]. The V1 Mushaf sets
  /// the surah name from its own font, so the band has to go around a
  /// widget rather than around a string.
  final Widget? child;

  /// Interior colour of the cartouche. Defaults to parchment; the
  /// Mushaf passes the reader's chosen page colour so the frame is part
  /// of the page rather than a cream patch sitting on it.
  final Color? pageColor;

  const SurahFrame({
    super.key,
    required this.title,
    required this.isDark,
    this.fontSize = 20,
    this.child,
    this.pageColor,
  });

  @override
  Widget build(BuildContext context) {
    final gold = isDark ? AppColors.darkSecondary : AppColors.mushafBorderGold;
    final fill =
        pageColor ?? (isDark ? AppColors.darkSurface : AppColors.mushafParchment);
    final text = isDark ? AppColors.darkText : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: CustomPaint(
        painter: _FramePainter(gold: gold, fill: fill),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
              horizontal: child == null ? 56 : fontSize * 1.6,
              vertical: child == null ? 14 : fontSize * 0.22),
          child: child != null
              ? Center(child: child)
              : Text(
                  title,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'QuranHafs',
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: text,
                    height: 1.4,
                  ),
                ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  final Color gold;
  final Color fill;

  _FramePainter({required this.gold, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = gold;
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = gold.withValues(alpha: 0.8);
    final solid = Paint()..color = gold;
    final bg = Paint()..color = fill;

    // Band body: outer + inner rules around a filled parchment strip.
    final outer = RRect.fromRectAndRadius(
        Rect.fromLTWH(h * 0.32, 1.5, w - h * 0.64, h - 3),
        Radius.circular(h * 0.24));
    final inner = RRect.fromRectAndRadius(
        Rect.fromLTWH(h * 0.32 + 4, 5.5, w - h * 0.64 - 8, h - 11),
        Radius.circular(h * 0.16));
    canvas.drawRRect(outer, bg);
    canvas.drawRRect(outer, stroke);
    canvas.drawRRect(inner, thin);

    // Scalloped rosette medallions on both ends (the round ornament
    // that marks surah headers and ayah counts in printed Mushafs).
    for (final cx in [h * 0.38, w - h * 0.38]) {
      final c = Offset(cx, h / 2);
      final r = h * 0.34;
      canvas.drawCircle(c, r, bg);
      // Scallop: 12 petals as small arcs around the rim.
      final petals = Path();
      const n = 12;
      for (var i = 0; i < n; i++) {
        final a1 = (i / n) * 2 * 3.1415926;
        final a2 = ((i + 1) / n) * 2 * 3.1415926;
        final mid = (a1 + a2) / 2;
        final p1 = c + Offset.fromDirection(a1, r);
        final pm = c + Offset.fromDirection(mid, r * 1.22);
        final p2 = c + Offset.fromDirection(a2, r);
        if (i == 0) petals.moveTo(p1.dx, p1.dy);
        petals.quadraticBezierTo(pm.dx, pm.dy, p2.dx, p2.dy);
      }
      petals.close();
      canvas.drawPath(petals, stroke);
      canvas.drawCircle(c, r * 0.68, thin);
      // Center diamond dot.
      final d = r * 0.30;
      final diamond = Path()
        ..moveTo(c.dx, c.dy - d)
        ..lineTo(c.dx + d, c.dy)
        ..lineTo(c.dx, c.dy + d)
        ..lineTo(c.dx - d, c.dy)
        ..close();
      canvas.drawPath(diamond, solid);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.gold != gold || old.fill != fill;
}

// The five skies painted behind the prayers in the home strip, and the
// sparkle field on the continue-reading card.
//
// HAND-PAINTED, deliberately, rather than pulled from one of the
// animated-background packages on pub.dev. Those paint one generic
// particle field over a whole page; what is wanted here is the
// opposite — five DIFFERENT skies, each matching the hour its prayer is
// called at, inside a cell about 63x82 logical pixels. (The most-cited
// of them, animated_background, was also last published five years ago,
// so it would have been a dead dependency for a wrong-shaped effect.)
//
// Everything is driven by ONE repeating controller owned by the screen
// and handed to each painter as `repaint:`. A twinkling star therefore
// never rebuilds a widget — the painter repaints its own layer and
// nothing above it is touched. Passing a stopped animation (kSkyStill)
// freezes every scene on a still frame, which is what the reduce-motion
// setting does.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One full turn of the home screen's ornaments.
///
/// Long on purpose: this sits under a screen people READ from, so the
/// motion has to be slow enough to never pull the eye off the surah
/// list. Twelve seconds reads as "alive", two seconds reads as "busy".
const Duration kSkyCycle = Duration(seconds: 12);

/// The frame every scene freezes on when motion is off. Not 0: at 0 the
/// twinkle sits at its dimmest and the skies look flat and unfinished.
const Animation<double> kSkyStill = AlwaysStoppedAnimation<double>(0.35);

/// Prayer order everywhere in the app: Fajr, Dhuhr, Asr, Maghrib, Isha.
///
/// Top-of-sky and horizon colour for each. Picked to read as the hour
/// itself — pre-dawn indigo, high blue noon, gold afternoon, burnt
/// sunset, deep night — so the strip can be read as a day passing even
/// before the names are.
/// The horizon colour of every one of them is LIGHT, including the two
/// night skies. That is not just how a horizon looks — it is what keeps
/// the cell readable. The prayer name and time sit in the lower half,
/// and the next prayer sets them in the app's dark green accent, which
/// disappears against a navy that stays dark all the way down. Rendered
/// with Isha as the next prayer to check exactly that.
const List<List<Color>> _skies = [
  [Color(0xFF243266), Color(0xFFF6C3A6)], // Fajr — night giving way
  [Color(0xFF3B93DA), Color(0xFFCFEBFA)], // Dhuhr — high sun
  [Color(0xFFE0952C), Color(0xFFF9E3B8)], // Asr — gold, sun dropping
  [Color(0xFFD2512A), Color(0xFFE9A98C)], // Maghrib — sun at the rim
  [Color(0xFF16244F), Color(0xFF8E9AC4)], // Isha — night over a lit horizon
];

/// How opaque a sky is drawn, given whether it is the NEXT prayer and
/// whether the app is dark.
///
/// Light mode needs more: the same alpha that reads as a night sky over
/// the dark card washes out to pastel over a white one. Rendered both
/// ways before these numbers were picked.
double skyStrength({required bool isNext, required bool isDark}) =>
    isDark ? (isNext ? 0.62 : 0.42) : (isNext ? 0.72 : 0.50);

/// Where the prayer's ICON sits in its cell, as a fraction. The scene is
/// built around it: each sky glows from this point, so the icon reads as
/// the sun (or moon) that lit it rather than as a sticker on top.
const Alignment _iconAt = Alignment(0.0, -0.56);

/// The colour the strip's icon is drawn in ON TOP of [index]'s sky, or
/// null to keep the PrayerVisuals colour.
///
/// Only Isha needs this, and it needs OPPOSITE corrections in the two
/// modes — which is the whole reason it takes [isDark] rather than
/// being a constant. Composited at the icon's own position, the night
/// sky lands around RGB(170,176,199) over the white card but near
/// RGB(56,65,82) over the dark one. A pale moon reads on the second and
/// vanishes into the first, so light mode goes DARKER instead.
///
/// The other four skies are pale enough at that height that the
/// original warm icons keep their contrast.
Color? skyIconColor(int index, {required bool isDark}) => switch (index) {
      4 => isDark
          ? const Color(0xFFF3F1E4) // moonlight on a night sky
          : const Color(0xFF2F4470), // deep night-blue on a lit one
      _ => null,
    };

/// A star, placed in FRACTIONS of the cell so one set of positions
/// works at any size, with its own phase so a field never blinks in
/// unison.
class _Star {
  final double x, y, size, phase;
  const _Star(this.x, this.y, this.size, this.phase);
}

/// Star positions are drawn once from a SEEDED generator, not per
/// frame: a fresh Random() each paint would make the stars jump around
/// the sky sixty times a second.
List<_Star> _seededStars(int seed, int count, {double top = 0.62}) {
  final rnd = math.Random(seed);
  return [
    for (var i = 0; i < count; i++)
      _Star(0.08 + rnd.nextDouble() * 0.84, 0.08 + rnd.nextDouble() * top,
          0.7 + rnd.nextDouble() * 0.8, rnd.nextDouble()),
  ];
}

final List<_Star> _fajrStars = _seededStars(4, 5, top: 0.34);
final List<_Star> _ishaStars = _seededStars(11, 9, top: 0.52);

/// Eased 0..1..0 pulse for [t] turns, offset by [phase].
double _pulse(double t, double phase) =>
    0.5 + 0.5 * math.sin((t + phase) * 2 * math.pi);

/// Paints the sky for ONE prayer, behind its name and time.
///
/// [strength] is the whole scene's opacity. It stays low because this
/// is a BACKGROUND: the prayer name and time are the point of the cell,
/// and they keep their own colours over it. The next prayer's cell is
/// given a stronger sky (see the call site) so the one that matters is
/// also the liveliest.
class PrayerSkyPainter extends CustomPainter {
  final int index;
  final double strength;
  final Animation<double> animation;

  PrayerSkyPainter({
    required this.index,
    required this.strength,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || strength <= 0) return;
    final rect = Offset.zero & size;
    final t = animation.value;
    final sky = _skies[index];

    // The wash. Full strength at the top where the scene is, fading
    // down the cell so the name and time below sit on almost-clean
    // card and stay as readable as they were without a sky at all.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            sky[0].withValues(alpha: strength),
            sky[1].withValues(alpha: strength * 0.55),
            sky[1].withValues(alpha: 0),
          ],
          // Down to the light horizon colour by 42% — where the prayer
          // NAME starts — and gone entirely by 86%, so the time at the
          // bottom sits on clean card and reads exactly as well as it
          // did before there was a sky behind it.
          stops: const [0, 0.42, 0.86],
        ).createShader(rect),
    );

    switch (index) {
      case 0:
        _fajr(canvas, size, t);
      case 1:
        _dhuhr(canvas, size, t);
      case 2:
        _asr(canvas, size, t);
      case 3:
        _maghrib(canvas, size, t);
      default:
        _isha(canvas, size, t);
    }
  }

  /// The light the icon sits in. Every scene has one — it is what makes
  /// the strip's existing sun/moon icon look like it belongs to the sky
  /// behind it instead of floating on it.
  ///
  /// No sun or crescent is painted anywhere in this file for the same
  /// reason: the cell already HAS one, and drawing a second put two
  /// suns in sixty-three pixels.
  void _glow(Canvas canvas, Size size, Color color, double radius,
      {double alpha = 1.0}) {
    final c = Offset(size.width * (0.5 + _iconAt.x / 2),
        size.height * (0.5 + _iconAt.y / 2));
    final r = size.shortestSide * radius;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: strength * alpha),
          color.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  /// Dawn: the last stars going out, over a horizon that is coming up.
  void _fajr(Canvas canvas, Size size, double t) {
    _paintStars(canvas, size, _fajrStars, t, const Color(0xFFFFF3E0), 0.55);
    // First light on the horizon, breathing very slowly.
    final rise = 0.34 + 0.18 * _pulse(t, 0.0);
    final band = Rect.fromLTRB(0, size.height * 0.34, size.width, size.height);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFFFFC98F).withValues(alpha: strength * rise),
            const Color(0xFFFFC98F).withValues(alpha: 0),
          ],
        ).createShader(band),
    );
    _glow(canvas, size, const Color(0xFFFFE3B5), 0.46, alpha: 0.5);
  }

  /// Noon: the sun at its highest, its halo breathing.
  void _dhuhr(Canvas canvas, Size size, double t) {
    _glow(
        canvas, size, const Color(0xFFFFFAD6), 0.62 * (1 + 0.14 * _pulse(t, 0)),
        alpha: 0.95);
  }

  /// Afternoon: gold light, with thin cloud drifting across it.
  void _asr(Canvas canvas, Size size, double t) {
    _glow(canvas, size, const Color(0xFFFFE6A8), 0.58, alpha: 0.85);
    // Two streaks crossing the cell, wrapping round as they leave it.
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: strength * 0.55)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 2; i++) {
      final drift = ((t + i * 0.5) % 1.0) * (size.width + 30) - 15;
      final y = size.height * (0.30 + i * 0.20);
      paint.strokeWidth = 1.7 - i * 0.5;
      canvas.drawLine(
          Offset(drift, y), Offset(drift + size.width * 0.32, y), paint);
    }
  }

  /// Sunset: the light going down, banded across the horizon.
  void _maghrib(Canvas canvas, Size size, double t) {
    _glow(canvas, size, const Color(0xFFFFC98A),
        0.60 * (1 + 0.12 * _pulse(t, 0.25)),
        alpha: 0.9);
    // The burning line the sun leaves along the horizon as it goes.
    final y = size.height * 0.60;
    final band = Rect.fromLTRB(0, y - 5, size.width, y + 5);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(colors: [
          const Color(0xFFFF9C55).withValues(alpha: 0),
          const Color(0xFFFF9C55).withValues(alpha: strength * 0.75),
          const Color(0xFFFF9C55).withValues(alpha: 0),
        ]).createShader(band),
    );
  }

  /// Night: a field of stars, and moonlight where the crescent sits.
  void _isha(Canvas canvas, Size size, double t) {
    _paintStars(canvas, size, _ishaStars, t, Colors.white, 1.0);
    _glow(canvas, size, const Color(0xFFDCE6FF), 0.44, alpha: 0.45);
  }

  void _paintStars(Canvas canvas, Size size, List<_Star> stars, double t,
      Color color, double intensity) {
    final paint = Paint();
    for (final s in stars) {
      // Each star twinkles on its own phase, and Fajr's are dimmer
      // because dawn is already washing them out.
      final tw = (0.35 + 0.65 * _pulse(t * 2, s.phase)) * intensity;
      paint.color = color.withValues(alpha: strength * tw * 1.6);
      canvas.drawCircle(
          Offset(s.x * size.width, s.y * size.height), s.size, paint);
    }
  }

  @override
  bool shouldRepaint(PrayerSkyPainter old) =>
      old.index != index ||
      old.strength != strength ||
      old.animation != animation;
}

/// The sparkle field over the continue-reading card.
///
/// Draws ONLY the sparkles — the card keeps its own green gradient, and
/// this layer sits on top of it, so the card's colour is untouched.
class SparklePainter extends CustomPainter {
  final Animation<double> animation;

  /// Sparkles are kept off this fraction of the reading edge, so none
  /// of them ever sits on top of the surah name.
  final double textInset;

  SparklePainter({required this.animation, this.textInset = 0.0})
      : super(repaint: animation);

  static final List<_Star> _field = _seededStars(7, 14, top: 0.86);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = animation.value;
    final paint = Paint();
    for (final s in _field) {
      final x = textInset + s.x * (size.width - textInset);
      // Sparkles come and go rather than sitting there pulsing: below a
      // quarter of the cycle a sparkle is simply absent, so the card
      // never looks like a fixed pattern of dots.
      final life = _pulse(t, s.phase);
      if (life < 0.26) continue;
      final f = (life - 0.26) / 0.74;
      final at = Offset(x, s.y * size.height);
      final r = s.size * 5.2 * (0.45 + 0.55 * f);
      // A glint is its halo as much as its shape — without the soft
      // wash behind it a sparkle reads as a hard little cross.
      canvas.drawCircle(
        at,
        r * 1.5,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: 0.30 * f),
            Colors.white.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: at, radius: r * 1.5)),
      );
      paint.color = Colors.white.withValues(alpha: 0.95 * f);
      canvas.drawPath(_sparkle(at, r), paint);
    }
  }

  /// The four-pointed "shine", waisted so it reads as a glint and not
  /// as a plus sign.
  Path _sparkle(Offset c, double r) {
    final w = r * 0.22;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(SparklePainter old) =>
      old.animation != animation || old.textInset != textInset;
}

// The sky behind the prayer-times card, and the glints on the
// continue-reading card.
//
// The prayer card is painted as the hour it is RIGHT NOW: one sky for
// the whole card, changing when the prayer time changes. (It was five
// separate skies, one behind each prayer, which put the colour on the
// wrong thing — the card is what tells you the time of day, not five
// competing thumbnails inside it.)
//
// HAND-PAINTED rather than pulled from one of the animated-background
// packages on pub.dev. Those paint a generic particle field over a
// whole page; this needs specific skies with text that stays readable
// on them. The most-cited of them, animated_background, was also last
// published five years ago.
//
// Everything is driven by ONE repeating controller handed to the
// painter as `repaint:`, so a twinkling star never rebuilds a widget.
// A stopped animation (kSkyStill) freezes the scene, which is what
// reduce-motion does.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One full turn of the ornaments.
///
/// Long on purpose: this sits under a screen people READ from, so the
/// motion has to be slow enough never to pull the eye off the surah
/// list. Twelve seconds reads as "alive", two seconds reads as "busy".
const Duration kSkyCycle = Duration(seconds: 12);

/// How long the card takes to become the next prayer's sky. Slow enough
/// to be seen as a change of light rather than a repaint.
const Duration kSkyChange = Duration(milliseconds: 1400);

/// The frame the scene freezes on when motion is off. Not 0: at 0 every
/// twinkle sits at its dimmest and the sky looks flat and unfinished.
const Animation<double> kSkyStill = AlwaysStoppedAnimation<double>(0.35);

/// Everything one prayer's sky is drawn from — including the ink, which
/// is the part that cannot be an afterthought.
///
/// Each sky commits to being either a LIGHT card or a DARK one, and
/// carries the text colour that reads on it. That is why Maghrib and
/// Isha are set in near-white while the other three are set in near-
/// black: a card that fades from dark at the top to light at the bottom
/// has no single ink that works, and the prayer names sit right across
/// the middle of it.
class PrayerSkyTheme {
  /// The sky itself, top to bottom.
  final Color top, bottom;

  /// Headline, prayer times, and the highlighted prayer.
  final Color ink;

  /// Prayer names and the quieter type.
  final Color inkSoft;

  /// Stars, 0 for a daylit sky.
  final double stars;

  /// Thin cloud drifting across, 0 for a clear one.
  final double cloud;

  /// A warm band low in the sky — dawn coming up, or the sun going
  /// down. 0 for the hours in between.
  final double horizon;

  const PrayerSkyTheme({
    required this.top,
    required this.bottom,
    required this.ink,
    required this.inkSoft,
    this.stars = 0,
    this.cloud = 0,
    this.horizon = 0,
  });

  static PrayerSkyTheme lerp(PrayerSkyTheme a, PrayerSkyTheme b, double t) =>
      PrayerSkyTheme(
        top: Color.lerp(a.top, b.top, t)!,
        bottom: Color.lerp(a.bottom, b.bottom, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
        inkSoft: Color.lerp(a.inkSoft, b.inkSoft, t)!,
        stars: a.stars + (b.stars - a.stars) * t,
        cloud: a.cloud + (b.cloud - a.cloud) * t,
        horizon: a.horizon + (b.horizon - a.horizon) * t,
      );

  /// The fill and keyline the NEXT prayer's cell is picked out with.
  /// Derived from the ink so it works on any of the five skies —
  /// the app's green accent disappears into a night sky.
  Color get highlight => ink.withValues(alpha: 0.13);
  Color get highlightLine => ink.withValues(alpha: 0.34);
}

const Color _dayInk = Color(0xFF23303A);
const Color _daySoft = Color(0xFF4B5A66);
const Color _nightInk = Color(0xFFF4F1E8);
const Color _nightSoft = Color(0xFFC9CEE0);

/// Prayer order everywhere in the app: Fajr, Dhuhr, Asr, Maghrib, Isha.
const List<PrayerSkyTheme> _lightSkies = [
  // Fajr — night thinning out into first light. Kept light enough to
  // take dark ink; the stars and the glow at the bottom carry the hour.
  PrayerSkyTheme(
      top: Color(0xFFB9BCE0),
      bottom: Color(0xFFFAD9BE),
      ink: _dayInk,
      inkSoft: _daySoft,
      stars: 0.45,
      horizon: 0.7),
  // Dhuhr — high, clean, bright.
  PrayerSkyTheme(
      top: Color(0xFF8CC7EF),
      bottom: Color(0xFFE2F2FB),
      ink: _dayInk,
      inkSoft: _daySoft),
  // Asr — the gold hours, with cloud drifting.
  PrayerSkyTheme(
      top: Color(0xFFF0C275),
      bottom: Color(0xFFFCEBCE),
      ink: _dayInk,
      inkSoft: _daySoft,
      cloud: 0.9),
  // Maghrib — the sun going down. A LATE sunset rather than a bright
  // one: the first try faded to a vivid orange that measured 2.4:1
  // against this ink. Deep plum into burnt orange keeps the hour and
  // clears the bar.
  PrayerSkyTheme(
      top: Color(0xFF5E2A4A),
      bottom: Color(0xFFA64A1C),
      ink: _nightInk,
      inkSoft: Color(0xFFF6DCCB),
      horizon: 1.0),
  // Isha — night, and the stars the whole thing was asked for.
  PrayerSkyTheme(
      top: Color(0xFF0C1533),
      bottom: Color(0xFF2A3A6B),
      ink: _nightInk,
      inkSoft: _nightSoft,
      stars: 1.0),
];

/// In dark mode every hour is set darker — a bright noon card would be
/// a lamp in the middle of a dark screen — but each keeps its hue, so
/// the five are still told apart at a glance.
const List<PrayerSkyTheme> _darkSkies = [
  PrayerSkyTheme(
      top: Color(0xFF232A50),
      bottom: Color(0xFF6B4B4A),
      ink: _nightInk,
      inkSoft: _nightSoft,
      stars: 0.6,
      horizon: 0.7),
  PrayerSkyTheme(
      top: Color(0xFF1B3E5C),
      bottom: Color(0xFF2E6382),
      ink: _nightInk,
      inkSoft: Color(0xFFCFE3EF)),
  PrayerSkyTheme(
      top: Color(0xFF5A431E),
      bottom: Color(0xFF7A5C26),
      ink: _nightInk,
      inkSoft: Color(0xFFEEDCBA),
      cloud: 0.7),
  PrayerSkyTheme(
      top: Color(0xFF4A2338),
      bottom: Color(0xFF8B4526),
      ink: _nightInk,
      inkSoft: Color(0xFFF0D2C2),
      horizon: 1.0),
  PrayerSkyTheme(
      top: Color(0xFF070C20),
      bottom: Color(0xFF1B2748),
      ink: _nightInk,
      inkSoft: _nightSoft,
      stars: 1.0),
];

/// The sky for [index], for the current mode.
PrayerSkyTheme prayerSkyTheme(int index, {required bool isDark}) =>
    (isDark ? _darkSkies : _lightSkies)[index.clamp(0, 4)];

/// A star, placed in FRACTIONS of the card so one set of positions works
/// at any width, with its own phase so a field never blinks in unison.
class _Star {
  final double x, y, size, phase;
  const _Star(this.x, this.y, this.size, this.phase);
}

/// Star positions are drawn once from a SEEDED generator, not per frame:
/// a fresh Random() each paint would make the stars jump around the sky
/// sixty times a second.
List<_Star> _seededStars(int seed, int count, {double top = 0.62}) {
  final rnd = math.Random(seed);
  return [
    for (var i = 0; i < count; i++)
      _Star(0.04 + rnd.nextDouble() * 0.92, 0.06 + rnd.nextDouble() * top,
          0.7 + rnd.nextDouble() * 0.9, rnd.nextDouble()),
  ];
}

final List<_Star> _cardStars = _seededStars(11, 26, top: 0.66);

/// Eased 0..1..0 pulse for [t] turns, offset by [phase].
double _pulse(double t, double phase) =>
    0.5 + 0.5 * math.sin((t + phase) * 2 * math.pi);

/// Paints the whole prayer card as one sky.
///
/// [theme] is already blended by the caller when one prayer is giving
/// way to the next, so the painter never has to know that a change is
/// under way — and the text above it can be tinted from the very same
/// blended colours.
class PrayerCardSkyPainter extends CustomPainter {
  final PrayerSkyTheme theme;
  final Animation<double> animation;

  PrayerCardSkyPainter({required this.theme, required this.animation})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final t = animation.value;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.top, theme.bottom],
        ).createShader(rect),
    );

    if (theme.stars > 0) _paintStars(canvas, size, t);
    if (theme.horizon > 0) _paintHorizon(canvas, size, t);
    if (theme.cloud > 0) _paintCloud(canvas, size, t);
  }

  void _paintStars(Canvas canvas, Size size, double t) {
    final paint = Paint();
    for (final s in _cardStars) {
      // Each star twinkles on its own phase; a dawn field is dimmer
      // because the light is already washing it out.
      final tw = 0.30 + 0.70 * _pulse(t * 2, s.phase);
      paint.color = Colors.white.withValues(alpha: theme.stars * tw * 0.9);
      canvas.drawCircle(
          Offset(s.x * size.width, s.y * size.height), s.size, paint);
    }
  }

  /// The warm band low in the sky: dawn coming up, or the sun going
  /// down. Breathes very slowly.
  void _paintHorizon(Canvas canvas, Size size, double t) {
    final glow = 0.62 + 0.20 * _pulse(t, 0.0);
    final band = Rect.fromLTRB(0, size.height * 0.42, size.width, size.height);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFFFFC98F)
                .withValues(alpha: theme.horizon * glow * 0.55),
            const Color(0xFFFFC98F).withValues(alpha: 0),
          ],
        ).createShader(band),
    );
  }

  /// Thin cloud crossing the card, wrapping round as it leaves.
  void _paintCloud(Canvas canvas, Size size, double t) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final drift = ((t + i * 0.37) % 1.0) * (size.width + 120) - 60;
      final y = size.height * (0.18 + i * 0.19);
      paint
        ..color =
            Colors.white.withValues(alpha: theme.cloud * (0.34 - i * 0.07))
        ..strokeWidth = 5.0 - i * 1.2;
      canvas.drawLine(
          Offset(drift, y), Offset(drift + size.width * 0.28, y), paint);
    }
  }

  @override
  bool shouldRepaint(PrayerCardSkyPainter old) =>
      old.theme.top != theme.top ||
      old.theme.bottom != theme.bottom ||
      old.theme.stars != theme.stars ||
      old.theme.cloud != theme.cloud ||
      old.theme.horizon != theme.horizon ||
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

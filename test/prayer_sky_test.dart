// The prayer card's sky, and the glints on the continue-reading card.
//
// These are BACKGROUNDS, so nothing here asserts what they look like —
// that was settled by rendering them at real size and looking. What is
// worth pinning down is what silently breaks them: an hour that picks
// the wrong sky, ink that stops being readable on the sky under it, or
// a reduce-motion path that stops painting instead of freezing.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/prayer_service.dart';
import 'package:quran_app_v1/widgets/prayer_sky.dart';

/// Runs a painter the way the framework does, so a bad shader surfaces
/// as a failure rather than a red screen.
void _paint(CustomPainter painter, [Size size = const Size(358, 112)]) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

/// WCAG contrast ratio, so "is this text readable on this sky" is a
/// number rather than an opinion.
double _contrast(Color fg, Color bg) {
  final a = fg.computeLuminance(), b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

const _times = PrayerTimes(
  fajr: '04:41',
  dhuhr: '12:25',
  asr: '15:48',
  maghrib: '18:51',
  isha: '20:05',
);

DateTime _at(int h, int m) => DateTime(2026, 8, 15, h, m);

void main() {
  group('which sky the card wears', () {
    test('the hour picks the prayer we are INSIDE, not the next one', () {
      // Just before a prayer we are still in the previous one; a minute
      // after it, we are in it.
      expect(_times.currentPrayerIndex(_at(12, 24)), 0); // still Fajr
      expect(_times.currentPrayerIndex(_at(12, 26)), 1); // now Dhuhr
      expect(_times.currentPrayerIndex(_at(15, 49)), 2); // Asr
      expect(_times.currentPrayerIndex(_at(18, 52)), 3); // Maghrib
      expect(_times.currentPrayerIndex(_at(20, 6)), 4); // Isha
    });

    test('both ends of the night are Isha', () {
      // The stretch before Fajr and the stretch after Isha are one
      // night; the card must not go bright between midnight and dawn.
      expect(_times.currentPrayerIndex(_at(23, 30)), 4);
      expect(_times.currentPrayerIndex(_at(0, 15)), 4);
      expect(_times.currentPrayerIndex(_at(4, 40)), 4);
      // ...and the moment Fajr is called it stops being night.
      expect(_times.currentPrayerIndex(_at(4, 42)), 0);
    });

    test('the next prayer is still answered separately', () {
      // The card highlights the NEXT prayer while wearing the CURRENT
      // one's sky; if these ever collapse into one number the card
      // stops being able to do both.
      expect(_times.nextPrayerIndex(_at(13, 0)), 2);
      expect(_times.currentPrayerIndex(_at(13, 0)), 1);
    });
  });

  group('the ink is readable on its own sky', () {
    test('headline ink clears 4.5:1 on both ends of every sky', () {
      for (var i = 0; i < 5; i++) {
        for (final isDark in [true, false]) {
          final sky = prayerSkyTheme(i, isDark: isDark);
          for (final ground in [sky.top, sky.bottom]) {
            expect(_contrast(sky.ink, ground), greaterThanOrEqualTo(4.5),
                reason: 'prayer $i, isDark=$isDark: the headline and the '
                    'highlighted prayer are set in this');
          }
        }
      }
    });

    test('the quieter ink still clears 3:1', () {
      // Prayer names, at 12.5px — held to the large-text bar rather
      // than body text, but not allowed to become decoration.
      for (var i = 0; i < 5; i++) {
        for (final isDark in [true, false]) {
          final sky = prayerSkyTheme(i, isDark: isDark);
          for (final ground in [sky.top, sky.bottom]) {
            expect(_contrast(sky.inkSoft, ground), greaterThanOrEqualTo(3.0),
                reason: 'prayer $i, isDark=$isDark');
          }
        }
      }
    });

    test('a sky that is dark takes light ink, and the reverse', () {
      // The rule the palette is built on: each sky commits to being a
      // light card or a dark one. A mid-tone sky with mid-tone ink is
      // how this gets quietly ruined later.
      for (var i = 0; i < 5; i++) {
        for (final isDark in [true, false]) {
          final sky = prayerSkyTheme(i, isDark: isDark);
          final skyLum =
              (sky.top.computeLuminance() + sky.bottom.computeLuminance()) / 2;
          final inkLum = sky.ink.computeLuminance();
          expect(skyLum > 0.5, isNot(inkLum > 0.5),
              reason: 'prayer $i, isDark=$isDark: sky and ink are on the '
                  'same side of the line');
        }
      }
    });
  });

  group('the scenes', () {
    test('night has stars and noon does not', () {
      expect(prayerSkyTheme(4, isDark: false).stars, greaterThan(0.5));
      expect(prayerSkyTheme(1, isDark: false).stars, 0);
      // Dawn keeps a few, washed out by the light coming up.
      final fajr = prayerSkyTheme(0, isDark: false);
      expect(fajr.stars, greaterThan(0));
      expect(fajr.stars, lessThan(prayerSkyTheme(4, isDark: false).stars));
      expect(fajr.horizon, greaterThan(0));
    });

    test('every sky paints, in both modes and across the whole cycle', () {
      for (var i = 0; i < 5; i++) {
        for (final isDark in [true, false]) {
          for (var step = 0; step <= 4; step++) {
            _paint(PrayerCardSkyPainter(
              theme: prayerSkyTheme(i, isDark: isDark),
              animation: AlwaysStoppedAnimation<double>(step / 4),
            ));
          }
        }
      }
    });

    test('a half-changed sky paints too', () {
      // What the card is for 1.4 seconds, five times a day.
      for (var step = 0; step <= 4; step++) {
        _paint(PrayerCardSkyPainter(
          theme: PrayerSkyTheme.lerp(prayerSkyTheme(3, isDark: false),
              prayerSkyTheme(4, isDark: false), step / 4),
          animation: kSkyStill,
        ));
      }
    });

    test('a zero-sized card paints nothing rather than throwing', () {
      _paint(
          PrayerCardSkyPainter(
              theme: prayerSkyTheme(0, isDark: false), animation: kSkyStill),
          Size.zero);
      _paint(SparklePainter(animation: kSkyStill), Size.zero);
    });

    test('reduce motion freezes the scene part-lit, never at its dimmest', () {
      // A stopped animation at 0 parks every twinkle at the bottom of
      // its curve, which is what "the stars vanish with animations off"
      // would mean.
      expect(kSkyStill.value, greaterThan(0.2));
      expect(kSkyStill.value, lessThan(0.8));
    });
  });

  test('sparkles paint across the cycle at card size', () {
    for (var step = 0; step <= 10; step++) {
      _paint(SparklePainter(animation: AlwaysStoppedAnimation(step / 10)),
          const Size(358, 132));
    }
  });
}

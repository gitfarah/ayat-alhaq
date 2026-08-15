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

/// Kuala Lumpur — the times the sky rule was actually reported wrong
/// against, kept as the case it has to get right.
const _times = PrayerTimes(
  fajr: '06:00',
  dhuhr: '13:18',
  asr: '16:35',
  maghrib: '19:24',
  isha: '20:31',
);

DateTime _at(int h, int m) => DateTime(2026, 8, 15, h, m);

void main() {
  group('which sky the card wears', () {
    test('between Maghrib and Isha the card is NIGHT, not a sunset', () {
      // The bug this rule exists for. Maghrib's PERIOD runs until Isha
      // is called, but the sunset is long over: at 20:00 it is dark
      // outside and the card is counting down to Isha, so a sunset card
      // reads as simply stuck.
      expect(_times.skyPrayerIndex(_at(20, 0)), 4);
      expect(_times.skyPrayerIndex(_at(19, 30)), 4);
      // ...while the run-up TO Maghrib is when the sunset belongs.
      expect(_times.skyPrayerIndex(_at(18, 45)), 3);
      expect(_times.skyPrayerIndex(_at(17, 0)), 3);
    });

    test('the whole stretch from Isha to Fajr is night', () {
      expect(_times.skyPrayerIndex(_at(21, 0)), 4); // after Isha
      expect(_times.skyPrayerIndex(_at(23, 59)), 4);
      expect(_times.skyPrayerIndex(_at(0, 20)), 4); // past midnight
      expect(_times.skyPrayerIndex(_at(5, 59)), 4); // still dark
    });

    test('dawn is the window after Fajr, not the whole morning', () {
      expect(_times.skyPrayerIndex(_at(6, 5)), 0); // dawn
      expect(_times.skyPrayerIndex(_at(7, 20)), 0); // still dawn
      expect(_times.skyPrayerIndex(_at(7, 40)), 1); // morning is blue
      expect(_times.skyPrayerIndex(_at(11, 0)), 1);
    });

    test('the middle of the day runs blue then gold', () {
      expect(_times.skyPrayerIndex(_at(13, 0)), 1); // before Dhuhr
      expect(_times.skyPrayerIndex(_at(14, 0)), 2); // afternoon gold
      expect(_times.skyPrayerIndex(_at(16, 30)), 2);
    });

    test('the sky and the highlighted prayer stay separate questions', () {
      // Through the day the sky IS the prayer being counted to, which
      // is why the card finally agrees with its own highlight...
      expect(_times.nextPrayerIndex(_at(14, 0)), 2);
      expect(_times.skyPrayerIndex(_at(14, 0)), 2);
      // ...but not at night: Fajr is highlighted from midnight onward,
      // and it is emphatically not dawn at 2am.
      expect(_times.nextPrayerIndex(_at(2, 0)), 0);
      expect(_times.skyPrayerIndex(_at(2, 0)), 4);
    });

    test('every hour of the day maps to a real sky', () {
      for (var h = 0; h < 24; h++) {
        for (final m in [0, 30]) {
          expect(_times.skyPrayerIndex(_at(h, m)), inInclusiveRange(0, 4),
              reason: 'at $h:$m');
        }
      }
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

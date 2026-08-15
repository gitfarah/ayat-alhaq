// The home screen's painted ornaments: a sky behind each prayer, and
// the glints on the continue-reading card.
//
// These are BACKGROUNDS, so nothing here asserts what they look like —
// the look was settled by rendering them at their real size and looking
// at the result, which no assertion can replace. What is worth pinning
// down is what silently breaks them: a sixth prayer index, or a
// reduce-motion path that stops painting instead of freezing.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/widgets/prayer_sky.dart';

/// Runs a painter the way the framework does, so an out-of-range index
/// or a bad shader surfaces as a failure rather than a red screen.
void _paint(CustomPainter painter, [Size size = const Size(63, 74)]) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

void main() {
  test('every prayer has a sky, in both modes and at both strengths', () {
    for (var i = 0; i < 5; i++) {
      for (final isDark in [true, false]) {
        for (final isNext in [true, false]) {
          _paint(PrayerSkyPainter(
            index: i,
            strength: skyStrength(isNext: isNext, isDark: isDark),
            animation: kSkyStill,
          ));
        }
      }
    }
  });

  test('a sky is painted across the whole cycle, not just at t=0', () {
    for (var step = 0; step <= 10; step++) {
      _paint(PrayerSkyPainter(
        index: 4,
        strength: 0.5,
        animation: AlwaysStoppedAnimation<double>(step / 10),
      ));
    }
  });

  test('a zero-sized cell paints nothing rather than throwing', () {
    _paint(PrayerSkyPainter(index: 0, strength: 0.5, animation: kSkyStill),
        Size.zero);
    _paint(SparklePainter(animation: kSkyStill), Size.zero);
  });

  test('reduce motion freezes the scene part-lit, never at its dimmest', () {
    // A stopped animation at 0 would park every twinkle and glow at the
    // bottom of its curve, which is what "the skies look flat when
    // animations are off" would mean.
    expect(kSkyStill.value, greaterThan(0.2));
    expect(kSkyStill.value, lessThan(0.8));
  });

  test('the night sky icon flips direction between light and dark', () {
    // Isha is the one prayer whose sky is dark enough in dark mode to
    // need a pale icon, and light enough in light mode that the same
    // pale icon would vanish. If these ever match, one of the two modes
    // has an invisible crescent.
    final dark = skyIconColor(4, isDark: true)!;
    final light = skyIconColor(4, isDark: false)!;
    expect(dark.computeLuminance(), greaterThan(0.5));
    expect(light.computeLuminance(), lessThan(0.2));
  });

  test('the other prayers keep their shared PrayerVisuals colour', () {
    for (final i in [0, 1, 2, 3]) {
      expect(skyIconColor(i, isDark: true), isNull);
      expect(skyIconColor(i, isDark: false), isNull);
    }
  });

  test('the next prayer always gets the livelier sky', () {
    for (final isDark in [true, false]) {
      expect(skyStrength(isNext: true, isDark: isDark),
          greaterThan(skyStrength(isNext: false, isDark: isDark)));
    }
  });

  test('sparkles paint across the cycle at card size', () {
    for (var step = 0; step <= 10; step++) {
      _paint(SparklePainter(animation: AlwaysStoppedAnimation(step / 10)),
          const Size(358, 132));
    }
  });
}

// Regression test for the 2026-08-xx report: the Madinah V1 (1405H)
// page font reads noticeably heavier than V2/V4, "looks bold".
//
// Verified against the font files themselves (not just by eye) that
// this is not a weight metadata issue Flutter/Skia could resolve by
// picking a lighter sibling face: every page of V1, V2 and V4 declares
// OS/2.usWeightClass = 400 and no bold bit in head.macStyle. QUL's V1
// outlines are simply drawn with a thicker stroke, and there is no
// thinner variant on their CDN — so the fix is a slightly translucent
// ink for V1 only, applied in mushaf_svg_screen.dart's rawGlyph().
//
// This test pins the pure selection function so a future edit cannot
// silently apply it to the wrong edition or drop it entirely.

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/screens/mushaf_svg_screen.dart';

void main() {
  group('mushafGlyphInkOpacity', () {
    test('V1 (1405H) — the reported edition — is lightened', () {
      final opacity = mushafGlyphInkOpacity('madinah1405');
      expect(opacity, lessThan(1.0),
          reason: 'V1 must be less than fully opaque, or the reported '
              'boldness is unchanged');
      // Enough to visibly lighten a heavy stroke without reading as
      // faded/low-contrast Quranic script.
      expect(opacity, greaterThan(0.7));
    });

    test('every other glyph edition stays fully opaque', () {
      // V4 (KFGQPC Hafs) was never part of the complaint — a blanket
      // "lighten every edition" fix would be wrong, this must stay
      // scoped to V1 alone.
      for (final id in ['hafs', 'hafs_plain']) {
        expect(mushafGlyphInkOpacity(id), 1.0, reason: id);
      }
    });

    test('an unrecognised id is not silently lightened', () {
      // Defends the >= comparison direction: a typo'd or future
      // edition id must fall back to full strength, not to V1's
      // reduced opacity.
      expect(mushafGlyphInkOpacity('some-future-edition'), 1.0);
    });
  });
}

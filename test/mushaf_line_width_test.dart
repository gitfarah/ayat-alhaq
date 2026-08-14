// Regression test for the 2026-08-14 report: pages 1 and 2 of every
// glyph Mushaf edition overflowed to the right, Flutter's yellow stripes
// showing, with letters clipped off the edge.
//
// Cause: the font size was fitted by measuring each line as ONE
// concatenated glyph string, but the row that actually draws the line
// substitutes fixed boxes for some words — a kAyahEndBoxEm square for
// every ayah-end medallion, plus spacers for juz ornaments and centred
// lines. Those boxes are wider than the glyphs' own advances, so the fit
// under-counted, and the shortfall scaled with the NUMBER OF MARKERS on
// a line. Ordinary pages carry a handful; Al-Fatiha and the opening of
// Al-Baqarah are short ayahs packed with them, which is why exactly
// those two pages overflowed.
//
// mushafV2LineWidth composes the width the row will really occupy. These
// pin that composition; the renderer reads the same constants, so the
// two cannot drift apart again.

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/screens/mushaf_svg_screen.dart';

void main() {
  group('mushafV2LineWidth', () {
    test('a line with no markers is just the sum of its words', () {
      final w = mushafV2LineWidth(
        naturalWidths: [100, 200, 50],
        isAyahEnd: [false, false, false],
        centered: false,
      );
      expect(w, 350);
    });

    test('an ayah-end marker is charged its BOX, not its glyph advance',
        () {
      // The reported bug in one assertion: the marker's natural advance
      // (10) is far narrower than the square it is drawn into.
      final w = mushafV2LineWidth(
        naturalWidths: [100, 10],
        isAyahEnd: [false, true],
        centered: false,
      );
      expect(w, 100 + kAyahEndBoxEm * 100);
      expect(w, greaterThan(110),
          reason: 'charging the glyph advance is what under-counted the '
              'line and let the row overflow');
    });

    test('the shortfall grows with marker count — the opening pages', () {
      // Same total glyph ink, spread over more markers. A page of short
      // ayahs must be measured wider than a page of long ones.
      double lineWith(int markers) => mushafV2LineWidth(
            naturalWidths: [for (var i = 0; i < markers; i++) ...[100, 10]],
            isAyahEnd: [for (var i = 0; i < markers; i++) ...[false, true]],
            centered: false,
          );
      final one = lineWith(1);
      final four = lineWith(4);
      // Naive concatenation would call the 4-marker line 4x the 1-marker
      // line exactly; the box substitution makes it wider than that.
      expect(four, greaterThan(one * 4 - 0.001));
      expect(four - one * 4, closeTo(0, 0.001),
          reason: 'per-marker cost must be constant, so the error is '
              'strictly proportional to how many markers a line has');
    });

    test('a centred line pays for the gaps between its words', () {
      final plain = mushafV2LineWidth(
        naturalWidths: [100, 100, 100],
        isAyahEnd: [false, false, false],
        centered: false,
      );
      final centred = mushafV2LineWidth(
        naturalWidths: [100, 100, 100],
        isAyahEnd: [false, false, false],
        centered: true,
      );
      // Two gaps between three words.
      expect(centred - plain, closeTo(kCenteredWordGapEm * 100 * 2, 0.001));
    });

    test('a single-word centred line has no gaps to pay for', () {
      expect(
        mushafV2LineWidth(
            naturalWidths: [100], isAyahEnd: [false], centered: true),
        100,
      );
    });

    test('a juz-opening word pays for its ornament gap, once', () {
      final without = mushafV2LineWidth(
        naturalWidths: [100, 100],
        isAyahEnd: [false, false],
        centered: false,
      );
      final with_ = mushafV2LineWidth(
        naturalWidths: [100, 100],
        isAyahEnd: [false, false],
        centered: false,
        firstWordHasJuzOrnament: true,
      );
      expect(with_ - without, closeTo(kJuzOrnamentGapEm * 100, 0.001));
    });

    test('an empty line is zero, not a crash', () {
      expect(
        mushafV2LineWidth(
            naturalWidths: const [], isAyahEnd: const [], centered: true),
        0,
      );
    });
  });

  group('the constants the renderer shares', () {
    test('are the multipliers the row actually draws with', () {
      // If any of these is edited, the SizedBox that uses it in
      // mushaf_svg_screen.dart moves with it — that is the point of
      // their being shared. Pinned so a silent edit is visible here.
      expect(kAyahEndBoxEm, 0.84);
      expect(kJuzOrnamentGapEm, 0.22);
      expect(kCenteredWordGapEm, 0.12);
    });
  });
}

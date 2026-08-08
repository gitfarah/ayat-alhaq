// Regression test for the 2026-08-05 report: on real iPads in portrait
// (never touched in landscape, never on phones), the Madinah V1/V2/V4
// Mushaf leaf sat at full screen width with tight vertical line
// spacing — "very wide... text is almost hard to read... small space
// between the lines."
//
// Root cause, proven by pure device-dimension arithmetic (no font
// metrics needed): portrait multiplied maxHeight by 0.72 to cap the
// leaf's width, but every real iPad's own portrait aspect ratio
// (width/height) already exceeds 0.72, so `maxHeight * 0.72` was never
// the smaller side of the min() — the clamp never bound. The leaf sat
// at full screen width, which stretches the spaceBetween-justified
// words across it, AND independently a tablet's flatter aspect ratio
// (vs. a phone's much taller one) makes the font's HEIGHT constraint
// bind instead of its WIDTH constraint, filling nearly the whole row
// budget and crowding adjacent lines' diacritics together.
//
// These tests assert the geometric fix directly, against real device
// content-area dimensions, and are independent of font metrics — they
// would fail identically whether or not a real Mushaf font is loaded.

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/screens/mushaf_svg_screen.dart';

void main() {
  group('mushafV2LeafWidth', () {
    // Logical-point content areas: device portrait size, minus a
    // representative status-bar + app-bar + bottom-nav allowance.
    const devices = {
      'iPad 10th gen': (width: 820.0, height: 1180.0 - 140),
      'iPad Pro 11"': (width: 834.0, height: 1194.0 - 140),
      'iPad Pro 12.9"': (width: 1024.0, height: 1366.0 - 140),
      'iPad mini': (width: 744.0, height: 1133.0 - 140),
      'iPad Air': (width: 820.0, height: 1180.0 - 140),
    };

    for (final entry in devices.entries) {
      test('${entry.key} portrait: the leaf actually narrows', () {
        final leaf = mushafV2LeafWidth(
          maxWidth: entry.value.width,
          maxHeight: entry.value.height,
          isTablet: true,
        );
        // The bug's exact signature: leafWidth == maxWidth means the
        // clamp was a no-op and the page sat at full screen width.
        expect(leaf, lessThan(entry.value.width),
            reason: '${entry.key} portrait did not narrow — this is '
                'the reported bug returning');
        // Not so aggressive that it looks like a phone-width column
        // floating in a sea of margin.
        expect(leaf / entry.value.width, greaterThan(0.55));
        // The tablet rule must stay narrower than the phone one, or
        // tablets would silently inherit the phone margin instead of
        // their book column.
        expect(leaf, lessThan(entry.value.width * 0.94),
            reason: '${entry.key} is no narrower than a phone margin');
      });
    }

    test('landscape and portrait now use the same, already-proven '
        'multiplier', () {
      // Landscape (short, wide content area) already relied on 0.58 to
      // bind and was never part of the complaint. Both orientations
      // must produce the same leaf/height ratio for a given height, so
      // a future edit cannot silently special-case one of them again.
      const maxHeight = 700.0;
      final landscapeLike = mushafV2LeafWidth(
          maxWidth: 1200, maxHeight: maxHeight, isTablet: true);
      final portraitLike = mushafV2LeafWidth(
          maxWidth: 500, maxHeight: maxHeight, isTablet: true);
      // Landscape is width-capped (1200 > 700*0.58); portrait's own
      // width (500) already sits below the same cap, so both equal
      // maxHeight * 0.58 here — proving one shared rule, not two.
      expect(landscapeLike, closeTo(maxHeight * 0.58, 0.01));
      expect(portraitLike, closeTo(maxHeight * 0.58, 0.01));
    });

    // 2026-08-08: this requirement REVERSED. Phones were previously
    // pinned to full width on purpose ("phones must not change" when
    // the iPad bug was fixed); the reported problem now is that full
    // width leaves the script hard against both screen edges, because
    // spaceBetween justification always fills whatever width the leaf
    // is given. Phones now get a slim margin; tablets are unaffected.
    group('phones get a side margin', () {
      // Portrait content areas of real phones (logical points).
      const phones = {
        'iPhone SE': (width: 375.0, height: 667.0 - 140),
        'iPhone 14': (width: 390.0, height: 844.0 - 140),
        'iPhone 14 Pro Max': (width: 430.0, height: 932.0 - 140),
        'Pixel 7': (width: 412.0, height: 915.0 - 140),
      };

      for (final entry in phones.entries) {
        test('${entry.key}: the leaf clears both edges', () {
          final leaf = mushafV2LeafWidth(
            maxWidth: entry.value.width,
            maxHeight: entry.value.height,
            isTablet: false,
          );

          expect(leaf, lessThan(entry.value.width),
              reason: '${entry.key} still fills the full width — the '
                  'script would touch both screen edges');

          // Real, visible margin on each side, but not so much that it
          // eats the script: the font size scales with the leaf.
          final sideMargin = (entry.value.width - leaf) / 2;
          expect(sideMargin, greaterThan(8.0),
              reason: 'too slim to read as a margin');
          expect(sideMargin, lessThan(20.0),
              reason: 'so wide the text shrinks noticeably');
        });
      }

      test('height never binds on a phone — the margin is the only '
          'thing narrowing it', () {
        // A phone's leaf must not pick up the tablet 0.58 rule, which
        // on a tall phone would crush it to a narrow column.
        final leaf =
            mushafV2LeafWidth(maxWidth: 390, maxHeight: 2000, isTablet: false);
        expect(leaf, closeTo(390 * 0.94, 0.01));
      });
    });

    test('a very short/wide tablet window still binds', () {
      // Extreme landscape (e.g. a floating multitasking window) — the
      // multiplier must still produce a real book column, not the
      // full width, however the window is shaped.
      final leaf =
          mushafV2LeafWidth(maxWidth: 1400, maxHeight: 500, isTablet: true);
      expect(leaf, closeTo(500 * 0.58, 0.01));
    });
  });

  group('mushafV2HeightFraction', () {
    test('tablets get more inter-line breathing room than phones', () {
      // The direct fix for "small space between the lines": tablets
      // must use LESS of the row height than phones, or the font
      // fills the row edge to edge and adjacent lines crowd together.
      final tablet =
          mushafV2HeightFraction(isTablet: true, isOpeningPage: false);
      final phone =
          mushafV2HeightFraction(isTablet: false, isOpeningPage: false);
      expect(tablet, lessThan(phone),
          reason: 'tablets need MORE headroom between lines than '
              'phones, not the same amount');
      expect(phone, 0.88, reason: 'phones were already fine — must not move');
    });

    test('opening pages (١-٢) keep their own, smaller fraction on '
        'every device', () {
      // The Fatiha/opening-of-Baqarah pages already had a dedicated,
      // more generous fraction for their much shorter line count —
      // this must stay untouched by the tablet fix.
      expect(mushafV2HeightFraction(isTablet: true, isOpeningPage: true),
          0.78);
      expect(mushafV2HeightFraction(isTablet: false, isOpeningPage: true),
          0.78);
    });
  });
}

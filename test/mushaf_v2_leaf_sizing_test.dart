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

    // 2026-08-08: phones were given a slim side margin, because at full
    // width spaceBetween justification put the first and last word of
    // every line hard against the bezel.
    //
    // 2026-08-13: that margin was cut back again — "0.94 → 0.99 is
    // still not enough for iphone/android mobiles! Touch that margin
    // and go ahead". It stacked with the leaf's padding and the
    // layout's usable-width inset, and the three together cost about
    // 14% of the screen. The leaf is now nearly full width; the margin
    // that remains comes from mushafV2WidthFactor holding the widest
    // line just inside it.
    group('phones give the script nearly the whole width', () {
      // Portrait content areas of real phones (logical points).
      const phones = {
        'iPhone SE': (width: 375.0, height: 667.0 - 140),
        'iPhone 14': (width: 390.0, height: 844.0 - 140),
        'iPhone 14 Pro Max': (width: 430.0, height: 932.0 - 140),
        'Pixel 7': (width: 412.0, height: 915.0 - 140),
      };

      for (final entry in phones.entries) {
        test('${entry.key}: the leaf keeps a hairline, not a margin', () {
          final leaf = mushafV2LeafWidth(
            maxWidth: entry.value.width,
            maxHeight: entry.value.height,
            isTablet: false,
          );

          // Still not edge to edge — the leaf is what the page's
          // background and furniture are drawn into.
          expect(leaf, lessThan(entry.value.width));
          // ...but the old 8-20pt-a-side margin is gone.
          final sideMargin = (entry.value.width - leaf) / 2;
          expect(sideMargin, lessThan(4.0),
              reason: '${entry.key} still spends a visible margin here — '
                  'that width belongs to the script now');
          expect(leaf / entry.value.width, greaterThan(0.97));
        });
      }

      test('the script gained real width over the old rule', () {
        // The whole point of the change: compare the leaf a phone gets
        // now against what the previous 0.94 rule gave it. The font
        // size scales with this width, so this IS the size increase.
        const width = 390.0;
        final now =
            mushafV2LeafWidth(maxWidth: width, maxHeight: 704, isTablet: false);
        const before = width * 0.94;
        expect(now / before, greaterThan(1.04),
            reason: 'the leaf barely moved — the text will look the same');
      });

      test('height never binds on a phone — nothing narrows it but the '
          'leaf fraction', () {
        // A phone's leaf must not pick up the tablet 0.58 rule, which
        // on a tall phone would crush it to a narrow column.
        final leaf =
            mushafV2LeafWidth(maxWidth: 390, maxHeight: 2000, isTablet: false);
        expect(leaf, closeTo(390 * 0.99, 0.01));
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
      for (final edition in _editions) {
        final tablet = mushafV2HeightFraction(
            isTablet: true, isOpeningPage: false, editionId: edition);
        final phone = mushafV2HeightFraction(
            isTablet: false, isOpeningPage: false, editionId: edition);
        expect(tablet, lessThan(phone),
            reason: 'tablets need MORE headroom between lines than '
                'phones, not the same amount ($edition)');
      }
    });

    test('opening pages (١-٢) keep their own, smaller fraction on '
        'every device', () {
      // The Fatiha/opening-of-Baqarah pages already had a dedicated,
      // more generous fraction for their much shorter line count —
      // this must stay untouched by the tablet fix.
      for (final edition in _editions) {
        expect(
            mushafV2HeightFraction(
                isTablet: true, isOpeningPage: true, editionId: edition),
            0.78);
        expect(
            mushafV2HeightFraction(
                isTablet: false, isOpeningPage: true, editionId: edition),
            0.78);
      }
    });
  });

  // 2026-08-13: "make the fontSize a bit bigger for the 3, specially for
  // V1 because that one is very small in iphone/mobiles... All musahf
  // types have good font size in ipads, so don't change anything in the
  // ipad versions."
  group('phones get a larger glyph than before; tablets do not move', () {
    // The values the iPad line-spread fix settled on. Any change to
    // these is a regression of that fix, whatever the phone needs.
    const tabletWidthFactor = 0.91;
    const tabletHeightFraction = 0.80;

    test('every tablet value is exactly as the iPad fix left it', () {
      for (final edition in _editions) {
        expect(mushafV2WidthFactor(isTablet: true, editionId: edition),
            tabletWidthFactor,
            reason: '$edition changed the iPad width factor');
        expect(
            mushafV2HeightFraction(
                isTablet: true, isOpeningPage: false, editionId: edition),
            tabletHeightFraction,
            reason: '$edition changed the iPad height fraction');
      }
    });

    test('every edition draws larger on a phone than it used to', () {
      // The previous shared phone values.
      const wasWidth = 0.94;
      const wasHeight = 0.88;
      for (final edition in _editions) {
        expect(mushafV2WidthFactor(isTablet: false, editionId: edition),
            greaterThan(wasWidth),
            reason: '$edition is no wider on a phone than before');
        expect(
            mushafV2HeightFraction(
                isTablet: false, isOpeningPage: false, editionId: edition),
            greaterThan(wasHeight),
            reason: '$edition has no more row height on a phone than before');
      }
    });

    test('the allowances run V1 > V2 > V4, as the fonts draw', () {
      // Reported from the phone: V4 reads right, V2 is small, V1 is
      // smaller still. The budgets must follow that order.
      double h(String e) => mushafV2HeightFraction(
          isTablet: false, isOpeningPage: false, editionId: e);
      double w(String e) =>
          mushafV2WidthFactor(isTablet: false, editionId: e);

      expect(h('madinah1405'), greaterThan(h('madinah1421')),
          reason: 'V1 must get more room than V2');
      expect(h('madinah1421'), greaterThan(h('hafs')),
          reason: 'V2 was reported small next to V4 and must get more room');
      expect(w('madinah1405'), greaterThanOrEqualTo(w('madinah1421')));
      expect(w('madinah1421'), greaterThanOrEqualTo(w('hafs')));
    });

    test('nothing is allowed to overflow the leaf it is measured into', () {
      // The width factor scales the size at which the WIDEST line
      // exactly fills the usable width, so above 1.0 that line would be
      // clipped or forced to wrap.
      for (final isTablet in [true, false]) {
        for (final edition in _editions) {
          expect(mushafV2WidthFactor(isTablet: isTablet, editionId: edition),
              lessThanOrEqualTo(1.0),
              reason: '$edition would overflow the leaf');
        }
      }
    });

    test('an unknown edition still gets sane values', () {
      // A future edition must not fall through to zero and vanish.
      expect(mushafV2WidthFactor(isTablet: false, editionId: 'something-new'),
          inInclusiveRange(0.9, 1.0));
      expect(
          mushafV2HeightFraction(
              isTablet: false, isOpeningPage: false, editionId: 'something-new'),
          inInclusiveRange(0.8, 1.0));
    });
  });
}

/// The three glyph editions, by the ids MushafSvgService uses.
const _editions = ['hafs', 'madinah1421', 'madinah1405'];

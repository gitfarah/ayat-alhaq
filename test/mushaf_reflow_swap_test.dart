// Pinch-to-reflow: the printed Mushaf and the responsive view as ONE
// surface, swapping under a pinch instead of being two editions to pick
// between (the Golden Quran model).
//
// The rule these guard is a CORRECTNESS one, not a preference. The
// reflowing page is typeset from the bundled Hafs text on Hafs
// pagination. The three glyph editions are Madinah Hafs prints, so their
// page N holds what page N holds here. The four artwork riwayat — Warsh,
// Qalon, Shu'bah, ad-Duri — are different readings AND paginate
// differently, so reflowing one of their pages would put the WRONG WORDS
// on screen under a gesture the reader thinks is only a zoom.

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/screens/mushaf_svg_screen.dart';
import 'package:quran_app_v1/services/mushaf_svg_service.dart';

void main() {
  /// Every edition the app offers, split by whether reflowing its page
  /// would be faithful — read from the service rather than hard-coded,
  /// so a newly added edition has to be classified here to pass.
  final glyph =
      MushafSvgService.editions.where((e) => e.isGlyph).map((e) => e.id);
  final artwork =
      MushafSvgService.editions.where((e) => e.isArtwork).map((e) => e.id);
  final text =
      MushafSvgService.editions.where((e) => e.isText).map((e) => e.id);

  group('which editions may reflow', () {
    test('the Hafs glyph editions do, pinched out', () {
      expect(glyph, isNotEmpty, reason: 'sanity: the set is not empty');
      for (final id in glyph) {
        expect(mushafShowsReflow(editionId: id, zoom: 2.0), isTrue,
            reason: id);
      }
    });

    test('the artwork riwayat NEVER do, at any zoom', () {
      expect(artwork, isNotEmpty);
      for (final id in artwork) {
        for (final z in [1.0, kReflowZoom, 2.0, 3.5, 99.0]) {
          expect(mushafShowsReflow(editionId: id, zoom: z), isFalse,
              reason: '$id at $z — a different riwayah reflowed from the '
                  'Hafs text would show the wrong words');
        }
      }
    });

    test('the reflowing edition itself does not "swap" — it already is '
        'the text', () {
      for (final id in text) {
        expect(mushafShowsReflow(editionId: id, zoom: 3.0), isFalse,
            reason: id);
      }
    });

    test('an unknown edition id never reflows', () {
      // Defends the lookup: a typo or a future edition must fall back to
      // the printed page, not to reflowing text of unverified pagination.
      expect(mushafShowsReflow(editionId: 'not-an-edition', zoom: 3.0),
          isFalse);
      expect(mushafShowsReflow(editionId: '', zoom: 3.0), isFalse);
    });
  });

  group('the threshold', () {
    final id = glyph.first;

    test('an unpinched page is printed', () {
      expect(mushafShowsReflow(editionId: id, zoom: 1.0), isFalse);
    });

    test('just under the threshold is still printed', () {
      expect(mushafShowsReflow(editionId: id, zoom: kReflowZoom - 0.01),
          isFalse);
    });

    test('exactly at the threshold has swapped', () {
      expect(mushafShowsReflow(editionId: id, zoom: kReflowZoom), isTrue);
    });

    test('sits above 1.0 by a real margin, so a sloppy pinch cannot flip '
        'the surface', () {
      expect(kReflowZoom, greaterThan(1.05));
      // ...but low enough that the reflowed type arrives larger than the
      // print rather than smaller — the text is drawn at its page-filling
      // fitted size TIMES this.
      expect(kReflowZoom, lessThan(1.5));
    });
  });
}

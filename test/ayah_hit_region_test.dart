import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/mushaf_svg_service.dart';

void main() {
  group('AyahHitRegion polygon parsing & hit-testing', () {
    // Real entry from page 50 (surah 3, ayah 3): the ayah spans two
    // lines, so its polygon is TWO sub-rectangles.
    final region = AyahHitRegion.fromJson({
      'surahNumber': 3,
      'ayahNumber': 3,
      'x': 36.45,
      'y': 136.2,
      'polygon': 'M 5.0 86.6 L 114.72 86.6 L 114.72 118.43 L 5.0 118.43 Z '
          'M 24.58 118.43 L 340.0 118.43 L 340.0 154.2 L 24.58 154.2 Z',
    });

    test('splits the path into one ring per line', () {
      expect(region.rings.length, 2);
      expect(region.rings[0].length, 8); // 4 corners
      expect(region.rings[1].length, 8);
    });

    test('point inside the first line-rect is inside', () {
      expect(region.containsPoint(60, 100), isTrue);
    });

    test('point inside the second line-rect is inside', () {
      expect(region.containsPoint(200, 140), isTrue);
    });

    test('point on the first line but outside this ayah is NOT inside '
        '(bounding box would wrongly claim it)', () {
      // (200, 100) is on line 1, x beyond 114.72 — belongs to the
      // neighbouring ayah. The old bounding-box check (5..340 x
      // 86.6..154.2) would have claimed it.
      expect(region.containsPoint(200, 100), isFalse);
    });

    test('point outside everything is not inside', () {
      expect(region.containsPoint(400, 400), isFalse);
      expect(region.containsPoint(10, 160), isFalse);
    });

    test('plain point-list polygon still parses as one ring', () {
      final simple = AyahHitRegion.fromJson({
        'surahNumber': 1,
        'ayahNumber': 1,
        'x': 0,
        'y': 0,
        'polygon': '0,0 10,0 10,10 0,10',
      });
      expect(simple.rings.length, 1);
      expect(simple.containsPoint(5, 5), isTrue);
      expect(simple.containsPoint(15, 5), isFalse);
    });
  });
}

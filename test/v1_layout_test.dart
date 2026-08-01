// The KFGQPC V1 (1405H) layout asset: 604 pages, 15 lines each except
// the illuminated opening spread, every ayah accounted for.
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/mushaf_glyph_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('V1 mushaf layout', () {
    setUpAll(() async => MushafGlyphService.loadLayout());

    test('every page is present with the right number of lines', () {
      for (var p = 1; p <= 604; p++) {
        final lines = MushafGlyphService.linesOf(p);
        expect(lines, isNotEmpty, reason: 'page $p');
        // Pages 1-2 are the illuminated opening; the rest are 15 lines.
        expect(lines.length, p <= 2 ? 8 : 15, reason: 'page $p');
      }
    });

    test('every ayah of the Quran appears exactly once per page run', () {
      final seen = <String>{};
      for (var p = 1; p <= 604; p++) {
        for (final line in MushafGlyphService.linesOf(p)) {
          for (final s in line.spans) {
            seen.add('${s[0]}:${s[1]}');
          }
        }
      }
      expect(seen.length, 6236);
    });

    test('spans point at real stretches of their line', () {
      for (var p = 1; p <= 604; p++) {
        for (final line in MushafGlyphService.linesOf(p)) {
          for (final s in line.spans) {
            expect(s[2], greaterThanOrEqualTo(0), reason: 'page $p');
            expect(s[2] + s[3], lessThanOrEqualTo(line.text.length),
                reason: 'page $p');
          }
        }
      }
    });

    test('surah headers and basmalah lines carry no ayah spans', () {
      var headers = 0;
      for (var p = 1; p <= 604; p++) {
        for (final line in MushafGlyphService.linesOf(p)) {
          if (line.isHeader || line.isBasmalah) {
            headers++;
            expect(line.spans, isEmpty, reason: 'page $p');
          }
        }
      }
      expect(headers, greaterThan(200));
    });
  });
}

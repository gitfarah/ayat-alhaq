import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/mushaf_glyph_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('V1 header surah numbers', () {
    setUpAll(() async => MushafGlyphService.loadLayout());

    test('every header line resolves to a surah, in order 1..114', () {
      final found = <int>[];
      for (var page = 1; page <= 604; page++) {
        for (final line in MushafGlyphService.linesOf(page)) {
          if (line.isHeader) found.add(line.surahNumber!);
        }
      }
      expect(found.length, 114, reason: 'one header per surah');
      expect(found, List.generate(114, (i) => i + 1));
    });

    test('a header on the LAST line of a page still resolves', () {
      // An-Nisa (4) opens on page 77, but its header sits at the foot
      // of page 76 — the layout puts the title wherever the printed
      // leaf had room for it, not always at the top of the new page.
      final page76 = MushafGlyphService.linesOf(76);
      final header = page76.last;
      expect(header.isHeader, isTrue);
      expect(header.surahNumber, 4);
    });

    test('a header at the TOP of its own page also resolves', () {
      final page1 = MushafGlyphService.linesOf(1).first;
      expect(page1.isHeader, isTrue);
      expect(page1.surahNumber, 1);
    });
  });

  group('voweledSurahName', () {
    test('carries full tashkeel, unlike the header glyph text', () {
      final name = MushafGlyphService.voweledSurahName(4);
      expect(name, contains('سُورَةُ'));
      expect(name, contains('النِّسَاءِ'));
    });

    test('covers all 114 surahs', () {
      for (var n = 1; n <= 114; n++) {
        expect(MushafGlyphService.voweledSurahName(n), isNotEmpty,
            reason: 'surah $n');
      }
    });
  });
}

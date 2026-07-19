import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/models/quran_page_meta.dart';

void main() {
  group('QuranPageMeta.ayahCounts / globalAyahNumber', () {
    test('counts cover all 114 surahs and total 6236 ayahs', () {
      expect(QuranPageMeta.ayahCounts.length, 114);
      expect(QuranPageMeta.ayahCounts.reduce((a, b) => a + b), 6236);
    });

    test('well-known surah lengths', () {
      expect(QuranPageMeta.ayahCounts[0], 7); // الفاتحة
      expect(QuranPageMeta.ayahCounts[1], 286); // البقرة
      expect(QuranPageMeta.ayahCounts[8], 129); // التوبة
      expect(QuranPageMeta.ayahCounts[35], 83); // يس
      expect(QuranPageMeta.ayahCounts[113], 6); // الناس
    });

    test('global ayah numbers match the alquran.cloud numbering', () {
      // Anchors confirmed against the live API: surah 2 ayah 1 has
      // global number 8, and surah 2 ayah 286 has global number 293.
      expect(QuranPageMeta.globalAyahNumber(1, 1), 1);
      expect(QuranPageMeta.globalAyahNumber(1, 7), 7);
      expect(QuranPageMeta.globalAyahNumber(2, 1), 8);
      expect(QuranPageMeta.globalAyahNumber(2, 286), 293);
      expect(QuranPageMeta.globalAyahNumber(114, 6), 6236);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/mushaf_svg_service.dart';
import 'package:quran_app_v1/services/quran_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuranService.ayahsOnPage', () {
    test('page 1 is Al-Fatiha in full', () async {
      final page = await QuranService.ayahsOnPage(1);
      expect(page.length, 7);
      expect(page.every((a) => a.surahNumber == 1), isTrue);
      expect(page.first.numberInSurah, 1);
      expect(page.last.numberInSurah, 7);
    });

    test('a page spanning a surah boundary returns both surahs in order',
        () async {
      // Al-Fatiha ends on page 1, so page 2 opens Al-Baqarah.
      final page = await QuranService.ayahsOnPage(2);
      expect(page.first.surahNumber, 2);
      expect(page.first.numberInSurah, 1);
      // Page 604 closes the Mushaf with the last three surahs.
      final last = await QuranService.ayahsOnPage(604);
      expect(last.map((a) => a.surahNumber).toSet(), {112, 113, 114});
      expect(last.last.surahNumber, 114);
      expect(last.last.numberInSurah, 6);
    });

    test('the Basmala is stripped from an opening ayah', () async {
      final page = await QuranService.ayahsOnPage(604);
      final ikhlas = page.firstWhere(
          (a) => a.surahNumber == 112 && a.numberInSurah == 1);
      expect(ikhlas.text, isNot(contains('بِسْمِ')));
      // ...but Al-Fatiha's first ayah IS the Basmala, so it stays.
      final fatiha = (await QuranService.ayahsOnPage(1)).first;
      expect(fatiha.text, contains('بِسْمِ'));
    });

    test('every one of the 604 pages has text', () async {
      for (var p = 1; p <= 604; p++) {
        expect((await QuranService.ayahsOnPage(p)), isNotEmpty,
            reason: 'page $p came back empty');
      }
    });
  });

  group('Mushaf editions', () {
    test('the reflowing text edition needs no download', () {
      MushafSvgService.setEdition('text');
      expect(MushafSvgService.edition.isText, isTrue);
      expect(MushafSvgService.supportsFullOfflineDownload, isFalse);
      MushafSvgService.setEdition('hafs');
      expect(MushafSvgService.edition.isText, isFalse);
    });

    test('an unknown edition id falls back to Hafs', () {
      MushafSvgService.setEdition('nope');
      expect(MushafSvgService.edition.id, 'hafs');
    });
  });
}

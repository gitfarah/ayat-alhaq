import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/mushaf_svg_service.dart';
import 'package:quran_app_v1/services/quran_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  checkFontSafe();

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
      final ikhlas =
          page.firstWhere((a) => a.surahNumber == 112 && a.numberInSurah == 1);
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
    test('the reflowing view is no longer an edition, and selecting it '
        'falls back to Hafs', () {
      // It became the state a Hafs page enters when pinched, so it is
      // not something to choose between. Anyone whose saved preference
      // still names it must land on a real edition rather than on
      // nothing — setEdition's orElse is what carries them.
      expect(MushafSvgService.editions.any((e) => e.id == 'text'), isFalse,
          reason: 'the reflowing view must not be offered as an edition');

      MushafSvgService.setEdition('madinah1405');
      MushafSvgService.setEdition('text');
      expect(MushafSvgService.edition.id, 'hafs',
          reason: 'a stale "text" preference must fall back to Hafs');
      MushafSvgService.setEdition('hafs');
    });

    test('a stale "madinah1421" preference falls back to Hafs too', () {
      // V2/1421H was removed as an edition (its "Hafs without colour"
      // need is now covered by V4's own plain cut via the tajweed
      // switch) — setEdition's own orElse fallback is what carries
      // anyone whose saved preference still names it.
      MushafSvgService.setEdition('madinah1405');
      MushafSvgService.setEdition('madinah1421');
      expect(MushafSvgService.edition.id, 'hafs',
          reason: 'a stale "madinah1421" preference must fall back to Hafs');
      MushafSvgService.setEdition('hafs');
    });

    test('V4 Hafs and V1 1405H lead the menu', () {
      expect(MushafSvgService.editions[0].id, 'hafs');
      expect(MushafSvgService.editions[0].nameEn, 'Musahf Hafs with Tajweed');
      expect(MushafSvgService.editions[0].isGlyph, isTrue);
      expect(MushafSvgService.editions[1].id, 'madinah1405');
      expect(MushafSvgService.editions[1].nameEn, 'Midinah Hafs Musahf 1405 H');
      expect(MushafSvgService.editions[1].isGlyph, isTrue);
    });

    test('the 1405H Madinah edition is a live printed-page view', () {
      MushafSvgService.setEdition('madinah1405');
      expect(MushafSvgService.edition.isGlyph, isTrue);
      expect(MushafSvgService.edition.isArtwork, isFalse);
      expect(MushafSvgService.supportsFullOfflineDownload, isFalse);
      MushafSvgService.setEdition('hafs');
    });
    test('the bundled QUL V4 layout contains all 604 pages and ayah ends',
        () async {
      final raw = await rootBundle
          .loadString('assets/quran/mushaf_v4_1441h_layout.json');
      final pages = (jsonDecode(raw) as Map<String, dynamic>)['pages'] as List;
      expect(pages.length, 604);
      var ayahEnds = 0;
      for (var index = 0; index < pages.length; index++) {
        final page = pages[index] as Map<String, dynamic>;
        expect(page['p'], index + 1);
        final lines = page['l'] as List;
        expect(lines, isNotEmpty, reason: 'page ${index + 1}');
        expect(lines.length, lessThanOrEqualTo(15),
            reason: 'page ${index + 1}');
        for (final line in lines.cast<Map<String, dynamic>>()) {
          for (final word in (line['w'] as List? ?? const [])) {
            final values = word as List;
            if (values.length > 2 && values[2] == 1) ayahEnds++;
          }
        }
      }
      expect(ayahEnds, 6236);
    });
    test('the bundled QUL V2 layout contains all 604 pages', () async {
      final raw = await rootBundle
          .loadString('assets/quran/mushaf_v2_1421h_layout.json');
      final pages = (jsonDecode(raw) as Map<String, dynamic>)['pages'] as List;
      expect(pages.length, 604);
      for (var index = 0; index < pages.length; index++) {
        final page = pages[index] as Map<String, dynamic>;
        expect(page['p'], index + 1);
        final lines = page['l'] as List;
        expect(lines, isNotEmpty, reason: 'page ${index + 1}');
        expect(lines.length, lessThanOrEqualTo(15),
            reason: 'page ${index + 1}');
      }
    });
    test('the bundled QUL V1 layout contains all 604 pages and ayah ends',
        () async {
      final raw = await rootBundle
          .loadString('assets/quran/mushaf_v1_1405h_layout.json');
      final pages = (jsonDecode(raw) as Map<String, dynamic>)['pages'] as List;
      expect(pages.length, 604);
      var ayahEnds = 0;
      for (var index = 0; index < pages.length; index++) {
        final page = pages[index] as Map<String, dynamic>;
        expect(page['p'], index + 1);
        final lines = page['l'] as List;
        expect(lines, isNotEmpty, reason: 'page ${index + 1}');
        expect(lines.length, lessThanOrEqualTo(15),
            reason: 'page ${index + 1}');
        for (final line in lines.cast<Map<String, dynamic>>()) {
          for (final word in (line['w'] as List? ?? const [])) {
            final values = word as List;
            if (values.length > 2 && values[2] == 1) ayahEnds++;
          }
        }
      }
      expect(ayahEnds, 6236);
    });
    test('the QUL surah-name ligature font is bundled', () async {
      final font = await rootBundle.load('assets/fonts/qul_surah_name_v4.ttf');
      expect(font.lengthInBytes, greaterThan(10000));
      final basmala = await rootBundle.load('assets/fonts/qul_bismillah.ttf');
      expect(basmala.lengthInBytes, greaterThan(3000));
    });
    test('an unknown edition id falls back to Hafs', () {
      MushafSvgService.setEdition('nope');
      expect(MushafSvgService.edition.id, 'hafs');
    });
  });
}

// Regression: the KFGQPC HAFS font has no mark support for U+06DF,
// U+06E3 and U+06EB — each renders as a bold ring on a dotted circle.
// The service re-encodes them at load (U+06DF becomes the sukun this
// font draws as the silent-letter circle; the other two are dropped).
void checkFontSafe() {
  group('Quran font re-encoding', () {
    test('no displayed ayah carries a mark the font cannot shape', () async {
      for (var p = 1; p <= 604; p++) {
        for (final a in await QuranService.ayahsOnPage(p)) {
          for (final bad in ['۟', 'ۣ', '۫']) {
            expect(a.text, isNot(contains(bad)),
                reason: 'page $p ${a.surahNumber}:${a.numberInSurah}');
          }
        }
      }
    });

    test('the silent-letter circle became a sukun, not a deletion', () async {
      // كفروا in 3:4 must still carry a mark on its silent alef.
      final page = await QuranService.ayahsOnPage(50);
      final a4 =
          page.firstWhere((a) => a.surahNumber == 3 && a.numberInSurah == 4);
      expect(a4.text, contains('كَفَرُواْ'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/models/surah.dart';
import 'package:quran_app_v1/services/quran_service.dart';

/// Search used to match bare substrings, which put ayahs and surahs in
/// front of the reader that had nothing to do with what they typed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ayah search finds the WORD, not its letters', () {
    test('"من" no longer returns ٱلرَّحْمَٰنِ ٱلرَّحِيمِ', () async {
      final results = await QuranService.searchAyahs('من');
      // Al-Fatiha 3 is the whole of "ٱلرَّحْمَٰنِ ٱلرَّحِيمِ" and carries
      // no word مِن — it only ever matched inside ٱلرَّحْمَٰن.
      final fatiha3 = results.where(
          (r) => r.surahNumber == 1 && r.numberInSurah == 3);
      expect(fatiha3, isEmpty);
    });

    test('"من" still returns ayahs that do carry the word', () async {
      final results = await QuranService.searchAyahs('من');
      expect(results, isNotEmpty);
      // Al-Baqarah 8: وَمِنَ ٱلنَّاسِ مَن يَقُولُ
      expect(
          results.any((r) => r.surahNumber == 2 && r.numberInSurah == 8),
          isTrue);
    });

    test('an exact phrase is ranked first', () async {
      final results = await QuranService.searchAyahs('قل هو الله احد');
      expect(results, isNotEmpty);
      expect(results.first.surahNumber, 112);
    });

    test('a single word is ranked by whole-word match first', () async {
      final results = await QuranService.searchAyahs('الحمد');
      expect(results.first.surahNumber, 1);
      expect(results.first.numberInSurah, 2);
    });

    test('the definite article is optional on a prefix match', () async {
      // رحم must still reach ٱلرَّحْمَٰن, whose leading ال would
      // otherwise block it.
      final results = await QuranService.searchAyahs('رحم');
      expect(results.any((r) => r.surahNumber == 1 && r.numberInSurah == 3),
          isTrue);
    });

    test('a word in no ayah returns nothing rather than noise', () async {
      expect(await QuranService.searchAyahs('زقزقزق'), isEmpty);
    });
  });

  group('surah search', () {
    test('"ال" does not match surahs whose name lacks it', () async {
      final results = await QuranService.searchSurahs('ال');
      final names = results.map((s) => s.number).toSet();
      // يس (36), طه (20) and نوح (71) carry no definite article.
      expect(names.contains(36), isFalse);
      expect(names.contains(20), isFalse);
      expect(names.contains(71), isFalse);
      expect(results.length, lessThan(114));
    });

    test('a bare name finds its surah without the article', () async {
      final results = await QuranService.searchSurahs('بقرة');
      expect(results.map((s) => s.number), [2]);
    });

    test('transliteration still works', () async {
      final results = await QuranService.searchSurahs('fatiha');
      expect(results.map((s) => s.number), contains(1));
    });

    test('a number reaches its surah', () async {
      final results = await QuranService.searchSurahs('18');
      expect(results.map((s) => s.number), contains(18));
    });
  });

  group('SurahQuery guards degenerate input', () {
    Surah surah(int number, String name, String english) => Surah(
          number: number,
          name: name,
          englishName: english,
          englishNameTranslation: english,
          numberOfAyahs: 7,
          revelationType: 'Meccan',
        );

    test('stripping the article to nothing must not match everything', () {
      // "ال" reduces to a bare lam; removing the article leaves "".
      // contains('') is true of every string, which is how the home
      // screen's filter used to return the entire Mushaf.
      final q = SurahQuery('ال');
      expect(q.arabicNoAl, isEmpty);
      expect(q.matches(surah(36, 'سُورَةُ يسٓ', 'Ya-Sin')), isFalse);
    });

    test('a single Latin letter is not used for matching', () {
      expect(SurahQuery('a').latin, isEmpty);
      expect(SurahQuery('al').latin, isNotEmpty);
    });

    test('an empty query matches nothing at all', () {
      expect(SurahQuery('').isEmpty, isTrue);
      expect(SurahQuery('   ').isEmpty, isTrue);
    });
  });
}

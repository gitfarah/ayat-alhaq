// The index search has to survive the gap between how a reader types a
// word and how the Mushaf spells it: ٱلَّذِى typed as "الذي", البقرة
// typed as "البقره".
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/quran_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Surah name search', () {
    test('finds a surah spelled with ta marbuta typed as ha', () async {
      for (final q in ['البقرة', 'البقره', 'بقره', 'baqara']) {
        final hits = await QuranService.searchSurahs(q);
        expect(hits.map((s) => s.number), contains(2), reason: q);
      }
    });

    test('a hamza-carrying name stays specific', () async {
      final hits = await QuranService.searchSurahs('النساء');
      expect(hits.map((s) => s.number), contains(4));
      // Not every name that merely shares the letters ن س.
      expect(hits.map((s) => s.number), isNot(contains(10)));
    });

    test('finds Al-Fatiha several ways', () async {
      for (final q in ['الفاتحة', 'الفاتحه', 'فاتحه', 'Fatihah']) {
        final hits = await QuranService.searchSurahs(q);
        expect(hits.map((s) => s.number), contains(1), reason: q);
      }
    });
  });

  group('Ayah search', () {
    test('alef maqsura in the text matches a typed ya', () async {
      final hits = await QuranService.searchAyahs('الذي');
      expect(hits, isNotEmpty);
    });

    test('finds a well-known phrase', () async {
      final hits = await QuranService.searchAyahs('الحمد لله رب العالمين');
      expect(hits.any((r) => r.surahNumber == 1 && r.numberInSurah == 2),
          isTrue);
    });

    test('words out of order still find the ayah', () async {
      // Not a contiguous phrase anywhere — only the all-words pass finds it.
      final hits = await QuranService.searchAyahs('العالمين الحمد');
      expect(hits.any((r) => r.surahNumber == 1 && r.numberInSurah == 2),
          isTrue);
    });

    test('a nonsense query finds nothing', () async {
      expect(await QuranService.searchAyahs('زقزقزق'), isEmpty);
    });
  });
}

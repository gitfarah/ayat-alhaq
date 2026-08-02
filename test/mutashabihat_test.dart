import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/mutashabihat_service.dart';
import 'package:quran_app_v1/services/quran_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('global ayah numbering', () {
    test('round-trips through the bundled text', () async {
      for (final pair in const [[1, 1], [2, 255], [18, 10], [114, 6]]) {
        final global =
            await QuranService.globalAyahNumber(pair[0], pair[1]);
        final back = await QuranService.locateGlobalAyah(global);
        expect(back, isNotNull);
        expect(back!.surahNumber, pair[0]);
        expect(back.numberInSurah, pair[1]);
      }
    });

    test('the numbering spans the whole Mushaf', () async {
      expect(await QuranService.globalAyahNumber(1, 1), 1);
      expect(await QuranService.globalAyahNumber(2, 1), 8);
      expect(await QuranService.globalAyahNumber(114, 6), 6236);
    });

    test('out-of-range lookups are reported, not guessed', () async {
      expect(await QuranService.globalAyahNumber(1, 8), 0);
      expect(await QuranService.globalAyahNumber(115, 1), 0);
      expect(await QuranService.globalAyahNumber(2, 0), 0);
      expect(await QuranService.locateGlobalAyah(6237), isNull);
      expect(await QuranService.locateGlobalAyah(0), isNull);
    });

    test('resolved ayahs carry their surah name and text', () async {
      final hit = await QuranService.locateGlobalAyah(
          await QuranService.globalAyahNumber(2, 255));
      expect(hit!.surahName, contains('بَقَرَة'));
      expect(hit.text, isNotEmpty);
    });
  });

  group('MutashabihatService', () {
    test('finds the mutashabihat of a known source ayah', () async {
      // The dataset's very first entry: global 9 (2:2) against three
      // matches elsewhere in the Quran.
      final entries = await MutashabihatService.forGlobalAyah(9);
      expect(entries, isNotEmpty);
      final all = {for (final e in entries) ...e.similar.expand((r) => r)};
      expect(all, containsAll([1162, 3161, 3472]));
    });

    test('the index is symmetric — a match finds its source back',
        () async {
      final fromSource = await MutashabihatService.forGlobalAyah(9);
      expect(fromSource.first.similar.expand((r) => r), contains(1162));

      // Sitting on the match must surface the source, which the raw
      // one-way dataset would not do on its own.
      final fromMatch = await MutashabihatService.forGlobalAyah(1162);
      final back = {for (final e in fromMatch) ...e.similar.expand((r) => r)};
      expect(back, contains(9));
    });

    test('an entry never lists the ayah being read as its own match',
        () async {
      for (final global in const [9, 1162, 3161, 61, 128]) {
        for (final e in await MutashabihatService.forGlobalAyah(global)) {
          expect(e.current, contains(global));
          expect(e.similar.expand((r) => r), isNot(contains(global)));
        }
      }
    });

    test('every ayah of a multi-ayah run is an entry point', () async {
      // Juz 1 holds a two-ayah run 53-54 matched against 128-129.
      final fromFirst = await MutashabihatService.forGlobalAyah(53);
      final fromSecond = await MutashabihatService.forGlobalAyah(54);
      expect(fromFirst, isNotEmpty);
      expect(fromSecond, isNotEmpty,
          reason: 'the second ayah of the run must find the pair too');
      expect(fromSecond.first.current, containsAll([53, 54]));
    });

    test('ayahs with no recorded mutashabiha come back empty, not null',
        () async {
      expect(await MutashabihatService.forGlobalAyah(1), isEmpty);
      expect(await MutashabihatService.forGlobalAyah(999999), isEmpty);
    });

    test('every referenced ayah number is a real ayah', () async {
      // A stale or mis-indexed dataset would silently render blank
      // cards, so check the whole thing resolves.
      var checked = 0;
      for (var g = 1; g <= 6236; g++) {
        for (final e in await MutashabihatService.forGlobalAyah(g)) {
          for (final run in [e.current, ...e.similar]) {
            for (final ayah in run) {
              expect(ayah, inInclusiveRange(1, 6236));
              checked++;
            }
          }
        }
      }
      expect(checked, greaterThan(1000));
    });
  });
}

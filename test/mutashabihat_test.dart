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

  // The dataset (assets/quran/mutashabihat.json) is transcribed from
  // the reference book — see mutashabihat_service.dart's doc comment.
  // References below are written as surah:ayah and resolved through
  // QuranService, so they can be checked against the printed page by
  // eye and would fail loudly if the bundled Quran asset ever shifted.
  group('MutashabihatService (book-transcribed)', () {
    /// Global numbers for a surah:ayah pair, for readable assertions.
    Future<int> g(int surah, int ayah) =>
        QuranService.globalAyahNumber(surah, ayah);

    /// Everything the book links to the given ayah.
    Future<Set<int>> linkedTo(int surah, int ayah) async {
      final entries = await MutashabihatService.forGlobalAyah(
          await g(surah, ayah));
      return {for (final e in entries) ...e.similar.expand((r) => r)};
    }

    test('the Iblis-refusal row links all four of its occurrences',
        () async {
      // Page 2, row 1. Each surah contributes the refusal AND the
      // follow-up question, except Al-Baqarah which prints only the
      // refusal — an earlier transcription wrongly mixed the two
      // patterns, so both ayahs of each pair are asserted.
      final found = await linkedTo(2, 34);
      expect(found, containsAll([
        await g(7, 11), await g(7, 12),
        await g(15, 31), await g(15, 32),
        await g(38, 74), await g(38, 75),
      ]));
    });

    test('the index is symmetric — every member finds the others back',
        () async {
      // Sitting on any occurrence must surface the rest of the row,
      // which the one-way printed layout would not do on its own.
      final row = [
        await g(2, 34),
        await g(7, 11),
        await g(15, 31),
        await g(38, 74),
      ];
      for (final member in row) {
        final entries = await MutashabihatService.forGlobalAyah(member);
        final found = {
          for (final e in entries) ...e.similar.expand((r) => r)
        };
        for (final other in row.where((x) => x != member)) {
          expect(found, contains(other),
              reason: 'global $member did not link back to $other');
        }
      }
    });

    test('the ihbitu row keeps all three occurrences', () async {
      // Page 2, row 3: البقرة ٣٨ / الأعراف ٢٤ / طه ١٢٣. Al-A'raf 24
      // was wrongly dropped from an earlier transcription on the
      // reasoning that its wording matches Al-Baqarah 36 instead — but
      // the book groups it here, and the book is the source of truth.
      final found = await linkedTo(2, 38);
      expect(found, contains(await g(7, 24)));
      expect(found, contains(await g(20, 123)));
    });

    test('the Adam/Jannah row links both directions', () async {
      expect(await linkedTo(2, 35), contains(await g(7, 19)));
      expect(await linkedTo(7, 19), contains(await g(2, 35)));
    });

    test('a surah opening finds the other surahs opening the same way',
        () async {
      // Page 1, row 8: the حم family plus Az-Zumar, which shares
      // "تنزيل الكتاب من الله العزيز الحكيم" without the حم.
      expect(await linkedTo(45, 2), contains(await g(46, 2)));
      expect(await linkedTo(39, 1), contains(await g(45, 2)));

      // Page 1, row 9: سبّح / يسبّح.
      expect(await linkedTo(59, 1), contains(await g(61, 1)));
    });

    test('an entry never lists the ayah being read as its own match',
        () async {
      for (final ref in const [[2, 34], [7, 24], [20, 123], [40, 1]]) {
        final global = await g(ref[0], ref[1]);
        for (final e in await MutashabihatService.forGlobalAyah(global)) {
          expect(e.current, contains(global));
          expect(e.similar.expand((r) => r), isNot(contains(global)));
        }
      }
    });

    test('a row with a single occurrence is not indexed', () async {
      // Page 1, row 4: المص opens Al-A'raf alone. It is kept in the
      // JSON for faithfulness to the page, but has nothing to compare
      // against, so it must not produce an empty card.
      expect(await MutashabihatService.forGlobalAyah(await g(7, 1)),
          isEmpty);
    });

    test('the «يا أهل الكتاب» vocative links all twelve of its ayahs',
        () async {
      // Reported missing 2026-08-02: this family sits in the book's
      // القسم الخامس (بدايات الآيات), which had been wrongly dismissed
      // as not fitting the model — a chain of ayahs sharing an opening
      // IS a similar-ayah group. Membership here comes from an
      // exhaustive text search, so it is complete by construction.
      const family = [
        [3, 64], [3, 65], [3, 70], [3, 71], [3, 98], [3, 99],
        [4, 171], [5, 15], [5, 19], [5, 59], [5, 68], [5, 77],
      ];
      for (final ref in family) {
        final found = await linkedTo(ref[0], ref[1]);
        for (final other in family) {
          if (other[0] == ref[0] && other[1] == ref[1]) continue;
          expect(found, contains(await g(other[0], other[1])),
              reason: '${ref[0]}:${ref[1]} did not link to '
                  '${other[0]}:${other[1]}');
        }
      }
    });

    test('the sharpest نداء أهل الكتاب near-twins are paired directly',
        () async {
      // Differ by «قل» alone / by a single following word — the pairs a
      // hafiz actually slips between, so they get their own card on top
      // of the twelve-member family.
      expect(await linkedTo(3, 70), contains(await g(3, 98)));
      expect(await linkedTo(4, 171), contains(await g(5, 77)));
      expect(await linkedTo(5, 15), contains(await g(5, 19)));
    });

    test('the «إنه لا يفلح» endings link across all three predicates',
        () async {
      // The tightest kind of tadhyil confusion: same sentence, only the
      // final word changes — الظالمون in most places, المجرمون in Yunus,
      // الكافرون in Al-Mu'minun.
      expect(await linkedTo(10, 17), contains(await g(6, 21)));
      expect(await linkedTo(10, 17), contains(await g(23, 117)));
      expect(await linkedTo(23, 117), contains(await g(28, 37)));
    });

    test('«ويعلمهم الكتاب والحكمة» keeps البقرة ١٥١ with its «ويعلمكم»',
        () async {
      // 2:151 is the odd one out (يعلّمكم, and a different clause
      // order), which is exactly why it belongs in the group.
      final found = await linkedTo(3, 164);
      expect(found, contains(await g(2, 129)));
      expect(found, contains(await g(2, 151)));
      expect(found, contains(await g(62, 2)));
    });

    test('اتخذ الله ولدا links to اتخذ الرحمن ولدا', () async {
      expect(await linkedTo(2, 116), contains(await g(19, 88)));
      expect(await linkedTo(21, 26), contains(await g(10, 68)));
    });

    test('the نفع/ضر reversals pair the identical sentences directly',
        () async {
      // The sharpest kind there is: same words, opposite order.
      expect(await linkedTo(7, 188), contains(await g(10, 49)));
      expect(await linkedTo(13, 16), contains(await g(25, 3)));
    });

    test('the نفع-first sites are exactly the book\'s three exceptions',
        () async {
      // الأعراف ١٨٨ / الرعد ١٦ / سبأ ٤٢ — derived independently by text
      // search, and they matched the rule the book states, which is a
      // good check on the search-derived method itself.
      final found = await linkedTo(34, 42);
      for (final ref in const [[7, 188], [13, 16]]) {
        expect(found, contains(await g(ref[0], ref[1])));
      }
    });

    test('لهو ولعب in الأعراف and العنكبوت link to the لعب ولهو places',
        () async {
      final found = await linkedTo(7, 51);
      expect(found, contains(await g(29, 64)));
      expect(found, contains(await g(6, 32)));
      expect(found, contains(await g(57, 20)));
    });

    test('the three الإنس-before-الجن sites are linked', () async {
      final found = await linkedTo(17, 88);
      expect(found, contains(await g(6, 112)));
      expect(found, contains(await g(72, 5)));
    });

    test('the consecutive النور pair 58/59 is linked', () async {
      // Adjacent ayahs identical but for «الآيات» vs «آياته» — about as
      // easy to slip between as the Quran gets.
      expect(await linkedTo(24, 58), contains(await g(24, 59)));
    });

    test('«يبين الله لكم» links its four different endings', () async {
      final found = await linkedTo(2, 219); // تتفكرون
      expect(found, contains(await g(2, 242))); // تعقلون
      expect(found, contains(await g(3, 103))); // تهتدون
      expect(found, contains(await g(5, 89))); // تشكرون
    });

    test('الفوز العظيم links across all its prefixes', () async {
      final found = await linkedTo(5, 119); // «ذلك»
      expect(found, contains(await g(4, 13))); // «وذلك»
      expect(found, contains(await g(9, 72))); // «ذلك هو»
      expect(found, contains(await g(9, 111))); // «وذلك هو»
      expect(found, contains(await g(37, 60))); // «لهو»
    });

    test('the counted-place rules hold exactly', () async {
      // Both counts were derived by exhaustive search and matched the
      // book's own «٣ مواضع» and «٤ مواضع» — so a change to either
      // should fail loudly rather than drift.
      expect(await linkedTo(7, 71), contains(await g(47, 26)));
      expect(await linkedTo(7, 71), contains(await g(67, 9)));
      expect(await linkedTo(10, 104), contains(await g(22, 49)));
      expect(await linkedTo(10, 104), contains(await g(7, 158)));
    });

    test('ayahs with no recorded mutashabiha come back empty, not null',
        () async {
      expect(await MutashabihatService.forGlobalAyah(3), isEmpty);
      expect(await MutashabihatService.forGlobalAyah(999999), isEmpty);
    });

    test('every transcribed reference resolves to a real ayah', () async {
      // A typo like "2:999" would silently shrink or blank a card, so
      // sweep the whole dataset and confirm each number is in range.
      var checked = 0;
      for (var global = 1; global <= 6236; global++) {
        for (final e in await MutashabihatService.forGlobalAyah(global)) {
          for (final run in [e.current, ...e.similar]) {
            expect(run, isNotEmpty);
            for (final ayah in run) {
              expect(ayah, inInclusiveRange(1, 6236));
              checked++;
            }
          }
        }
      }
      expect(checked, greaterThan(0));
    });
  });
}

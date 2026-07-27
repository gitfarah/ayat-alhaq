import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/models/quran_page_meta.dart';
import 'package:quran_app_v1/services/tajweed_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _combiningMarks();

  group('Tajweed data', () {
    setUpAll(() async => TajweedService.load());

    test('covers all 6236 ayahs', () {
      var missing = 0;
      for (var s = 1; s <= 114; s++) {
        for (var a = 1; a <= QuranPageMeta.ayahCounts[s - 1]; a++) {
          if (TajweedService.segments(s, a) == null) missing++;
        }
      }
      expect(missing, 0, reason: '$missing ayahs have no tajweed data');
    });

    test('every rule used in the data has a colour', () {
      final seen = <String>{};
      for (var s = 1; s <= 114; s++) {
        for (var a = 1; a <= QuranPageMeta.ayahCounts[s - 1]; a++) {
          for (final seg in TajweedService.segments(s, a)!) {
            if (!seg.isPlain) seen.add(seg.rule);
          }
        }
      }
      expect(seen, isNotEmpty);
      final uncoloured =
          seen.where((r) => TajweedService.colorFor(r) == null).toList();
      expect(uncoloured, isEmpty, reason: 'rules without a colour');
    });

    test('segments rejoin into the full ayah text', () {
      // Al-Ikhlas 1 — short, well-known, and carries several rules.
      final segs = TajweedService.segments(112, 1)!;
      final joined = segs.map((s) => s.text).join();
      expect(joined, contains('قُلْ'));
      expect(joined, contains('أَحَ'));
      // No stray markup should survive the offline conversion.
      expect(joined, isNot(contains('<')));
      expect(joined, isNot(contains('tajweed')));
      expect(segs.any((s) => !s.isPlain), isTrue);
    });

    test('ayah numbers are not embedded in the text', () {
      for (final key in [[1, 1], [2, 255], [114, 6]]) {
        final joined = TajweedService.segments(key[0], key[1])!
            .map((s) => s.text)
            .join();
        expect(joined, isNot(contains('span')));
      }
    });

    test('legend rules all exist in the colour map', () {
      for (final r in TajweedService.legendOrder) {
        expect(TajweedService.ruleColors[r], isNotNull, reason: r);
        expect(TajweedService.ruleNames['ar']![r], isNotNull, reason: r);
        expect(TajweedService.ruleNames['en']![r], isNotNull, reason: r);
        expect(TajweedService.ruleNames['de']![r], isNotNull, reason: r);
      }
    });
  });
}

// Regression: the source data can cut a rule between a letter and the
// mark that sits on it. Rendered as separate spans that mark has no base
// and the shaper draws it on a dotted circle, which showed up as stray
// blue dots inside words like ٱلصِّرَٰطَ.
void _combiningMarks() {
  group('Tajweed segment boundaries', () {
    setUpAll(() async => TajweedService.load());

    test('no segment starts with a combining mark', () async {
      var checked = 0;
      for (var s = 1; s <= 114; s++) {
        for (var a = 1; a <= 10; a++) {
          final segs = TajweedService.segments(s, a);
          if (segs == null) continue;
          checked++;
          for (var i = 1; i < segs.length; i++) {
            final first = segs[i].text.codeUnitAt(0);
            expect(TajweedService.isCombiningMark(first), isFalse,
                reason: 'surah $s ayah $a segment $i starts with U+'
                    '${first.toRadixString(16)}');
          }
        }
      }
      expect(checked, greaterThan(100), reason: 'no ayahs were checked');
    });

    test('segments still reconstruct the ayah text', () async {
      final segs = TajweedService.segments(1, 5)!;
      final joined = segs.map((s) => s.text).join();
      expect(joined, contains('نَعْبُدُ'));
    });

    test('no scraped markup survives into the text', () {
      for (var s = 1; s <= 114; s++) {
        for (var a = 1; a <= 12; a++) {
          final segs = TajweedService.segments(s, a);
          if (segs == null) continue;
          for (final seg in segs) {
            expect(seg.text, isNot(contains('tajweed')),
                reason: 'surah  ayah ');
            expect(seg.text, isNot(contains('<')), reason: 'surah  ayah ');
          }
        }
      }
    });

    test('uses the same codepoints as the bundled Uthmani text', () {
      // The scraped data spells these two letters differently, which
      // breaks how the word joins in the Mushaf font.
      for (var s = 1; s <= 114; s++) {
        for (var a = 1; a <= 12; a++) {
          final segs = TajweedService.segments(s, a);
          if (segs == null) continue;
          final joined = segs.map((x) => x.text).join();
          expect(joined, isNot(contains('ٲ')), reason: 'surah  ayah ');
          expect(joined, isNot(contains('ٮ')), reason: 'surah  ayah ');
          expect(joined, isNot(contains('‌')), reason: 'surah  ayah ');
        }
      }
    });
  });
}

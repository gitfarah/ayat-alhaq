// The source spells ٱلْءَاخِرَةُ with a standalone hamza, which cannot
// join, so the Mushaf font breaks the word open around it. It has to be
// re-encoded as a hamza riding a connecting stroke.
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/quran_service.dart';

bool isMark(int cp) =>
    (cp >= 0x0610 && cp <= 0x061A) ||
    (cp >= 0x064B && cp <= 0x065F) ||
    cp == 0x0670 ||
    (cp >= 0x06D6 && cp <= 0x06ED);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Medial hamza', () {
    test('a hamza after a joining letter gets a connecting stroke', () {
      expect(QuranService.fixForQuranFont('ٱلْءَاخِرَةُ'),
          contains('ـٔ'));
      expect(QuranService.fixForQuranFont('لِءَادَمَ'), contains('ـٔ'));
    });

    test('a word-initial hamza is left alone', () {
      expect(QuranService.fixForQuranFont('ءَامَنُوا'), startsWith('ء'));
    });

    test('a hamza after a non-joining letter is left alone', () {
      for (final w in ['سَوَآءٌ', 'ٱلسَّمَآءِ', 'أَضَآءَتْ']) {
        expect(QuranService.fixForQuranFont(w), isNot(contains('ـٔ')),
            reason: w);
      }
    });

    test('every page is free of word-breaking medial hamzas', () async {
      const nonJoining = 'اأإآٱدذرزوةى ';
      for (var p = 1; p <= 604; p++) {
        for (final a in await QuranService.ayahsOnPage(p)) {
          final t = a.text;
          for (var i = 1; i < t.length; i++) {
            if (t[i] != 'ء') continue;
            var j = i - 1;
            while (j >= 0 && isMark(t.codeUnitAt(j))) {
              j--;
            }
            if (j < 0) continue;
            expect(nonJoining.contains(t[j]), isTrue,
                reason: 'page $p ${a.surahNumber}:${a.numberInSurah} '
                    'has a hamza joined onto ${t[j]}');
          }
        }
      }
    });
  });
}

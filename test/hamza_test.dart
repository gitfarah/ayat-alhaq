// Word-internal hamza must reach the screen exactly as the source
// spells it. fixForQuranFont may re-encode MARKS; it must never rewrite
// a letter.
//
// This file used to assert the OPPOSITE: that a medial standalone hamza
// (U+0621) was re-encoded as tatweel + U+0654, to close the gap the
// reader's font leaves around a letter that cannot join.
//
// That was reported as a misreading and removed. In the bundled KFGQPC
// HAFS v0.18 face, لْ followed by a hamza-topped connector renders as a
// shape indistinguishable from كـ, so وَبِٱلْءَاخِرَةِ (2:4) reached
// readers as وَبِٱلْكَاخِرَة — a different word, in the Quran's own text.
//
// Note the source is deliberately NOT uniform, which is exactly why it
// must be left alone: it writes أَنبِـُٔونِى (2:31) and ٱلْـَٰٔنَ (2:71)
// with a connector, and ٱلْءَاخِرَةِ with a standalone hamza. Only the
// last was being rewritten. Whole-Quran "this sequence never appears"
// scans are therefore the wrong shape of test — they fail on the
// source's own spellings — so these pin the transform itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/quran_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fixForQuranFont never rewrites a letter', () {
    test('a medial standalone hamza is left standalone', () {
      // The regression: these are the words that were being converted.
      for (final word in ['ٱلْءَاخِرَةُ', 'لِءَادَمَ', 'وَبِٱلْءَاخِرَةِ']) {
        final out = QuranService.fixForQuranFont(word);
        expect(out, word, reason: '$word must pass through unchanged');
        expect(out, contains('ء'), reason: 'the hamza itself survives');
        expect(out, isNot(contains('ـٔ')),
            reason: 'no tatweel+hamza connector may be invented — that is '
                'the pair that rendered as a kaf');
      }
    });

    test("the source's OWN connectors survive untouched", () {
      // Correct after ب and after لْ respectively in the source's own
      // orthography. Removing the rewrite must not swap which spelling
      // gets mangled.
      for (final word in ['أَنبِـُٔونِى', 'ٱلْـَٰٔنَ']) {
        expect(QuranService.fixForQuranFont(word), word, reason: word);
      }
    });

    test('a word-initial hamza is untouched, as it always was', () {
      expect(QuranService.fixForQuranFont('ءَامَنُوا'), startsWith('ء'));
    });
  });

  group('mark re-encoding still applies', () {
    test('the marks the font cannot shape are still handled', () {
      // Removing the letter rewrite must not have taken the mark fixes
      // with it: U+06DF becomes a plain sukun, U+06ED/U+06E2 are dropped.
      expect(QuranService.fixForQuranFont('كَفَرُوا۟'), 'كَفَرُواْ');
      expect(QuranService.fixForQuranFont('هُدًۭى'), 'هُدًى');
    });
  });

  group('as the reader actually receives it', () {
    test('2:4 keeps ٱلْءَاخِرَةِ — the exact ayah that was reported',
        () async {
      final page = await QuranService.ayahsOnPage(2);
      final a4 =
          page.firstWhere((a) => a.surahNumber == 2 && a.numberInSurah == 4);
      expect(a4.text, contains('ٱلْءَاخِرَةِ'));
      // Neither the kaf-shaped connector nor the modern imla'i آ
      // (U+0622), which would be an equally wrong way to close the gap.
      expect(a4.text, isNot(contains('ٱلْـٔ')));
      expect(a4.text, isNot(contains('ٱلْآ')));
    });
  });
}

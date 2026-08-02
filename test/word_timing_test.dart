import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/word_timing.dart';

void main() {
  const fatiha2 = 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ';

  group('wordRanges', () {
    test('splits on whitespace and points back at the original text', () {
      final ranges = WordTiming.wordRanges(fatiha2);
      expect(ranges.length, 4);
      expect(
        [for (final (s, e) in ranges) fatiha2.substring(s, e)],
        fatiha2.split(' '),
      );
    });

    test('ignores leading, trailing and repeated spaces', () {
      expect(WordTiming.wordRanges('  a   b  '), [(2, 3), (6, 7)]);
      expect(WordTiming.wordRanges('   '), isEmpty);
    });
  });

  group('forAyah', () {
    final timings =
        WordTiming.forAyah(fatiha2, const Duration(milliseconds: 6000));

    test('covers every word, in order, without gaps', () {
      expect(timings.length, 4);
      for (var i = 0; i < timings.length; i++) {
        expect(timings[i].from, lessThan(timings[i].to));
        if (i > 0) expect(timings[i].from, timings[i - 1].to);
      }
    });

    test('starts after a lead-in and runs to the end of the clip', () {
      expect(timings.first.from, greaterThan(Duration.zero));
      expect(timings.last.to, const Duration(milliseconds: 6000));
    });

    test('gives a longer word more time than a shorter one', () {
      Duration span(WordSpanTiming t) => t.to - t.from;
      // رَبِّ is the shortest word here; ٱلْعَٰلَمِينَ the longest.
      expect(span(timings[2]), lessThan(span(timings[1])));
      expect(span(timings[2]), lessThan(span(timings[3])));
    });

    test('is empty when there is no duration or no text', () {
      expect(WordTiming.forAyah(fatiha2, Duration.zero), isEmpty);
      expect(WordTiming.forAyah('', const Duration(seconds: 5)), isEmpty);
    });
  });

  group('indexAt', () {
    final timings =
        WordTiming.forAyah(fatiha2, const Duration(milliseconds: 6000));

    test('reports no word before the first one starts', () {
      expect(WordTiming.indexAt(timings, Duration.zero), -1);
    });

    test('finds the word covering a position', () {
      for (var i = 0; i < timings.length; i++) {
        final mid = timings[i].from +
            Duration(microseconds: (timings[i].to - timings[i].from).inMicroseconds ~/ 2);
        expect(WordTiming.indexAt(timings, mid), i);
      }
    });

    test('a stale hint does not break the answer', () {
      final mid = timings[1].from + const Duration(milliseconds: 10);
      expect(WordTiming.indexAt(timings, mid, 3), 1);
      expect(WordTiming.indexAt(timings, mid, 0), 1);
    });

    test('holds the last word past the end of the clip', () {
      expect(WordTiming.indexAt(timings, const Duration(seconds: 30)),
          timings.length - 1);
    });

    test('handles an empty timing list', () {
      expect(WordTiming.indexAt(const [], const Duration(seconds: 1)), -1);
    });
  });
}

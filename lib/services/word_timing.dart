/// Estimated per-word timing for a recited ayah, used to light up the
/// word being pronounced while the reciter reads.
///
/// The per-ayah audio this app plays (islamic.network / everyayah) ships
/// no word-level timestamps, and none of the eleven reciters offered
/// here has a published word-timing dataset. So the timing is DERIVED
/// from the text itself: every word is given a phonetic weight — roughly
/// how long it takes to pronounce — and the clip's real duration is
/// split between the words in proportion to those weights.
///
/// That is an approximation, not ground truth. It tracks a measured
/// recitation closely enough to read along with, because Quranic
/// recitation is metrical: madd letters are held, shadda doubles a
/// consonant, sukun clips one. Those are exactly the features weighted
/// below.
library;

/// One word of an ayah, with where it sits in the ayah string and when
/// it is expected to be pronounced.
class WordSpanTiming {
  /// Character range of the word inside the ayah text: [start, end).
  final int start;
  final int end;

  /// When this word starts and ends, relative to the clip's beginning.
  final Duration from;
  final Duration to;

  const WordSpanTiming({
    required this.start,
    required this.end,
    required this.from,
    required this.to,
  });

  bool contains(Duration t) => t >= from && t < to;
}

class WordTiming {
  /// Recitations open with a breath and close on a held final syllable
  /// that the weights below can't see. A slice of the clip is set aside
  /// at each end so the highlight doesn't run ahead of the voice.
  static const double _leadInFraction = 0.04;
  static const double _tailFraction = 0.07;

  /// A combining mark carries no syllable of its own, but several of
  /// them change how long the letter under them is held.
  static bool _isMark(int cp) =>
      (cp >= 0x064B && cp <= 0x065F) ||
      cp == 0x0670 ||
      (cp >= 0x06D6 && cp <= 0x06ED);

  /// Roughly how long one character is held, in arbitrary units that
  /// only matter relative to each other.
  static double _weightOf(int cp) {
    switch (cp) {
      case 0x0651: // shadda — the consonant is doubled
        return 0.9;
      case 0x0652: // sukun — no vowel, the letter is clipped
        return -0.25;
      case 0x0653: // maddah — a long hold
        return 1.6;
      case 0x0670: // superscript alef — a full long vowel
        return 0.8;
      case 0x064B: // tanween: an extra -n
      case 0x064C:
      case 0x064D:
        return 0.5;
    }
    // Small high signs (waqf marks, the small madd letters) add a
    // little length; ordinary short vowels add almost none.
    if (cp >= 0x06D6 && cp <= 0x06ED) return 0.35;
    if (_isMark(cp)) return 0.15;

    switch (cp) {
      case 0x0627: // alef
      case 0x0648: // waw
      case 0x064A: // yeh
      case 0x0649: // alef maqsura
        return 1.8; // long vowels — the letters that get held
      case 0x0622: // alef madda
        return 2.2;
    }
    return 1.0; // an ordinary consonant
  }

  /// Splits [text] into words with their character ranges, ignoring
  /// runs of whitespace.
  static List<(int start, int end)> wordRanges(String text) {
    final out = <(int, int)>[];
    var i = 0;
    while (i < text.length) {
      while (i < text.length && _isSpace(text.codeUnitAt(i))) {
        i++;
      }
      final start = i;
      while (i < text.length && !_isSpace(text.codeUnitAt(i))) {
        i++;
      }
      if (i > start) out.add((start, i));
    }
    return out;
  }

  static bool _isSpace(int cp) =>
      cp == 0x20 || cp == 0x09 || cp == 0x0A || cp == 0x0D || cp == 0x00A0;

  /// Timings for every word of [text] spread across a clip of
  /// [duration]. Returns an empty list when there is nothing to time.
  static List<WordSpanTiming> forAyah(String text, Duration duration) {
    final ranges = wordRanges(text);
    if (ranges.isEmpty || duration <= Duration.zero) return const [];

    final weights = <double>[];
    var total = 0.0;
    for (final (start, end) in ranges) {
      var w = 0.0;
      for (var i = start; i < end; i++) {
        w += _weightOf(text.codeUnitAt(i));
      }
      // Even a one-letter word takes time to say.
      w = w < 0.8 ? 0.8 : w;
      weights.add(w);
      total += w;
    }
    if (total <= 0) return const [];

    final micros = duration.inMicroseconds;
    final lead = (micros * _leadInFraction).round();
    final body = micros - lead - (micros * _tailFraction).round();
    if (body <= 0) return const [];

    final out = <WordSpanTiming>[];
    var acc = 0.0;
    for (var i = 0; i < ranges.length; i++) {
      final from = lead + (body * (acc / total)).round();
      acc += weights[i];
      // The last word runs to the very end of the clip — that is where
      // the reserved tail goes, since a closing syllable is held.
      final to = i == ranges.length - 1
          ? micros
          : lead + (body * (acc / total)).round();
      out.add(WordSpanTiming(
        start: ranges[i].$1,
        end: ranges[i].$2,
        from: Duration(microseconds: from),
        to: Duration(microseconds: to),
      ));
    }
    return out;
  }

  /// Index of the word being pronounced at [position], or -1 before the
  /// first word starts. Timings must be in order (as [forAyah] returns
  /// them); the search is linear from a caller-supplied hint so that
  /// following playback costs nothing per frame.
  static int indexAt(List<WordSpanTiming> timings, Duration position,
      [int hint = 0]) {
    if (timings.isEmpty) return -1;
    if (position < timings.first.from) return -1;
    var i = hint.clamp(0, timings.length - 1);
    if (position < timings[i].from) i = 0;
    while (i < timings.length - 1 && position >= timings[i].to) {
      i++;
    }
    return i;
  }
}

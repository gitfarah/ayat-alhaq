import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../models/surah.dart';

/// Provides Quran text data (surah list, ayah text + page/juz/hizb
/// metadata) from the BUNDLED asset `assets/quran/quran_ar.json`
/// (ar.alafasy edition) — the entire Quran works offline from the
/// moment the app is installed. The network is only used for optional
/// per-ayah translations, which are not part of the bundle.
class QuranService {
  static const String _baseUrl = 'https://api.alquran.cloud/v1';

  static List<Surah>? _surahCache;

  /// Raw per-surah ayah tuples straight from the asset:
  /// [globalNumber, numberInSurah, juz, page, hizbQuarter, text]
  static List<List<dynamic>>? _rawAyahs;

  /// Normalized (bare-letter) ayah texts for offline search, built
  /// lazily on the first search: one entry per surah, parallel to
  /// [_rawAyahs].
  static List<List<String>>? _searchIndex;

  static Future<void> _ensureLoaded() async {
    if (_surahCache != null) return;
    final raw = await rootBundle.loadString('assets/quran/quran_ar.json');
    final List list = jsonDecode(raw);
    _surahCache = [
      for (final s in list)
        Surah(
          number: s['number'],
          name: s['name'],
          englishName: s['englishName'],
          englishNameTranslation: s['englishNameTranslation'],
          numberOfAyahs: (s['ayahs'] as List).length,
          revelationType: s['revelationType'],
        ),
    ];
    _rawAyahs = [
      for (final s in list) (s['ayahs'] as List).cast<List<dynamic>>(),
    ];
    // Adapt the text to the KFGQPC HAFS font's own encoding — see
    // [fixForQuranFont].
    for (final surah in _rawAyahs!) {
      for (final t in surah) {
        t[5] = fixForQuranFont(t[5] as String);
      }
    }
  }

  /// Re-encodes marks the KFGQPC HAFS font cannot shape.
  ///
  /// NOTE: every finding below was measured against the font that used
  /// to be bundled, KFGQPC HAFS **v0.18** — an early beta. The app now
  /// ships **v2.2**, the King Fahd Complex's released version, which
  /// carries ~52% more mark-positioning (GPOS) data. These replacements
  /// are therefore very likely no longer needed, and each one DELETES a
  /// mark from the Quran's text, so they are worth re-testing on a
  /// device and removing one at a time. They are kept for now only
  /// because the font swap was made to fix the medial hamza and
  /// changing both at once would make a regression impossible to
  /// attribute.
  ///
  /// Originally verified by rendering each mark used in the whole text:
  ///
  ///  * U+06DF, U+06E3, U+06EB have no mark support at all — each draws
  ///    as a bold ring on a dotted circle instead of combining. The
  ///    KFGQPC's own text writes the silent-letter circle (U+06DF, as
  ///    in كَفَرُوا۟) as a plain sukun, which this font draws AS that
  ///    circle; the other two appear in three words in the whole Quran.
  ///
  ///  * U+06ED (small low meem, ikhfa) and U+06E2 (small high meem,
  ///    iqlab) carry no positioning against a tanween, so they land on
  ///    top of it and the pair renders as one smudged blob — the "م
  ///    mixed into the letter" in هُدًۭى and عَذَابٌۭ شَدِيدٌۭ. The
  ///    font has none of the stacked-tanween codepoints (U+08F0-08F2)
  ///    that would carry the same rule, so the marks are dropped; the
  ///    tajweed colouring conveys ikhfa and iqlab instead.
  ///
  /// Marks only. The letters are NEVER rewritten: see the medial-hamza
  /// note below for why.
  static String fixForQuranFont(String s) => s
      .replaceAll('۟', 'ْ')
      .replaceAll('ۣ', '')
      .replaceAll('۫', '')
      .replaceAll('ۭ', '')
      .replaceAll('ۢ', '');

  // WORD-INTERNAL HAMZA — left exactly as the source spells it, and it
  // must stay that way. Two rewrites were tried here and both were
  // wrong; the fix was the FONT, not the text.
  //
  // The source writes ٱلْءَاخِرَةِ and لِءَادَمَ with a standalone hamza
  // (U+0621), which cannot join. Under the old KFGQPC v0.18 face that
  // broke the word in two, so this code re-encoded the hamza onto a
  // connector (tatweel + U+0654). That rendered as a shape
  // indistinguishable from كـ — وَبِٱلْءَاخِرَةِ reached readers as
  // وَبِٱلْكَاخِرَة, a different word in the Quran's own text. Reverting
  // to the canonical spelling fixed the wrong letter but left the gap.
  //
  // Both symptoms were the beta font, so the fix is the font: the app
  // now bundles KFGQPC HAFS v2.2 (see pubspec.yaml) and this function
  // leaves the letters completely alone.
  //
  // Do not reintroduce the connector, and do not "fix" anything here by
  // substituting U+0622 (آ) either — ٱلْآخِرَة is the modern imla'i
  // spelling, not the Uthmani one this app sets. If the word ever looks
  // wrong again, the answer is in the font, not in this text.

  static Future<List<Surah>> getAllSurahs({bool forceRefresh = false}) async {
    await _ensureLoaded();
    return _surahCache!;
  }

  /// The Basmala exactly as the ar.alafasy edition writes it, for
  /// display as a standalone header line in the reader.
  static const String basmala = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ';

  /// Translation editions offered in the reader, keyed by the
  /// alquran.cloud edition identifier. Label = the language's own name.
  static const Map<String, String> translationEditions = {
    'en.sahih': 'English',
    'de.aburida': 'Deutsch',
    'fr.hamidullah': 'Français',
    'tr.diyanet': 'Türkçe',
    'id.indonesian': 'Bahasa Indonesia',
    'ur.jalandhry': 'اردو',
    'es.cortes': 'Español',
    'ru.kuliev': 'Русский',
  };

  /// Right-to-left translation languages (script direction, not edition
  /// specific) — the reader aligns these like the Arabic text.
  static bool isRtlEdition(String edition) =>
      edition.startsWith('ur.') || edition.startsWith('fa.');

  static Ayah _ayahFromTuple(List<dynamic> t, {String? translation}) {
    final int hizbQuarter = t[4];
    return Ayah(
      number: t[0],
      text: t[5],
      numberInSurah: t[1],
      juz: t[2],
      page: t[3],
      hizb: ((hizbQuarter - 1) ~/ 4) + 1,
      rub: hizbQuarter,
      translation: translation,
    );
  }

  /// Returns the surah's ayahs from the bundled asset — always
  /// available offline.
  ///
  /// The asset merges the Basmala into the first ayah's text of every
  /// surah (as the source edition does). Per Mushaf convention it
  /// belongs on its own line, so it is stripped here — except for
  /// Al-Fatiha (1), where the Basmala IS ayah 1, and At-Tawbah (9),
  /// which has no Basmala at all.
  ///
  /// When [translationEdition] is set, the translation alone is fetched
  /// from the network and merged in. If that fetch fails (offline), the
  /// Arabic text is returned WITHOUT translation instead of failing —
  /// reading always works.
  static Future<List<Ayah>> getSurahAyahs(int surahNumber,
      {String? translationEdition}) async {
    await _ensureLoaded();
    final tuples = _rawAyahs![surahNumber - 1];

    List? translated;
    if (translationEdition != null) {
      try {
        final response = await http
            .get(Uri.parse('$_baseUrl/surah/$surahNumber/$translationEdition'))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          translated = jsonDecode(response.body)['data']['ayahs'];
        }
      } catch (_) {
        // Offline or API down — show Arabic only.
      }
    }

    final list = [
      for (var i = 0; i < tuples.length; i++)
        _ayahFromTuple(
          tuples[i],
          translation: (translated != null && i < translated.length)
              ? translated[i]['text'] as String?
              : null,
        ),
    ];
    if (surahNumber != 1 && surahNumber != 9 && list.isNotEmpty) {
      final first = list.first;
      final stripped = _stripBasmala(first.text);
      if (stripped != first.text) {
        list[0] = Ayah(
          number: first.number,
          text: stripped,
          numberInSurah: first.numberInSurah,
          juz: first.juz,
          page: first.page,
          hizb: first.hizb,
          rub: first.rub,
          translation: first.translation,
        );
      }
    }
    return list;
  }

  /// Removes a leading Basmala (first four words) from [text] if
  /// present. Matching is done on bare letters — diacritics, the
  /// superscript alef, and alef variants are normalized away — so it
  /// keeps working even if the edition's exact vocalization changes.
  static String _stripBasmala(String text) {
    final clean = text.replaceFirst('﻿', '').trimLeft();
    final words = clean.split(' ');
    // A first ayah that is ONLY the Basmala (e.g. Al-Fatiha) is never
    // stripped — callers exclude surah 1, but stay safe regardless.
    if (words.length <= 4) return text;
    const target = ['بسم', 'الله', 'الرحمن', 'الرحيم'];
    for (var i = 0; i < 4; i++) {
      if (_bareLetters(words[i]) != _bareLetters(target[i])) return text;
    }
    return words.sublist(4).join(' ');
  }

  /// Folds a word to the bare letter skeleton used for searching.
  ///
  /// Beyond dropping the vowel marks, letters that a reader types one
  /// way and the Mushaf spells another are folded together — otherwise
  /// searching ٱلَّذِى for "الذي", or البقرة for "البقره", finds
  /// nothing at all, which is what made the search feel broken.
  static String _bareLetters(String word) {
    final b = StringBuffer();
    for (final r in word.runes) {
      final isMark = (r >= 0x0610 && r <= 0x061A) ||
          (r >= 0x064B && r <= 0x065F) ||
          r == 0x0670 ||
          (r >= 0x06D6 && r <= 0x06ED) ||
          r == 0x0640; // tatweel
      if (isMark) continue;
      switch (r) {
        // Every alef is dropped, not folded to one letter. The Mushaf
        // writes the long a as a superscript alef where a reader types
        // a full one (ٱلْعَٰلَمِينَ against العالمين) and omits one
        // where a reader types none (ٱلرَّحْمَٰنِ against الرحمن), so
        // no single spelling of it can match both — removing it does.
        case 0x0627: // ا
        case 0x0671: // ٱ wasla
        case 0x0622: // آ
        case 0x0623: // أ
        case 0x0625: // إ
        case 0x0670: // superscript (dagger) alef
          break;
        case 0x0649: // ى alef maqsura -> ya
        case 0x0626: // ئ
          b.write('ي');
        case 0x0624: // ؤ
          b.write('و');
        case 0x0629: // ة ta marbuta -> ha
          b.write('ه');
        default:
          b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// A single ayah's text from the bundled asset — offline, no network.
  /// Same Mushaf convention as [getSurahAyahs]: the merged Basmala is
  /// stripped from each surah's first ayah.
  static Future<String> getAyahText(int surahNumber, int ayahNumber) async {
    await _ensureLoaded();
    final tuples = _rawAyahs![surahNumber - 1];
    if (ayahNumber < 1 || ayahNumber > tuples.length) return '';
    final text = tuples[ayahNumber - 1][5] as String;
    if (ayahNumber == 1 && surahNumber != 1 && surahNumber != 9) {
      return _stripBasmala(text);
    }
    return text;
  }

  /// The GLOBAL ayah number (1-6236) of a surah:ayah pair, or 0 when
  /// out of range. Inverse of [locateGlobalAyah].
  static Future<int> globalAyahNumber(int surahNumber, int ayahNumber) async {
    await _ensureLoaded();
    if (surahNumber < 1 || surahNumber > _rawAyahs!.length) return 0;
    final tuples = _rawAyahs![surahNumber - 1];
    if (ayahNumber < 1 || ayahNumber > tuples.length) return 0;
    return tuples[ayahNumber - 1][0] as int;
  }

  /// Resolves a GLOBAL ayah number (1-6236) to its surah, position and
  /// text. Returns null when out of range. Powers the mutashabihat
  /// list, whose dataset addresses ayahs globally.
  ///
  /// Unlike [getAyahText] the Basmala is NOT stripped from a surah's
  /// first ayah: a mutashabiha match points at the ayah as recited, and
  /// dropping its opening would hide the very words being compared.
  static Future<AyahSearchResult?> locateGlobalAyah(int globalAyah) async {
    await _ensureLoaded();
    for (var s = 0; s < _rawAyahs!.length; s++) {
      final tuples = _rawAyahs![s];
      if (tuples.isEmpty) continue;
      if (globalAyah > (tuples.last[0] as int)) continue;
      if (globalAyah < (tuples.first[0] as int)) return null;
      for (final t in tuples) {
        if (t[0] as int != globalAyah) continue;
        return AyahSearchResult(
          surahNumber: s + 1,
          surahName: _surahCache![s].name,
          numberInSurah: t[1] as int,
          text: t[5] as String,
        );
      }
      return null;
    }
    return null;
  }

  /// The Mushaf page a GLOBAL ayah number (1-6236) appears on, from the
  /// bundled metadata. Returns 1 when out of range.
  static Future<int> pageOfGlobalAyah(int globalAyah) async {
    await _ensureLoaded();
    for (final surah in _rawAyahs!) {
      if (surah.isEmpty) continue;
      final lastGlobal = surah.last[0] as int;
      if (globalAyah <= lastGlobal) {
        for (final t in surah) {
          if (t[0] as int == globalAyah) return t[3] as int;
        }
        return 1;
      }
    }
    return 1;
  }

  /// Every ayah printed on Mushaf page [page], in order, from the
  /// bundled text. Powers the reflowing text edition of the Mushaf.
  ///
  /// The Basmala is stripped from each surah's first ayah for the same
  /// reason as in [getSurahAyahs] — it is printed on its own line, and
  /// the reflowing page draws it as a header.
  static Future<List<PageAyah>> ayahsOnPage(int page) async {
    await _ensureLoaded();
    final out = <PageAyah>[];
    for (var s = 0; s < _rawAyahs!.length; s++) {
      final tuples = _rawAyahs![s];
      // Pages run in order, so a surah ending before this page or
      // starting after it cannot contribute any ayah.
      if ((tuples.last[3] as int) < page) continue;
      if ((tuples.first[3] as int) > page) break;
      for (final t in tuples) {
        if (t[3] as int != page) continue;
        final n = t[1] as int;
        var text = t[5] as String;
        final surah = s + 1;
        if (n == 1 && surah != 1 && surah != 9) text = _stripBasmala(text);
        out.add(PageAyah(surah, n, text));
      }
    }
    return out;
  }

  /// Normalizes Arabic to bare letters word-by-word (public form of
  /// [_bareLetters] for multi-word strings).
  static String normalizeArabic(String s) =>
      s.trim().split(RegExp(r'\s+')).map(_bareLetters).join(' ');

  /// Finds surahs whose name matches [query] — offline, diacritic- and
  /// prefix-insensitive, so typing "الفاتحة" or "سورة الفاتحة" or
  /// "فاتحة" all find سُورَةُ ٱلْفَاتِحَةِ.
  static Future<List<Surah>> searchSurahs(String query) async {
    await _ensureLoaded();
    final q = SurahQuery(query);
    if (q.isEmpty) return [];
    return [
      for (final s in _surahCache!)
        if (q.matches(s)) s,
    ];
  }

  /// A surah name reduced for matching: bare letters, with the "سورة"
  /// prefix the data carries removed so a reader can type either form.
  static String searchKey(String s) => normalizeArabic(s)
      .replaceFirst(RegExp('^${_bareLetters('سورة')}\\s*'), '')
      .trim();

  /// A transliterated name reduced for matching. Transliteration is not
  /// standardised — the data says "Al-Faatiha" and "Al-Baqara" where a
  /// reader types "Fatihah" and "Baqarah" — so doubled vowels, the
  /// hyphen and a trailing h are all folded away.
  static String latinKey(String s) {
    final letters = s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    final b = StringBuffer();
    for (var i = 0; i < letters.length; i++) {
      if (i == 0 || letters[i] != letters[i - 1]) b.write(letters[i]);
    }
    return b.toString().replaceFirst(RegExp('h\$'), '');
  }

  /// Full-text ayah search over the BUNDLED text — works offline.
  /// Both the query and the ayah text are reduced to bare letters, so
  /// plain keyboard input like "الرحمن" matches the vocalized text.
  ///
  /// [surahNumbers], when given, restricts matches to just those surahs
  /// (1-based) — used to scope the search to the surah(s) open in the
  /// Mushaf instead of the whole Quran.
  static Future<List<AyahSearchResult>> searchAyahs(String query,
      {Set<int>? surahNumbers}) async {
    await _ensureLoaded();
    final normQuery =
        query.trim().split(RegExp(r'\s+')).map(_bareLetters).join(' ');
    if (normQuery.isEmpty) return [];

    // Padded with a space at each end so a word can be matched on its
    // BOUNDARIES: ' من ' finds the word مِن, where a bare `contains`
    // also finds it buried inside ٱلرَّحْمَٰن — an ayah that does not
    // carry the searched word at all.
    _searchIndex ??= [
      for (final surah in _rawAyahs!)
        [
          for (final t in surah)
            ' ${(t[5] as String).split(' ').map(_bareLetters).join(' ')} ',
        ],
    ];

    // Phrase first, then — if that finds little — ayahs carrying every
    // word anywhere in them. Typing three words a reader half-remembers
    // rarely reproduces their exact order and spacing, and a phrase-only
    // search answers that with nothing at all.
    final results = <AyahSearchResult>[];
    final seen = <int>{};

    void collect(bool Function(String) matches) {
      for (var s = 0; s < _searchIndex!.length; s++) {
        if (surahNumbers != null && !surahNumbers.contains(s + 1)) continue;
        final texts = _searchIndex![s];
        for (var i = 0; i < texts.length; i++) {
          final key = s * 1000 + i;
          if (seen.contains(key) || !matches(texts[i])) continue;
          seen.add(key);
          results.add(AyahSearchResult(
            surahNumber: s + 1,
            surahName: _surahCache![s].name,
            numberInSurah: _rawAyahs![s][i][1] as int,
            text: _rawAyahs![s][i][5] as String,
          ));
          if (results.length >= 300) return;
        }
      }
    }

    // Best matches first. Each tier is stricter about WHERE the query
    // may appear, so a reader sees ayahs that carry the word before
    // ayahs that merely contain its letters somewhere.
    final words = normQuery.split(' ').where((w) => w.isNotEmpty).toList();

    // 1. The phrase itself, as whole words.
    collect((t) => t.contains(' $normQuery '));
    // 2. Every word present, in any order, each a whole word.
    if (results.length < 300 && words.length > 1) {
      collect((t) => words.every((w) => t.contains(' $w ')));
    }
    // 3. Every word present as the START of a word, with the definite
    //    article optional there just as it is in a surah name — so رحم
    //    reaches ٱلرَّحْمَٰن, whose leading ال would otherwise block the
    //    match. (After normalising, ال reads as a bare lam.) This tier
    //    is also what shows results while a word is still being typed.
    if (results.length < 300) {
      collect((t) =>
          words.every((w) => t.contains(' $w') || t.contains(' ل$w')));
    }
    // 4. Letters anywhere at all, the old behaviour. Kept ONLY as a
    //    last resort: it is what surfaced ayahs with no visible
    //    connection to the query, so it must never dilute a tier above
    //    it — it runs only when nothing better was found.
    if (results.isEmpty) {
      collect((t) => words.every(t.contains));
    }
    return results;
  }

  // Tafsir fetching lives in TafsirService (lib/services/tafsir_service
  // .dart), which also handles offline downloads and the CDN source.
}

/// One ayah as it appears on a Mushaf page — see [QuranService.ayahsOnPage].
class PageAyah {
  final int surahNumber;
  final int numberInSurah;
  final String text;

  const PageAyah(this.surahNumber, this.numberInSurah, this.text);
}

/// A typed surah-name query, normalised once and then matched against
/// candidates — so the home screen's live filter and [QuranService
/// .searchSurahs] cannot drift apart, which is how the filter came to
/// carry a bug the service did not.
class SurahQuery {
  /// Bare-letter form of the query, empty when it holds no Arabic.
  final String arabic;

  /// The same without a leading lam. The definite article is optional —
  /// "بقرة" should find البقرة — and once the alef is normalised away
  /// "ال" reads as a bare lam.
  ///
  /// Empty when stripping the lam would leave nothing: `contains('')`
  /// is true of every string, so an unguarded empty value here matched
  /// the ENTIRE list. Typing "ال", the opening of a great many surah
  /// names, did exactly that.
  final String arabicNoAl;

  /// Transliterated form, empty below two letters: a single Latin
  /// letter appears in almost every name and matches almost everything.
  final String latin;

  /// A surah reached by typing its number, on either keyboard.
  final int? number;

  const SurahQuery._(this.arabic, this.arabicNoAl, this.latin, this.number);

  factory SurahQuery(String raw) {
    final query = raw.trim();
    final arabic = QuranService.searchKey(query);
    final noAl = arabic.replaceFirst(RegExp(r'^ل'), '');
    final latin = QuranService.latinKey(query);
    final digits = query.replaceAllMapped(RegExp('[٠-٩]'),
        (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x0660 + 0x30));
    return SurahQuery._(
      arabic,
      noAl.isEmpty ? '' : noAl,
      latin.length >= 2 ? latin : '',
      int.tryParse(digits),
    );
  }

  bool get isEmpty => arabic.isEmpty && latin.isEmpty && number == null;

  bool matches(Surah s) {
    if (number != null && s.number == number) return true;
    if (arabic.isNotEmpty) {
      final name = QuranService.searchKey(s.name);
      final nameNoAl = name.replaceFirst(RegExp(r'^ل'), '');
      // A single letter matches as a PREFIX only. As a substring it
      // pulls in most of the Mushaf, which reads as random results.
      if (arabic.length == 1) {
        if (name.startsWith(arabic) || nameNoAl.startsWith(arabic)) return true;
      } else {
        if (name.contains(arabic)) return true;
        if (arabicNoAl.isNotEmpty && nameNoAl.contains(arabicNoAl)) return true;
      }
    }
    if (latin.isNotEmpty &&
        (QuranService.latinKey(s.englishName).contains(latin) ||
            QuranService.latinKey(s.englishNameTranslation).contains(latin))) {
      return true;
    }
    return false;
  }
}

class AyahSearchResult {
  final int surahNumber;
  final String surahName;
  final int numberInSurah;
  final String text;

  AyahSearchResult({
    required this.surahNumber,
    required this.surahName,
    required this.numberInSurah,
    required this.text,
  });
}

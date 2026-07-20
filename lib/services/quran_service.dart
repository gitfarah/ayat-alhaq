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
  }

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
      if (_bareLetters(words[i]) != target[i]) return text;
    }
    return words.sublist(4).join(' ');
  }

  /// Reduces an Arabic word to its bare letters: strips tashkeel and
  /// other combining marks, drops tatweel, and folds alef variants
  /// (wasla, madda, hamza forms) into a plain alef.
  static String _bareLetters(String word) {
    final b = StringBuffer();
    for (final r in word.runes) {
      final isMark = (r >= 0x0610 && r <= 0x061A) ||
          (r >= 0x064B && r <= 0x065F) ||
          r == 0x0670 ||
          (r >= 0x06D6 && r <= 0x06ED) ||
          r == 0x0640; // tatweel
      if (isMark) continue;
      if (r == 0x0671 || r == 0x0622 || r == 0x0623 || r == 0x0625) {
        b.write('ا');
      } else {
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

  /// Normalizes Arabic to bare letters word-by-word (public form of
  /// [_bareLetters] for multi-word strings).
  static String normalizeArabic(String s) =>
      s.trim().split(RegExp(r'\s+')).map(_bareLetters).join(' ');

  /// Finds surahs whose name matches [query] — offline, diacritic- and
  /// prefix-insensitive, so typing "الفاتحة" or "سورة الفاتحة" or
  /// "فاتحة" all find سُورَةُ ٱلْفَاتِحَةِ.
  static Future<List<Surah>> searchSurahs(String query) async {
    await _ensureLoaded();
    var q = normalizeArabic(query);
    q = q.replaceFirst(RegExp(r'^سورة\s*'), '');
    if (q.isEmpty) return [];
    final qNoAl = q.replaceFirst(RegExp(r'^ال'), '');
    final results = <Surah>[];
    for (final s in _surahCache!) {
      final name =
          normalizeArabic(s.name).replaceFirst(RegExp(r'^سورة\s*'), '');
      final nameNoAl = name.replaceFirst(RegExp(r'^ال'), '');
      if (name.contains(q) ||
          (qNoAl.isNotEmpty && nameNoAl.contains(qNoAl)) ||
          s.englishName.toLowerCase().contains(query.trim().toLowerCase())) {
        results.add(s);
      }
    }
    return results;
  }

  /// Full-text ayah search over the BUNDLED text — works offline.
  /// Both the query and the ayah text are reduced to bare letters, so
  /// plain keyboard input like "الرحمن" matches the vocalized text.
  static Future<List<AyahSearchResult>> searchAyahs(String query) async {
    await _ensureLoaded();
    final normQuery =
        query.trim().split(RegExp(r'\s+')).map(_bareLetters).join(' ');
    if (normQuery.isEmpty) return [];

    _searchIndex ??= [
      for (final surah in _rawAyahs!)
        [
          for (final t in surah)
            (t[5] as String).split(' ').map(_bareLetters).join(' '),
        ],
    ];

    final results = <AyahSearchResult>[];
    for (var s = 0; s < _searchIndex!.length; s++) {
      final texts = _searchIndex![s];
      for (var i = 0; i < texts.length; i++) {
        if (texts[i].contains(normQuery)) {
          results.add(AyahSearchResult(
            surahNumber: s + 1,
            surahName: _surahCache![s].name,
            numberInSurah: _rawAyahs![s][i][1] as int,
            text: _rawAyahs![s][i][5] as String,
          ));
          if (results.length >= 300) return results;
        }
      }
    }
    return results;
  }

  // Tafsir fetching lives in TafsirService (lib/services/tafsir_service
  // .dart), which also handles offline downloads and the CDN source.
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

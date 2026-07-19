import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/surah.dart';

/// Fetches Quran text data (surah list, ayah text + page/juz/hizb
/// metadata, and tafsir) from the api.alquran.cloud REST API.
class QuranService {
  static const String _baseUrl = 'https://api.alquran.cloud/v1';

  /// The surah list is static reference data that never changes, so we
  /// cache it in memory after the first fetch. Without this, every
  /// screen that needs to resolve a Surah object (bookmarks, highlights)
  /// was re-fetching the entire list over the network on every single
  /// tap, causing a very noticeable delay before navigation even began.
  static List<Surah>? _surahCache;

  static Future<List<Surah>> getAllSurahs({bool forceRefresh = false}) async {
    if (!forceRefresh && _surahCache != null) return _surahCache!;
    final response = await http.get(Uri.parse('$_baseUrl/surah'));
    if (response.statusCode != 200) {
      throw Exception('فشل تحميل قائمة السور');
    }
    final data = jsonDecode(response.body);
    final List list = data['data'];
    _surahCache = list.map((s) => Surah.fromJson(s)).toList();
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

  /// Ayah text uses the Alafasy recitation edition (ar.alafasy) purely
  /// as the text/metadata source — audio itself is fetched separately
  /// by QuranAudioService directly from the CDN using the global ayah
  /// number, not through this endpoint.
  ///
  /// The API merges the Basmala into the first ayah's text of every
  /// surah. Per Mushaf convention it belongs on its own line, so it is
  /// stripped here — except for Al-Fatiha (1), where the Basmala IS
  /// ayah 1, and At-Tawbah (9), which has no Basmala at all.
  /// When [translationEdition] is set, the multi-edition endpoint is
  /// used so Arabic text and translation arrive in ONE request, and each
  /// Ayah carries its translation.
  static Future<List<Ayah>> getSurahAyahs(int surahNumber,
      {String? translationEdition}) async {
    final List ayahs;
    List? translated;
    if (translationEdition == null) {
      final response =
          await http.get(Uri.parse('$_baseUrl/surah/$surahNumber/ar.alafasy'));
      if (response.statusCode != 200) {
        throw Exception('فشل تحميل آيات السورة');
      }
      ayahs = jsonDecode(response.body)['data']['ayahs'];
    } else {
      final response = await http.get(Uri.parse(
          '$_baseUrl/surah/$surahNumber/editions/ar.alafasy,$translationEdition'));
      if (response.statusCode != 200) {
        throw Exception('فشل تحميل آيات السورة');
      }
      final List editions = jsonDecode(response.body)['data'];
      ayahs = editions[0]['ayahs'];
      translated = editions.length > 1 ? editions[1]['ayahs'] : null;
    }

    final list = [
      for (var i = 0; i < ayahs.length; i++)
        Ayah.fromJson({
          ...ayahs[i] as Map<String, dynamic>,
          if (translated != null && i < translated.length)
            'translation': translated[i]['text'],
        }),
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

  /// Fetches a single ayah's text directly — much lighter than fetching
  /// the whole surah when only one verse's text is needed (e.g. opening
  /// Tafsir from the Mushaf page view, which only has ayah *numbers*
  /// from the tap-region data, not the actual Arabic text).
  static Future<String> getAyahText(int surahNumber, int ayahNumber) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/ayah/$surahNumber:$ayahNumber/ar.alafasy'));
    if (response.statusCode != 200) {
      throw Exception('فشل تحميل نص الآية');
    }
    final data = jsonDecode(response.body);
    final text = (data['data']['text'] ?? '') as String;
    // Same Mushaf convention as getSurahAyahs: the API merges the
    // Basmala into each surah's first ayah — show the ayah alone.
    if (ayahNumber == 1 && surahNumber != 1 && surahNumber != 9) {
      return _stripBasmala(text);
    }
    return text;
  }

  /// Full-text ayah search via the API's search endpoint. The
  /// quran-simple-clean edition (no diacritics) is used so plain
  /// keyboard input like "الرحمن" matches the vocalized text.
  /// Returns an empty list when nothing matches (the API reports
  /// no-match as 404).
  static Future<List<AyahSearchResult>> searchAyahs(String query) async {
    final q = Uri.encodeComponent(query.trim());
    if (q.isEmpty) return [];
    final response =
        await http.get(Uri.parse('$_baseUrl/search/$q/all/quran-simple-clean'));
    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      throw Exception('فشل البحث');
    }
    final List matches = jsonDecode(response.body)['data']['matches'];
    return matches
        .map((m) => AyahSearchResult(
              surahNumber: m['surah']['number'],
              surahName: m['surah']['name'] ?? '',
              numberInSurah: m['numberInSurah'],
              text: (m['text'] ?? '') as String,
            ))
        .toList();
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

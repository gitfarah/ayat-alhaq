import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage/tafsir_storage.dart';

/// A tafsir edition the app offers. Two remote sources exist:
///  - [cdnSlug]: spa5k/tafsir_api on jsDelivr — per-ayah AND per-surah
///    JSON. This is the primary source and the only one carrying
///    Ibn Kathir, As-Saadi and At-Tabari. Per-surah files make full
///    offline downloads cheap (114 requests per tafsir).
///  - [cloudEdition]: api.alquran.cloud identifier, kept as an online
///    fallback for editions that exist there.
class TafsirEdition {
  final int id;
  final String name;
  final String cdnSlug;
  final String? cloudEdition;

  const TafsirEdition({
    required this.id,
    required this.name,
    required this.cdnSlug,
    this.cloudEdition,
  });
}

class TafsirService {
  static const String _cdnBase =
      'https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir';
  static const String _cloudBase = 'https://api.alquran.cloud/v1';

  /// Every slug verified against the CDN's editions.json; every
  /// cloudEdition verified against alquran.cloud type=tafsir list.
  /// IDs are stable — they are stored in SharedPreferences.
  ///
  /// [editions.first] is the app-wide default (the tafsir screen and
  /// the ayah share sheet both fall back to it), so its position here
  /// IS the default-edition setting, not just display order.
  static const List<TafsirEdition> editions = [
    TafsirEdition(
        id: 98,
        name: 'المختصر في تفسير القرآن الكريم',
        cdnSlug: 'ar-tafsir-al-mukhtasar'),
    TafsirEdition(
        id: 16,
        name: 'التفسير الميسر',
        cdnSlug: 'ar-tafsir-muyassar',
        cloudEdition: 'ar.muyassar'),
    TafsirEdition(
        id: 97, name: 'تفسير ابن كثير', cdnSlug: 'ar-tafsir-ibn-kathir'),
    TafsirEdition(
        id: 91, name: 'تفسير السعدي', cdnSlug: 'ar-tafsir-as-saadi'),
    TafsirEdition(
        id: 14,
        name: 'تفسير الجلالين',
        cdnSlug: 'ar-tafsir-al-jalalayn',
        cloudEdition: 'ar.jalalayn'),
    TafsirEdition(
        id: 94,
        name: 'تفسير البغوي',
        cdnSlug: 'ar-tafsir-al-baghawi',
        cloudEdition: 'ar.baghawi'),
    TafsirEdition(
        id: 90,
        name: 'تفسير القرطبي',
        cdnSlug: 'ar-tafseer-al-qurtubi',
        cloudEdition: 'ar.qurtubi'),
    TafsirEdition(
        id: 15, name: 'تفسير الطبري', cdnSlug: 'ar-tafsir-al-tabari'),
    TafsirEdition(
        id: 95,
        name: 'التفسير الوسيط',
        cdnSlug: 'ar-tafsir-al-wasit',
        cloudEdition: 'ar.waseet'),
    TafsirEdition(
        id: 96,
        name: 'تنوير المقباس (ابن عباس)',
        cdnSlug: 'ar-tafseer-tanwir-al-miqbas',
        cloudEdition: 'ar.miqbas'),
  ];

  /// Same value as `editions.first.id`, kept as its own constant only
  /// because a parameter default must be a compile-time constant — a
  /// list lookup isn't one. Change the default edition by reordering
  /// [editions]; update this alongside it.
  static const int defaultEditionId = 98;

  static TafsirEdition? editionById(int id) {
    for (final e in editions) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Whether full offline downloads are available on this platform.
  static bool get supportsDownload => TafsirFileStorage.supportsDownload;

  /// Tafsir text for one ayah: downloaded copy first, then the CDN,
  /// then alquran.cloud as a last resort.
  static Future<String> getTafsir(int surahNumber, int ayahNumber,
      {int tafsirId = defaultEditionId}) async {
    final edition = editionById(tafsirId) ?? editions.first;

    // 1. Local download.
    final local = await TafsirFileStorage.readSurah(edition.id, surahNumber);
    if (local != null) {
      try {
        final List ayahs = jsonDecode(local)['ayahs'];
        final hit = ayahs.firstWhere((a) => a['ayah'] == ayahNumber,
            orElse: () => null);
        if (hit != null) return hit['text'] ?? '';
      } catch (_) {
        // Corrupt file — fall through to network.
      }
    }

    // 2. CDN per-ayah file.
    try {
      final r = await http.get(Uri.parse(
          '$_cdnBase/${edition.cdnSlug}/$surahNumber/$ayahNumber.json'));
      if (r.statusCode == 200) {
        final text = jsonDecode(utf8.decode(r.bodyBytes))['text'];
        if (text is String && text.isNotEmpty) return text;
      }
    } catch (_) {
      // Fall through to alquran.cloud.
    }

    // 3. alquran.cloud fallback (only for editions that exist there).
    if (edition.cloudEdition != null) {
      final r = await http.get(Uri.parse(
          '$_cloudBase/ayah/$surahNumber:$ayahNumber/${edition.cloudEdition}'));
      if (r.statusCode == 200) {
        return jsonDecode(r.body)['data']['text'] ?? '';
      }
    }
    throw Exception('فشل تحميل التفسير');
  }

  /// Downloads the whole edition (114 per-surah files) for offline use.
  /// [onProgress] gets (surahsDone, 114); [isCancelled] is checked
  /// before each surah. Already-stored surahs are skipped, so an
  /// interrupted download resumes where it stopped.
  static Future<void> downloadEdition(
    int tafsirId, {
    required void Function(int done, int total) onProgress,
    bool Function()? isCancelled,
  }) async {
    final edition = editionById(tafsirId);
    if (edition == null || !supportsDownload) return;
    for (var surah = 1; surah <= 114; surah++) {
      if (isCancelled != null && isCancelled()) break;
      final existing = await TafsirFileStorage.readSurah(edition.id, surah);
      if (existing == null) {
        final r = await http
            .get(Uri.parse('$_cdnBase/${edition.cdnSlug}/$surah.json'));
        if (r.statusCode != 200) {
          throw Exception('فشل تحميل سورة $surah');
        }
        // Normalize to {ayahs:[{ayah,text},...]} so the reader doesn't
        // depend on the CDN's raw shape (a bare array, where surah-intro
        // entries may carry no ayah number — those are skipped).
        final decoded = jsonDecode(utf8.decode(r.bodyBytes));
        final List raw =
            decoded is List ? decoded : (decoded['ayahs'] as List);
        final normalized = jsonEncode({
          'ayahs': [
            for (final a in raw)
              if (a['ayah'] != null)
                {'ayah': a['ayah'], 'text': a['text'] ?? ''},
          ]
        });
        await TafsirFileStorage.writeSurah(edition.id, surah, normalized);
      }
      onProgress(surah, 114);
    }
  }

  /// True when all 114 surahs of the edition are stored locally.
  static Future<bool> isDownloaded(int tafsirId) async =>
      (await TafsirFileStorage.surahCount(tafsirId)) >= 114;

  static Future<int> downloadedSizeBytes(int tafsirId) =>
      TafsirFileStorage.editionSizeBytes(tafsirId);

  static Future<void> deleteDownload(int tafsirId) =>
      TafsirFileStorage.deleteEdition(tafsirId);
}

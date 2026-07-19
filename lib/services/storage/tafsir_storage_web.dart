/// Web storage backend for tafsirs — downloads are NOT offered here:
/// browser localStorage (5-10MB) cannot hold full tafsir texts, and
/// the app is online on web anyway, so per-ayah network fetching is
/// always available. All methods are inert.
class TafsirFileStorage {
  static Future<String?> readSurah(int editionId, int surah) async => null;

  static Future<void> writeSurah(
      int editionId, int surah, String json) async {}

  static Future<int> surahCount(int editionId) async => 0;

  static Future<void> deleteEdition(int editionId) async {}

  static Future<int> editionSizeBytes(int editionId) async => 0;

  static const bool supportsDownload = false;
}

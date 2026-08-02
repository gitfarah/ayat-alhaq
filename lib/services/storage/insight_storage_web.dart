/// Web backing store for the ayah study layers — inert, matching the
/// tafsir backend. The app is online on web anyway, and the in-memory
/// cache already spares repeat fetches within a session.
class InsightFileStorage {
  static Future<String?> readSurah(String slug, int surah) async => null;

  static Future<void> writeSurah(
      String slug, int surah, String json) async {}

  static Future<int> cacheSizeBytes() async => 0;

  static Future<void> clearCache() async {}

  static const bool supportsCache = false;
}

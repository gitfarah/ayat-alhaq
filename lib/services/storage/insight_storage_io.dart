import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Mobile/desktop backing store for the ayah study layers — الإعراب،
/// التصريف، المعنى، القراءات.
///
/// One JSON file per book per surah, under insights/{slug}/, each
/// holding only the ayahs the reader has actually opened. There is no
/// bulk download for these works (the API serves word data one ayah at
/// a time), so the cache fills as the reader reads: revisiting an ayah
/// then works with no network at all.
class InsightFileStorage {
  static Future<Directory> _dir(String slug) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/insights/$slug');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String?> readSurah(String slug, int surah) async {
    final dir = await _dir(slug);
    final f = File('${dir.path}/$surah.json');
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  static Future<void> writeSurah(
      String slug, int surah, String json) async {
    final dir = await _dir(slug);
    await File('${dir.path}/$surah.json').writeAsString(json);
  }

  static Future<int> cacheSizeBytes() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/insights');
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static Future<void> clearCache() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/insights');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static const bool supportsCache = true;
}

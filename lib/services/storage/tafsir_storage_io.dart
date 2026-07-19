import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Mobile/desktop storage backend for downloaded tafsirs — one JSON
/// file per surah, under tafsir/{editionId}/. A full tafsir is 114
/// small text files (a few MB total), so per-edition downloads are
/// practical without shipping every tafsir with the app.
class TafsirFileStorage {
  static Future<Directory> _dir(int editionId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/tafsir/$editionId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String?> readSurah(int editionId, int surah) async {
    final dir = await _dir(editionId);
    final f = File('${dir.path}/$surah.json');
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  static Future<void> writeSurah(
      int editionId, int surah, String json) async {
    final dir = await _dir(editionId);
    await File('${dir.path}/$surah.json').writeAsString(json);
  }

  /// Number of surah files stored for this edition (114 = complete).
  static Future<int> surahCount(int editionId) async {
    final dir = await _dir(editionId);
    var count = 0;
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) count++;
    }
    return count;
  }

  static Future<void> deleteEdition(int editionId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/tafsir/$editionId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<int> editionSizeBytes(int editionId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/tafsir/$editionId');
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static const bool supportsDownload = true;
}

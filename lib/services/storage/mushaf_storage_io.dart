import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Mobile/desktop storage backend — real files on disk. Phones have
/// gigabytes of free space, so caching the entire ~230MB Mushaf here
/// is practical and safe.
class MushafFileStorage {
  /// Pages are stored per mushaf edition so switching riwayah never
  /// mixes pages from different editions.
  static String edition = 'hafs';

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/mushaf_pages/$edition');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _pad(int page) => page.toString().padLeft(3, '0');

  static Future<bool> hasPage(int page) async {
    final dir = await _dir();
    final svg = File('${dir.path}/${_pad(page)}.svg');
    final json = File('${dir.path}/${_pad(page)}.json');
    return await svg.exists() && await json.exists();
  }

  static Future<String?> readSvg(int page) async {
    final dir = await _dir();
    final f = File('${dir.path}/${_pad(page)}.svg');
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  static Future<String?> readJson(int page) async {
    final dir = await _dir();
    final f = File('${dir.path}/${_pad(page)}.json');
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  static Future<void> writePage(int page, String svg, String json) async {
    final dir = await _dir();
    await File('${dir.path}/${_pad(page)}.svg').writeAsString(svg);
    await File('${dir.path}/${_pad(page)}.json').writeAsString(json);
  }

  static Future<void> deletePage(int page) async {
    final dir = await _dir();
    final svg = File('${dir.path}/${_pad(page)}.svg');
    final json = File('${dir.path}/${_pad(page)}.json');
    if (await svg.exists()) await svg.delete();
    if (await json.exists()) await json.delete();
  }

  static Future<void> clearAll() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<int> totalSizeBytes() async {
    final dir = await _dir();
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static Future<List<int>> cachedPages() async {
    final dir = await _dir();
    if (!await dir.exists()) return [];
    final pages = <int>{};
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.svg')) {
        final name = e.uri.pathSegments.last.replaceAll('.svg', '');
        final n = int.tryParse(name);
        if (n != null) pages.add(n);
      }
    }
    return pages.toList()..sort();
  }

  /// Phones have ample storage — full offline download is offered.
  static const bool supportsFullOfflineDownload = true;
}

/// Page-font bytes for the glyph-rendered KFGQPC V2 edition. Each
/// page has its own font, so these are cached exactly like page
/// artwork — fetched once, then read from disk.
class MushafFontStorage {
  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/mushaf_fonts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Uint8List?> read(int page) async {
    try {
      final f = File('${(await _dir()).path}/v2_p$page.ttf');
      if (!await f.exists()) return null;
      return f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(int page, Uint8List bytes) async {
    try {
      final f = File('${(await _dir()).path}/v2_p$page.ttf');
      await f.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Caching is opportunistic; the font is already in memory.
    }
  }

  /// Drops one page's cached font — used when the file turns out to be
  /// truncated or otherwise unusable, so the next attempt refetches it.
  static Future<void> remove(int page) async {
    try {
      final f = File('${(await _dir()).path}/v2_p$page.ttf');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<int> cachedCount() async {
    try {
      final dir = await _dir();
      return dir.listSync().whereType<File>().length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clear() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}

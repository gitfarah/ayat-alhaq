import 'package:shared_preferences/shared_preferences.dart';

/// Web storage backend — localStorage via SharedPreferences. Browsers
/// cap this at roughly 5-10MB per site, which cannot hold the full
/// ~230MB Mushaf, so only a small rolling cache of recently viewed
/// pages is kept here. Full offline download is not offered on web.
class MushafFileStorage {
  static String _svgKey(int page) =>
      'mushaf_svg_${page.toString().padLeft(3, '0')}';
  static String _jsonKey(int page) =>
      'mushaf_json_${page.toString().padLeft(3, '0')}';
  static const String _indexKey = 'mushaf_cached_pages';
  static const int maxWebPages = 8;

  static Future<bool> hasPage(int page) async {
    final p = await SharedPreferences.getInstance();
    return p.containsKey(_svgKey(page)) && p.containsKey(_jsonKey(page));
  }

  static Future<String?> readSvg(int page) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_svgKey(page));
  }

  static Future<String?> readJson(int page) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_jsonKey(page));
  }

  static Future<void> writePage(int page, String svg, String json) async {
    final p = await SharedPreferences.getInstance();
    await _evictIfNeeded(p);
    await p.setString(_svgKey(page), svg);
    await p.setString(_jsonKey(page), json);
    final idx = p.getStringList(_indexKey) ?? [];
    if (!idx.contains('$page')) {
      idx.add('$page');
      await p.setStringList(_indexKey, idx);
    }
  }

  static Future<void> _evictIfNeeded(SharedPreferences p) async {
    final idx = p.getStringList(_indexKey) ?? [];
    if (idx.length >= maxWebPages) {
      final toRemove = idx.take(idx.length - maxWebPages + 1).toList();
      for (final s in toRemove) {
        final n = int.tryParse(s);
        if (n != null) {
          await p.remove(_svgKey(n));
          await p.remove(_jsonKey(n));
        }
      }
      idx.removeWhere((s) => toRemove.contains(s));
      await p.setStringList(_indexKey, idx);
    }
  }

  static Future<void> deletePage(int page) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_svgKey(page));
    await p.remove(_jsonKey(page));
    final idx = p.getStringList(_indexKey) ?? [];
    idx.remove('$page');
    await p.setStringList(_indexKey, idx);
  }

  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    final idx = p.getStringList(_indexKey) ?? [];
    for (final s in idx) {
      final n = int.tryParse(s);
      if (n != null) {
        await p.remove(_svgKey(n));
        await p.remove(_jsonKey(n));
      }
    }
    await p.remove(_indexKey);
  }

  static Future<int> totalSizeBytes() async {
    final p = await SharedPreferences.getInstance();
    final idx = p.getStringList(_indexKey) ?? [];
    int total = 0;
    for (final s in idx) {
      final n = int.tryParse(s);
      if (n != null) {
        total += p.getString(_svgKey(n))?.length ?? 0;
        total += p.getString(_jsonKey(n))?.length ?? 0;
      }
    }
    return total;
  }

  static Future<List<int>> cachedPages() async {
    final p = await SharedPreferences.getInstance();
    final idx = p.getStringList(_indexKey) ?? [];
    return idx.map((s) => int.tryParse(s)).whereType<int>().toList()..sort();
  }

  /// Browser storage quotas can't fit the full Mushaf.
  static const bool supportsFullOfflineDownload = false;
}

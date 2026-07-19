import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quran_page_meta.dart';
import 'library_events.dart';

/// Automatic khatma progress: reading screens report each page the
/// user actually views; once every page of a juz has been read, that
/// juz is checked off in the الختمة tracker automatically. Manual
/// ticking in the khatma screen keeps working alongside this.
class KhatmaService {
  static const _pagesKey = 'readPages';
  static const _khatmaKey = 'khatma';

  /// Records [page] as read and auto-completes its juz when it was the
  /// last unread page of that juz.
  static Future<void> markPageRead(int page) async {
    if (page < 1 || page > 604) return;
    final p = await SharedPreferences.getInstance();
    final read = (p.getStringList(_pagesKey) ?? []).toSet();
    if (!read.add('$page')) return; // Already counted.
    await p.setStringList(_pagesKey, read.toList());

    final juz = QuranPageMeta.juzForPage(page);
    final start = QuranPageMeta.juzStartPages[juz - 1];
    final end = juz < 30 ? QuranPageMeta.juzStartPages[juz] - 1 : 604;
    for (var pg = start; pg <= end; pg++) {
      if (!read.contains('$pg')) return; // Juz not finished yet.
    }
    await _markJuzDone(p, juz);
  }

  static Future<void> _markJuzDone(SharedPreferences p, int juz) async {
    var done = List<bool>.filled(30, false);
    String? start;
    final raw = p.getString(_khatmaKey);
    if (raw != null) {
      final m = jsonDecode(raw);
      done = (m['done'] as List).map((e) => e as bool).toList();
      start = m['start'] as String?;
    }
    if (done[juz - 1]) return;
    done[juz - 1] = true;
    start ??= DateTime.now().toIso8601String();
    await p.setString(
        _khatmaKey, jsonEncode({'done': done, 'start': start}));
    LibraryEvents.khatma.ping();
  }

  /// Number of distinct pages read so far (for the khatma screen).
  static Future<int> readPageCount() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_pagesKey) ?? []).length;
  }

  /// Clears the page-read record — called when the user restarts the
  /// khatma, so old reads don't instantly re-complete ajza'.
  static Future<void> resetReadPages() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_pagesKey);
  }
}

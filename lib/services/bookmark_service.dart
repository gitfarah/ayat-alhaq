import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'library_events.dart';

class Bookmark {
  final int surahNumber;
  final int ayahNumber;
  final String surahName;
  final String? note;
  final String color;
  final DateTime createdAt;

  Bookmark({
    required this.surahNumber,
    required this.ayahNumber,
    required this.surahName,
    this.note,
    this.color = 'green',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'surahNumber': surahNumber,
        'ayahNumber': ayahNumber,
        'surahName': surahName,
        'note': note,
        'color': color,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        surahNumber: json['surahNumber'],
        ayahNumber: json['ayahNumber'],
        surahName: json['surahName'],
        note: json['note'],
        color: json['color'] ?? 'green',
        createdAt: DateTime.parse(json['createdAt']),
      );
}

class BookmarkService {
  static const _key = 'bookmarks';

  static Future<void> addBookmark(Bookmark bookmark) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.removeWhere((b) => jsonDecode(b)['color'] == bookmark.color);
    list.add(jsonEncode(bookmark.toJson()));
    await prefs.setStringList(_key, list);
    LibraryEvents.bookmarks.ping();
  }

  static Future<List<Bookmark>> getAllBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.map((e) => Bookmark.fromJson(jsonDecode(e))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<Bookmark?> getBookmarkByColor(String color) async {
    final all = await getAllBookmarks();
    try {
      return all.firstWhere((b) => b.color == color);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Bookmark>> getBookmarksBySurah(int surahNumber) async {
    final all = await getAllBookmarks();
    return all.where((b) => b.surahNumber == surahNumber).toList();
  }

  /// Delete by index — kept for backward compatibility
  static Future<void> deleteBookmark(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    final sorted = list
        .map((e) => MapEntry(e, Bookmark.fromJson(jsonDecode(e))))
        .toList()
      ..sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));
    if (index >= 0 && index < sorted.length) {
      list.remove(sorted[index].key);
      await prefs.setStringList(_key, list);
      LibraryEvents.bookmarks.ping();
    }
  }

  /// Delete by surah + ayah — safer
  static Future<void> deleteBookmarkByAyah(
      int surahNumber, int ayahNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.removeWhere((b) {
      final d = jsonDecode(b);
      return d['surahNumber'] == surahNumber && d['ayahNumber'] == ayahNumber;
    });
    await prefs.setStringList(_key, list);
    LibraryEvents.bookmarks.ping();
  }

  static Future<bool> isBookmarked(int surahNumber, int ayahNumber) async {
    final all = await getAllBookmarks();
    return all
        .any((b) => b.surahNumber == surahNumber && b.ayahNumber == ayahNumber);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    LibraryEvents.bookmarks.ping();
  }
}

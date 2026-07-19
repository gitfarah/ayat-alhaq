import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'library_events.dart';

class Highlight {
  final int surahNumber;
  final int ayahNumber;
  final String surahName;
  final String color;
  final String? note;
  final DateTime createdAt;

  Highlight({
    required this.surahNumber,
    required this.ayahNumber,
    required this.surahName,
    required this.color,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'surahNumber': surahNumber,
        'ayahNumber': ayahNumber,
        'surahName': surahName,
        'color': color,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Highlight.fromJson(Map<String, dynamic> json) => Highlight(
        surahNumber: json['surahNumber'],
        ayahNumber: json['ayahNumber'],
        surahName: json['surahName'],
        color: json['color'],
        note: json['note'],
        createdAt: DateTime.parse(json['createdAt']),
      );
}

class HighlightService {
  static const String _key = 'highlights';

  // حفظ تمييز جديد
  static Future<void> addHighlight(Highlight highlight) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> highlights = prefs.getStringList(_key) ?? [];

    // إزالة التمييز السابق لنفس الآية
    highlights.removeWhere((h) {
      final decoded = jsonDecode(h);
      return decoded['surahNumber'] == highlight.surahNumber &&
          decoded['ayahNumber'] == highlight.ayahNumber;
    });

    highlights.add(jsonEncode(highlight.toJson()));
    await prefs.setStringList(_key, highlights);
    LibraryEvents.highlights.ping();
  }

  // جلب كل التمييزات
  static Future<List<Highlight>> getAllHighlights() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> highlights = prefs.getStringList(_key) ?? [];
    return highlights.map((e) => Highlight.fromJson(jsonDecode(e))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // جلب تمييز لآية محددة
  static Future<Highlight?> getHighlight(
      int surahNumber, int ayahNumber) async {
    final highlights = await getAllHighlights();
    try {
      return highlights.firstWhere(
          (h) => h.surahNumber == surahNumber && h.ayahNumber == ayahNumber);
    } catch (e) {
      return null;
    }
  }

  // حذف تمييز
  static Future<void> deleteHighlight(int surahNumber, int ayahNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> highlights = prefs.getStringList(_key) ?? [];

    highlights.removeWhere((h) {
      final decoded = jsonDecode(h);
      return decoded['surahNumber'] == surahNumber &&
          decoded['ayahNumber'] == ayahNumber;
    });

    await prefs.setStringList(_key, highlights);
    LibraryEvents.highlights.ping();
  }

  // جلب التمييزات لسورة محددة
  static Future<List<Highlight>> getHighlightsBySurah(int surahNumber) async {
    final highlights = await getAllHighlights();
    return highlights.where((h) => h.surahNumber == surahNumber).toList();
  }
}

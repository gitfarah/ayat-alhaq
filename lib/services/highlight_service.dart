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

  /// Mushaf page the mark was made on, or null when it was made in the
  /// verse-by-verse reader. Opening the mark returns to that same mode.
  final int? page;

  Highlight({
    required this.surahNumber,
    required this.ayahNumber,
    required this.surahName,
    required this.color,
    this.note,
    required this.createdAt,
    this.page,
  });

  bool get isFromMushaf => page != null;

  /// A note counts as present only when it has actual text — an empty
  /// string is stored as null so the UI never shows a blank note card.
  bool get hasNote => note != null && note!.trim().isNotEmpty;

  Highlight copyWith({String? color, String? note, bool clearNote = false}) =>
      Highlight(
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
        surahName: surahName,
        color: color ?? this.color,
        note: clearNote ? null : (note ?? this.note),
        createdAt: createdAt,
        page: page,
      );

  Map<String, dynamic> toJson() => {
        'surahNumber': surahNumber,
        'ayahNumber': ayahNumber,
        'surahName': surahName,
        'color': color,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'page': page,
      };

  factory Highlight.fromJson(Map<String, dynamic> json) => Highlight(
        surahNumber: json['surahNumber'],
        ayahNumber: json['ayahNumber'],
        surahName: json['surahName'],
        color: json['color'],
        note: json['note'],
        createdAt: DateTime.parse(json['createdAt']),
        // Older saved marks have no page — they open in the reader,
        // which is where they were made before this was tracked.
        page: json['page'] as int?,
      );
}

class HighlightService {
  static const String _key = 'highlights';

  // حفظ تمييز جديد
  static Future<void> addHighlight(Highlight highlight) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> highlights = prefs.getStringList(_key) ?? [];

    // إزالة التمييز السابق لنفس الآية
    String? previousNote;
    highlights.removeWhere((h) {
      final decoded = jsonDecode(h);
      final same = decoded['surahNumber'] == highlight.surahNumber &&
          decoded['ayahNumber'] == highlight.ayahNumber;
      // Recolouring an ayah must not throw away the note written on it —
      // the colour pickers build a fresh Highlight with no note.
      if (same) previousNote = decoded['note'] as String?;
      return same;
    });

    final toSave = highlight.note == null && previousNote != null
        ? highlight.copyWith(note: previousNote)
        : highlight;
    highlights.add(jsonEncode(toSave.toJson()));
    await prefs.setStringList(_key, highlights);
    LibraryEvents.highlights.ping();
  }

  /// Writes (or clears) the note on an ayah. Passing null/blank removes
  /// the note but keeps the colour mark.
  ///
  /// Notes live on the mark, so writing one on an ayah that isn't marked
  /// yet creates the mark too — [defaultColor] is used in that case, and
  /// [surahName]/[page] describe where the note was written so the
  /// Highlights tab can reopen it in the right mode.
  static Future<void> setNote(
    int surahNumber,
    int ayahNumber, {
    required String? note,
    String surahName = '',
    int? page,
    String defaultColor = 'yellow',
  }) async {
    final clean = note?.trim();
    final existing = await getHighlight(surahNumber, ayahNumber);

    if (existing == null) {
      // Nothing to attach an empty note to — don't create a bare mark.
      if (clean == null || clean.isEmpty) return;
      await addHighlight(Highlight(
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
        surahName: surahName,
        color: defaultColor,
        note: clean,
        createdAt: DateTime.now(),
        page: page,
      ));
      return;
    }

    final updated = (clean == null || clean.isEmpty)
        ? existing.copyWith(clearNote: true)
        : existing.copyWith(note: clean);

    final prefs = await SharedPreferences.getInstance();
    final List<String> highlights = prefs.getStringList(_key) ?? [];
    highlights.removeWhere((h) {
      final decoded = jsonDecode(h);
      return decoded['surahNumber'] == surahNumber &&
          decoded['ayahNumber'] == ayahNumber;
    });
    highlights.add(jsonEncode(updated.toJson()));
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

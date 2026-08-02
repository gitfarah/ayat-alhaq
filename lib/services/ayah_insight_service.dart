import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage/insight_storage.dart';

/// The linguistic layers the Tafsir screen offers beside the tafsir
/// itself. Each maps to a "project" on the surahapp content API — some
/// exist at ayah level, some at word level, some at both.
enum InsightKind { eerab, tasreef, meaning, qiraat }

extension InsightKindInfo on InsightKind {
  /// Arabic tab/section label. The reading surfaces are Arabic-only by
  /// design, so these are not routed through L10n.
  String get title => switch (this) {
        InsightKind.eerab => 'الإعراب',
        InsightKind.tasreef => 'التصريف',
        InsightKind.meaning => 'المعنى',
        InsightKind.qiraat => 'القراءات',
      };

  /// Attribution shown under a section, so the reader knows which
  /// published work the text comes from.
  String get source => switch (this) {
        InsightKind.eerab => 'النهج القويم في إعراب القرآن الكريم',
        InsightKind.tasreef => 'تصريف كلمات القرآن',
        InsightKind.meaning => 'معاني كلمات القرآن',
        InsightKind.qiraat => 'بيان القراءات (على مستوى الكلمة)',
      };

  /// Word-level project slug. Every kind has one.
  ///
  /// The meanings deliberately use `meaning-word-oldv` rather than the
  /// newer `meaning-word`: the latter is listed in the API's slug enum
  /// but is not published — `/project/meaning-word` answers 404 and its
  /// word endpoints have no data. `-oldv` serves the whole Quran. Worth
  /// re-testing if the newer volume is ever published.
  String get _wordSlug => switch (this) {
        InsightKind.eerab => 'eerab-word',
        InsightKind.tasreef => 'word-tasreef',
        InsightKind.meaning => 'meaning-word-oldv',
        InsightKind.qiraat => 'word-qeraat',
      };

  /// Ayah-level project slug, or null when the work is word-only.
  /// Only the i'rab has a whole-ayah parse (the others are inherently
  /// per-word), so it is the one kind with a summary section on top.
  String? get _ayahSlug =>
      this == InsightKind.eerab ? 'eerab-aya' : null;
}

/// On-device store for the study layers, filled as the reader reads.
///
/// These works have no bulk endpoint — the API serves word data one
/// ayah at a time — so there is nothing to "download". Instead every
/// ayah opened is kept, and reopening it later needs no connection.
///
/// Entries are grouped one file per book per surah rather than one file
/// per ayah, which keeps the file count in the hundreds instead of the
/// tens of thousands.
class InsightCache {
  /// "slug/surah" -> the surah's document, keyed by ayah number.
  ///
  /// The FUTURE is cached, not the resolved map: the screen asks the
  /// same book for the same ayah from two places at once, and two
  /// concurrent loads would each build a separate document, so
  /// whichever saved last would drop the other's entries.
  static final Map<String, Future<Map<String, dynamic>>> _docs = {};

  /// Serializes saves per document, so two ayahs written at the same
  /// time cannot interleave and truncate the file.
  static final Map<String, Future<void>> _saves = {};

  static String _docKey(String slug, int surah) => '$slug/$surah';

  static Future<Map<String, dynamic>> _doc(String slug, int surah) =>
      _docs[_docKey(slug, surah)] ??= _load(slug, surah);

  static Future<Map<String, dynamic>> _load(String slug, int surah) async {
    try {
      final raw = await InsightFileStorage.readSurah(slug, surah);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {
      // Missing plugin, unreadable file or corrupt JSON — start empty
      // rather than fail the read the caller is waiting on.
    }
    return <String, dynamic>{};
  }

  /// `(found, payload)`. [found] distinguishes "this ayah is stored and
  /// the book has nothing for it" from "never fetched", so a known gap
  /// isn't retried on every open.
  static Future<(bool, dynamic)> read(
      String slug, int surah, int ayah) async {
    final doc = await _doc(slug, surah);
    if (!doc.containsKey('$ayah')) return (false, null);
    return (true, doc['$ayah']);
  }

  static Future<void> write(
      String slug, int surah, int ayah, dynamic payload) async {
    final doc = await _doc(slug, surah);
    doc['$ayah'] = payload;
    final key = _docKey(slug, surah);
    final save = (_saves[key] ?? Future<void>.value()).then((_) async {
      try {
        await InsightFileStorage.writeSurah(slug, surah, jsonEncode(doc));
      } catch (_) {
        // Failing to cache must never break the read that produced it.
      }
    });
    _saves[key] = save;
    await save;
  }

  static Future<void> clear() async {
    forgetInMemory();
    try {
      await InsightFileStorage.clearCache();
    } catch (_) {
      // No storage on this platform (or it refused) — dropping the
      // in-memory documents is the part that must not fail.
    }
  }

  /// Drops the loaded documents but leaves the files alone, so the next
  /// read comes back off disk — the state a fresh launch starts in.
  static void forgetInMemory() {
    _docs.clear();
    _saves.clear();
  }
}

/// A slice of a qira'at entry: the reading it describes (`عند الوصل`,
/// `عند الوقف`…) and the text. [label] is null for the opening slice,
/// which the work leaves unheaded.
class QiraatSegment {
  final String? label;
  final String text;

  const QiraatSegment({required this.label, required this.text});
}

/// One word of an ayah with the text a project has for it.
class WordInsight {
  /// 1-based position within the ayah, as the API numbers words.
  final int wordNumber;
  final String word;
  final String content;

  const WordInsight({
    required this.wordNumber,
    required this.word,
    required this.content,
  });

  factory WordInsight.fromJson(Map<String, dynamic> j) => WordInsight(
        wordNumber: j['word_number'] as int,
        word: (j['word'] as String?)?.trim() ?? '',
        content: (j['content'] as String?)?.trim() ?? '',
      );
}

/// Reads the per-ayah and per-word linguistic works published by
/// surahapp (https://dev.surahapp.com/api/docs/).
///
/// Everything is fetched on demand and cached in memory for the life of
/// the process: opening the Tafsir screen on the same ayah twice, or
/// switching tabs back and forth, costs one request per project.
class AyahInsightService {
  static const String _base = 'https://dev.surahapp.com/api/v1';

  /// The API truncates an over-long word range to the ayah's real word
  /// count, so one request with a generous ceiling both discovers the
  /// word list and fetches its content. The longest ayah in the Quran
  /// (2:282) has 128 words.
  static const int _maxWordsPerAyah = 200;

  static const Duration _timeout = Duration(seconds: 20);

  static final Map<String, List<WordInsight>> _wordCache = {};
  static final Map<String, String?> _ayahCache = {};

  /// Requests already in the air, so the same book is fetched once even
  /// though the word strip and the open tab both ask for it. Entries
  /// are dropped on completion, so a retry after a failure re-fetches.
  static final Map<String, Future<List<WordInsight>>> _wordPending = {};
  static final Map<String, Future<String?>> _ayahPending = {};

  static String _key(String slug, int surah, int ayah) => '$slug/$surah/$ayah';

  /// The whole-ayah text for [kind], or null when the work has no
  /// ayah-level volume or no entry for this ayah.
  ///
  /// Answered from memory, then from the on-device cache, then from the
  /// network — so an ayah opened once reads back with no connection.
  /// Throws only on a transport failure, so the caller can offer a
  /// retry; a missing entry (404) is a null, not an error.
  static Future<String?> ayahText(InsightKind kind, int surah, int ayah) {
    final slug = kind._ayahSlug;
    if (slug == null) return Future.value();

    final key = _key(slug, surah, ayah);
    if (_ayahCache.containsKey(key)) return Future.value(_ayahCache[key]);

    // The callback body must NOT return the removed entry: whenComplete
    // awaits a returned future, and that entry IS this future — it
    // would wait on itself forever.
    return _ayahPending[key] ??= _fetchAyahText(kind, slug, key, surah, ayah)
        .whenComplete(() {
      _ayahPending.remove(key);
    });
  }

  static Future<String?> _fetchAyahText(InsightKind kind, String slug,
      String key, int surah, int ayah) async {
    final (onDisk, stored) = await InsightCache.read(slug, surah, ayah);
    if (onDisk) return _ayahCache[key] = stored as String?;

    final r = await http
        .get(Uri.parse('$_base/aya/$slug/$surah/$ayah'))
        .timeout(_timeout);
    if (r.statusCode != 200) {
      // 404 means this work simply doesn't cover the ayah — remember
      // the absence so the tab neither re-requests it on every rebuild
      // nor claims a network problem when offline.
      if (r.statusCode == 404) {
        await InsightCache.write(slug, surah, ayah, null);
        return _ayahCache[key] = null;
      }
      throw Exception('تعذّر تحميل ${kind.title} (${r.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    final raw = (decoded is Map ? decoded['content'] as String? : null)?.trim();
    final text = (raw == null || raw.isEmpty) ? null : raw;
    await InsightCache.write(slug, surah, ayah, text);
    return _ayahCache[key] = text;
  }

  /// Every word of the ayah with what [kind] says about it. Words the
  /// work has no entry for are simply absent from the list.
  ///
  /// Cached to disk on first read, for the same reason as [ayahText]:
  /// the API has no bulk endpoint for word data, so reading is the only
  /// way this content ever gets onto the device.
  static Future<List<WordInsight>> words(
      InsightKind kind, int surah, int ayah) {
    final slug = kind._wordSlug;
    final key = _key(slug, surah, ayah);
    final cached = _wordCache[key];
    if (cached != null) return Future.value(cached);

    // Block body, not an arrow — see the note in [ayahText].
    return _wordPending[key] ??= _fetchWords(kind, slug, key, surah, ayah)
        .whenComplete(() {
      _wordPending.remove(key);
    });
  }

  static Future<List<WordInsight>> _fetchWords(InsightKind kind, String slug,
      String key, int surah, int ayah) async {
    final (onDisk, stored) = await InsightCache.read(slug, surah, ayah);
    if (onDisk) return _wordCache[key] = _parseWords(stored);

    final r = await http
        .get(Uri.parse(
            '$_base/word/$slug/$surah/$ayah/1/$_maxWordsPerAyah'))
        .timeout(_timeout);
    if (r.statusCode != 200) {
      if (r.statusCode == 404) {
        await InsightCache.write(slug, surah, ayah, const []);
        return _wordCache[key] = const [];
      }
      throw Exception('تعذّر تحميل ${kind.title} (${r.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    // A one-word range answers with a bare object rather than a list.
    final payload = decoded is List ? decoded : [decoded];
    await InsightCache.write(slug, surah, ayah, payload);
    return _wordCache[key] = _parseWords(payload);
  }

  static List<WordInsight> _parseWords(dynamic payload) {
    if (payload is! List) return const [];
    return [
      for (final e in payload)
        if (e is Map && e['word_number'] is int)
          WordInsight.fromJson(e.cast<String, dynamic>()),
    ]..sort((a, b) => a.wordNumber.compareTo(b.wordNumber));
  }

  /// Bytes the study cache occupies on device, for the settings screen.
  /// Reports 0 rather than failing if the store can't be read — this
  /// only drives a label and a button's enabled state.
  static Future<int> cachedSizeBytes() async {
    try {
      return await InsightFileStorage.cacheSizeBytes();
    } catch (_) {
      return 0;
    }
  }

  /// Whether this platform keeps a cache at all (false on web).
  static bool get supportsCache => InsightFileStorage.supportsCache;

  /// Drops everything read so far, on disk and in memory.
  static Future<void> clearCache() async {
    _wordCache.clear();
    _ayahCache.clear();
    _wordPending.clear();
    _ayahPending.clear();
    await InsightCache.clear();
  }

  /// The ayah's words in order, for the tappable token strip.
  ///
  /// The API's own segmentation is the source of truth — splitting the
  /// app's Mushaf text on spaces would drift from the word numbering
  /// these projects are keyed by.
  ///
  /// All four books are asked at once and merged, because none of them
  /// covers every word of every ayah and there is no count to check a
  /// single book against. That costs nothing extra: the tabs need all
  /// four anyway, and [words] caches, so their own fetches are then
  /// served from memory. A book that fails contributes nothing rather
  /// than emptying the strip.
  static Future<List<String>> wordTokens(int surah, int ayah) async {
    final fetched = await Future.wait([
      for (final kind in InsightKind.values)
        words(kind, surah, ayah)
            .onError((_, __) => const <WordInsight>[]),
    ]);
    // Earlier books win a position: InsightKind.values leads with the
    // i'rab, the most complete word-level work.
    final byNumber = <int, String>{};
    for (final list in fetched) {
      for (final w in list) {
        if (w.word.isNotEmpty) byNumber.putIfAbsent(w.wordNumber, () => w.word);
      }
    }
    final numbers = byNumber.keys.toList()..sort();
    return [for (final n in numbers) byNumber[n]!];
  }

  // -------------------------------------------------------------
  // Shaping the works' raw text for display
  // -------------------------------------------------------------

  /// Word entries usually repeat the word as a `{كلمة}:` prefix. The
  /// card already shows it as a heading, so it is dropped.
  static String stripWordPrefix(String content) => content
      .replaceFirst(RegExp(r'^\s*[{﴿][^}﴾]*[}﴾]\s*:\s*'), '')
      .trim();

  /// The i'rab volume opens each ayah with the ayah itself wrapped in
  /// braces, then one `word: parse` line per word. The ayah card
  /// already carries the text, so that opening line is dropped and the
  /// rest is returned line by line.
  static List<String> eerabLines(String content) {
    final lines = content
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isNotEmpty && lines.first.startsWith('{')) lines.removeAt(0);
    return lines;
  }

  /// Splits a qira'at entry on its `---{عند الوصل}---` markers.
  static List<QiraatSegment> qiraatSegments(String content) {
    final parts = <QiraatSegment>[];
    final re = RegExp(r'-{2,}\{([^}]*)\}-{2,}');
    var last = 0;
    String? pendingLabel;
    for (final m in re.allMatches(content)) {
      final chunk = content.substring(last, m.start).trim();
      if (chunk.isNotEmpty) {
        parts.add(QiraatSegment(label: pendingLabel, text: chunk));
      }
      pendingLabel = m.group(1)!.trim();
      last = m.end;
    }
    final tail = content.substring(last).trim();
    if (tail.isNotEmpty) {
      parts.add(QiraatSegment(label: pendingLabel, text: tail));
    }
    return parts;
  }

  /// True when a qira'at entry says anything beyond "the readers agree
  /// here". Most words in the Quran carry no variant at all, so the
  /// tab hides those by default and this is the test it uses.
  static bool qiraatHasVariance(String content) {
    for (final part in qiraatSegments(content)) {
      final t = part.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isEmpty) continue;
      if (!t.startsWith('لا خلاف')) return true;
    }
    return false;
  }

  /// All four books' entries for a single word, for the word sheet.
  /// Missing entries are omitted from the map.
  static Future<Map<InsightKind, String>> forWord(
      int surah, int ayah, int wordNumber) async {
    final out = <InsightKind, String>{};
    for (final kind in InsightKind.values) {
      try {
        final list = await words(kind, surah, ayah);
        for (final w in list) {
          if (w.wordNumber == wordNumber && w.content.isNotEmpty) {
            out[kind] = w.content;
            break;
          }
        }
      } catch (_) {
        // Skip a book that failed; the others still render.
      }
    }
    return out;
  }
}

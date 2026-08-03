import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'quran_service.dart';

/// A run of one or more consecutive ayahs that a mutashabiha compares.
/// Most are a single ayah; a few span two or three, because the
/// resemblance only shows across the pair.
typedef MutashabihaRun = List<int>;

/// One mutashabiha as seen from a particular ayah: the run that ayah
/// belongs to, and the runs elsewhere in the Quran it resembles.
class Mutashabiha {
  /// Global ayah numbers (1-6236) of the run the queried ayah is in.
  final MutashabihaRun current;

  /// The other runs of the same mutashabiha, in Mushaf order.
  final List<MutashabihaRun> similar;

  /// The dataset's hint that the resemblance only becomes clear with
  /// the following ayah in view.
  final bool needsContext;

  const Mutashabiha({
    required this.current,
    required this.similar,
    required this.needsContext,
  });
}

/// Mutashabihat (المتشابهات اللفظية) — passages elsewhere in the Quran
/// whose wording closely resembles the ayah being read, the pairs that
/// most often trip up huffaz.
///
/// Backed by a bundled dataset (assets/quran/mutashabihat.json), so
/// this tab works offline. The dataset is transcribed group by group
/// from a published mutashabihat reference (the scanned pages Omar
/// supplies), NOT generated or scraped — an earlier version used the
/// open Waqar144/Quran_Mutashabihat_Data list, which turned out to be
/// one individual's informal hifz-confusion notes rather than a
/// scholarly index, and was inaccurate against the reference book on
/// spot-check (2026-08-02). Every entry here must be independently
/// verified against the bundled Quran text — by matching the ayah's
/// distinctive WORDING, not by trusting a printed/photographed ayah
/// number, which is easy to misread — before being added. Container
/// keys in the JSON name the source book page for traceability
/// (`book_p2` = page 2), not a juz; [_ensureLoaded] does not depend on
/// the key meaning anything, so this is free to extend however new
/// pages are best organized.
///
/// Coverage is intentionally partial and grows only as pages are
/// transcribed — there is no complete open dataset for this to start
/// from wholesale.
class MutashabihatService {
  /// Global ayah number -> the mutashabihat it takes part in. Built
  /// once on first use.
  static Map<int, List<Mutashabiha>>? _index;

  /// Expands a printed reference — `"2:34"` or `"7:11-12"` — into the
  /// global ayah numbers it covers. Out-of-range ayahs are dropped
  /// rather than faked, so a typo in the transcription shrinks a run
  /// instead of pointing at the wrong verse.
  static Future<MutashabihaRun> _expand(String ref) async {
    final colon = ref.indexOf(':');
    if (colon < 0) return const [];
    final surah = int.tryParse(ref.substring(0, colon).trim());
    if (surah == null) return const [];

    final rest = ref.substring(colon + 1).trim();
    final dash = rest.indexOf('-');
    final from = int.tryParse(dash < 0 ? rest : rest.substring(0, dash));
    final to =
        dash < 0 ? from : int.tryParse(rest.substring(dash + 1));
    if (from == null || to == null || to < from) return const [];

    final out = <int>[];
    for (var ayah = from; ayah <= to; ayah++) {
      final global = await QuranService.globalAyahNumber(surah, ayah);
      if (global > 0) out.add(global);
    }
    return out;
  }

  static Future<void> _ensureLoaded() async {
    if (_index != null) return;
    final raw =
        await rootBundle.loadString('assets/quran/mutashabihat.json');
    final Map<String, dynamic> doc = jsonDecode(raw);

    final index = <int, List<Mutashabiha>>{};
    for (final g in (doc['groups'] as List)) {
      final runs = <MutashabihaRun>[];
      for (final ref in (g['runs'] as List)) {
        final run = await _expand(ref as String);
        if (run.isNotEmpty) runs.add(run);
      }
      // The book prints some rows with a single occurrence (e.g. المص,
      // unique to Al-A'raf). There is nothing to compare those with, so
      // they are carried in the JSON for faithfulness but not indexed.
      if (runs.length < 2) continue;

      final needsContext = g['context'] == true;
      for (var i = 0; i < runs.length; i++) {
        final entry = Mutashabiha(
          current: runs[i],
          // The book lists a row's occurrences side by side; a reader
          // sitting on ANY of them wants the others, so the row is
          // indexed from every member rather than one-way.
          similar: [
            for (var j = 0; j < runs.length; j++)
              if (j != i) runs[j],
          ]..sort((a, b) => a.first.compareTo(b.first)),
          needsContext: needsContext,
        );
        // Every ayah of a multi-ayah run is an entry point, so opening
        // the second ayah of a pair finds it too.
        for (final ayah in runs[i]) {
          (index[ayah] ??= []).add(entry);
        }
      }
    }
    _index = index;
  }

  /// Every mutashabiha the given GLOBAL ayah number takes part in.
  /// Empty when the dataset lists none — the common case, and not an
  /// error.
  static Future<List<Mutashabiha>> forGlobalAyah(int globalAyah) async {
    await _ensureLoaded();
    return _index![globalAyah] ?? const [];
  }
}

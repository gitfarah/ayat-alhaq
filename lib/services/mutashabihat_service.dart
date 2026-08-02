import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

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
/// Backed by a bundled dataset (assets/quran/mutashabihat.json, from
/// Waqar144/Quran_Mutashabihat_Data, based on the work of Qari Idrees
/// Al-Asim), so this tab works offline. The dataset is deliberately a
/// curated list of the confusable pairs rather than every textual
/// repetition in the Quran.
class MutashabihatService {
  /// Global ayah number -> the mutashabihat it takes part in. Built
  /// once on first use.
  static Map<int, List<Mutashabiha>>? _index;

  static MutashabihaRun _run(dynamic ayah) =>
      ayah is List ? ayah.cast<int>() : <int>[ayah as int];

  static Future<void> _ensureLoaded() async {
    if (_index != null) return;
    final raw =
        await rootBundle.loadString('assets/quran/mutashabihat.json');
    final Map<String, dynamic> byJuz = jsonDecode(raw);

    final index = <int, List<Mutashabiha>>{};
    for (final entries in byJuz.values) {
      for (final e in (entries as List)) {
        // The dataset stores one source run plus its matches; a reader
        // sitting on ANY of them wants to see all the others, so the
        // one-way record is flattened into a symmetric group here.
        final runs = <MutashabihaRun>[
          _run(e['src']['ayah']),
          for (final m in (e['muts'] as List)) _run(m['ayah']),
        ];
        final needsContext = e['ctx'] != null;

        for (var i = 0; i < runs.length; i++) {
          final entry = Mutashabiha(
            current: runs[i],
            similar: [
              for (var j = 0; j < runs.length; j++)
                if (j != i) runs[j],
            ]..sort((a, b) => a.first.compareTo(b.first)),
            needsContext: needsContext,
          );
          // Every ayah of a multi-ayah run is an entry point, so
          // long-pressing the second ayah of a pair finds it too.
          for (final ayah in runs[i]) {
            (index[ayah] ??= []).add(entry);
          }
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

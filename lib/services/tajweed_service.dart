import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'quran_service.dart';

/// One run of ayah text that shares a single tajweed rule (or none).
class TajweedSegment {
  /// Rule id, e.g. `ikhafa`; empty for ordinary text.
  final String rule;
  final String text;
  const TajweedSegment(this.rule, this.text);

  bool get isPlain => rule.isEmpty;
}

/// Serves per-ayah tajweed colouring from a bundled asset, so it works
/// fully offline like the rest of the Quran text.
///
/// The data is the Uthmani script with per-letter rule markup; the app
/// swaps it in for the plain text when the user turns tajweed on.
class TajweedService {
  /// "surah:ayah" -> flat [rule, text, rule, text, ...] pairs.
  static Map<String, List<dynamic>>? _data;

  static bool get isLoaded => _data != null;

  /// Colours follow the convention used by printed tajweed Mushafs.
  static const Map<String, Color> ruleColors = {
    // Elongations (madd) — blues, deepening with obligation.
    'madda_normal': Color(0xFF537FFF),
    'madda_permissible': Color(0xFF4050FF),
    'madda_obligatory': Color(0xFF2144C1),
    'madda_necessary': Color(0xFF000EBC),
    // Nasalisation and assimilation — greens.
    'ghunnah': Color(0xFFFF7E1E),
    'idgham_ghunnah': Color(0xFF169200),
    'idgham_wo_ghunnah': Color(0xFF169200),
    'idgham_shafawi': Color(0xFF58B800),
    // Concealment — purples.
    'ikhafa': Color(0xFF9400A8),
    'ikhafa_shafawi': Color(0xFFD500B7),
    // Conversion.
    'iqlab': Color(0xFF26BFFD),
    // Echo (qalqalah) — red.
    'qalaqah': Color(0xFFDD0008),
    // Not pronounced / connecting hamza / sun laam — grey.
    'ham_wasl': Color(0xFFAAAAAA),
    'laam_shamsiyah': Color(0xFFAAAAAA),
    'slnt': Color(0xFFAAAAAA),
    'idgham_mutajanisayn': Color(0xFFA1A1A1),
    'idgham_mutaqaribayn': Color(0xFFA1A1A1),
  };

  /// Human-readable rule names for the settings legend.
  static const Map<String, Map<String, String>> ruleNames = {
    'ar': {
      'ghunnah': 'غنّة',
      'qalaqah': 'قلقلة',
      'ikhafa': 'إخفاء',
      'ikhafa_shafawi': 'إخفاء شفوي',
      'idgham_ghunnah': 'إدغام بغنّة',
      'idgham_wo_ghunnah': 'إدغام بغير غنّة',
      'idgham_shafawi': 'إدغام شفوي',
      'iqlab': 'إقلاب',
      'madda_normal': 'مدّ طبيعي',
      'madda_permissible': 'مدّ جائز',
      'madda_obligatory': 'مدّ واجب',
      'madda_necessary': 'مدّ لازم',
      'ham_wasl': 'همزة وصل',
      'laam_shamsiyah': 'لام شمسية',
      'slnt': 'حرف لا يُنطق',
    },
    'en': {
      'ghunnah': 'Ghunnah',
      'qalaqah': 'Qalqalah',
      'ikhafa': 'Ikhfa',
      'ikhafa_shafawi': 'Ikhfa Shafawi',
      'idgham_ghunnah': 'Idgham with Ghunnah',
      'idgham_wo_ghunnah': 'Idgham without Ghunnah',
      'idgham_shafawi': 'Idgham Shafawi',
      'iqlab': 'Iqlab',
      'madda_normal': 'Natural prolongation',
      'madda_permissible': 'Permissible prolongation',
      'madda_obligatory': 'Obligatory prolongation',
      'madda_necessary': 'Necessary prolongation',
      'ham_wasl': 'Connecting hamza',
      'laam_shamsiyah': 'Sun laam',
      'slnt': 'Silent letter',
    },
    'de': {
      'ghunnah': 'Ghunnah (Nasalierung)',
      'qalaqah': 'Qalqalah',
      'ikhafa': 'Ikhfa',
      'ikhafa_shafawi': 'Ikhfa Shafawi',
      'idgham_ghunnah': 'Idgham mit Ghunnah',
      'idgham_wo_ghunnah': 'Idgham ohne Ghunnah',
      'idgham_shafawi': 'Idgham Shafawi',
      'iqlab': 'Iqlab',
      'madda_normal': 'Natürliche Dehnung',
      'madda_permissible': 'Zulässige Dehnung',
      'madda_obligatory': 'Pflicht-Dehnung',
      'madda_necessary': 'Notwendige Dehnung',
      'ham_wasl': 'Verbindungs-Hamza',
      'laam_shamsiyah': 'Sonnen-Lam',
      'slnt': 'Stummer Buchstabe',
    },
  };

  /// The rules shown in the settings legend, in teaching order.
  static const List<String> legendOrder = [
    'ghunnah',
    'qalaqah',
    'ikhafa',
    'ikhafa_shafawi',
    'idgham_ghunnah',
    'idgham_wo_ghunnah',
    'idgham_shafawi',
    'iqlab',
    'madda_normal',
    'madda_permissible',
    'madda_obligatory',
    'madda_necessary',
    'ham_wasl',
    'laam_shamsiyah',
    'slnt',
  ];

  static Future<void> load() async {
    if (_data != null) return;
    try {
      final raw = await rootBundle.loadString('assets/quran/tajweed.json');
      final Map<String, dynamic> decoded = jsonDecode(raw);
      _data = decoded.map((k, v) => MapEntry(k, v as List<dynamic>));
    } catch (_) {
      // Reading must never break because the colouring data is missing —
      // the reader simply falls back to plain text.
      _data = const {};
    }
  }

  /// Whether [cp] is an Arabic combining mark — a vowel sign, a Quranic
  /// annotation, or the superscript alef. These have no width of their
  /// own and must stay attached to the letter they sit on.
  static bool _isCombiningMark(int cp) =>
      (cp >= 0x064B && cp <= 0x065F) || // tashkeel
      cp == 0x0670 || //                   superscript alef
      (cp >= 0x06D6 && cp <= 0x06DC) || // small high signs
      (cp >= 0x06DF && cp <= 0x06E8) ||
      (cp >= 0x06EA && cp <= 0x06ED);

  /// Cleans a raw segment from the source data.
  ///
  /// That data is scraped markup and is not quite the Uthmani text the
  /// rest of the app uses: 67 ayahs still carry unclosed `<tajweed>`
  /// tags, and it spells the superscript alef and the alef maqsura with
  /// codepoints the Mushaf font shapes differently. Left alone, the tags
  /// print literally and the odd letters break the joining of the word
  /// they sit in.
  static String _normalize(String s) => QuranService.fixForQuranFont(s
      .replaceAll(RegExp(r'</?tajweed[^>]*>'), '')
      .replaceAll('‌', '') //          ZWNJ — blocks Arabic joining
      .replaceAll('ٲ', 'ٰ') //    alef w/ wavy hamza -> superscript alef
      .replaceAll('ٮ', 'ى')); //  dotless beh -> alef maqsura

  /// Tajweed-coloured segments for an ayah, or null when unavailable
  /// (asset missing, or the ayah isn't in the data).
  static List<TajweedSegment>? segments(int surah, int ayah) {
    final flat = _data?['$surah:$ayah'];
    if (flat == null || flat.isEmpty) return null;
    final out = <TajweedSegment>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      final rule = flat[i] as String;
      var text = _normalize(flat[i + 1] as String);
      if (text.isEmpty) continue;

      // A rule can start between a letter and the mark sitting on it.
      // Split across spans, that mark has no base to attach to and the
      // shaper draws it on a dotted circle. Pull the letter it belongs
      // to forward into this span instead of pushing the mark back —
      // the carrying letter is what a printed tajweed Mushaf colours.
      if (out.isNotEmpty && _isCombiningMark(text.codeUnitAt(0))) {
        final prev = out.removeLast();
        var cut = prev.text.length - 1;
        while (cut > 0 && _isCombiningMark(prev.text.codeUnitAt(cut))) {
          cut--;
        }
        text = prev.text.substring(cut) + text;
        if (cut > 0) out.add(TajweedSegment(prev.rule, prev.text.substring(0, cut)));
      }
      out.add(TajweedSegment(rule, text));
    }
    return out.isEmpty ? null : out;
  }

  static Color? colorFor(String rule) => ruleColors[rule];

  @visibleForTesting
  static bool isCombiningMark(int cp) => _isCombiningMark(cp);
}

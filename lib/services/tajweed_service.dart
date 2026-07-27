import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show rootBundle;

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

  /// Tajweed-coloured segments for an ayah, or null when unavailable
  /// (asset missing, or the ayah isn't in the data).
  static List<TajweedSegment>? segments(int surah, int ayah) {
    final flat = _data?['$surah:$ayah'];
    if (flat == null || flat.isEmpty) return null;
    final out = <TajweedSegment>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      final rule = flat[i] as String;
      final text = flat[i + 1] as String;
      if (text.isEmpty) continue;
      out.add(TajweedSegment(rule, text));
    }
    return out.isEmpty ? null : out;
  }

  static Color? colorFor(String rule) => ruleColors[rule];
}

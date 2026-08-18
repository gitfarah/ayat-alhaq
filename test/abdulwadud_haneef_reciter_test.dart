// عبد الودود حنيف — added the same way عبد الرشيد صوفي already works:
// a bundled per-surah audio_url map, no per-ayah segment data at all
// (the export's own segments.json came back empty). These tests pin
// the one thing that's actually ours to get right offline — the
// bundled data is complete and well-formed — since the playback
// special-casing itself (snap to the surah's first ayah, advance a
// whole surah at a time) mirrors code already covered by existing
// behaviour for the other whole-surah reciter.
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('is offered as a reciter', () {
    expect(
        QuranAudioService.reciters.containsKey('qul.abdulwadudhaneef'), isTrue);
  });

  test('the bundled surah map covers all 114 surahs with a real URL',
      () async {
    final raw = await rootBundle
        .loadString('assets/quran/abdulwadud_haneef_surahs.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    expect(data.length, 114);
    for (var surah = 1; surah <= 114; surah++) {
      final entry = data['$surah'] as Map<String, dynamic>?;
      expect(entry, isNotNull, reason: 'surah $surah is missing');
      expect(entry!['surah_number'], surah);
      final url = entry['audio_url'] as String?;
      expect(url, isNotNull);
      expect(url, startsWith('https://'));
      expect(entry['duration'], greaterThan(0),
          reason: 'surah $surah has a zero/negative duration');
    }
  });
}

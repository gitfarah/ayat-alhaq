// The Somali translation (so.abduh) is the one edition served from a
// BUNDLED file (assets/quran/translation_so_abduh.json) rather than
// fetched live from alquran.cloud — every other translation depends on
// the network the way the app's own Arabic text never has to. These
// tests run with no network available at all (the standard `flutter
// test` sandbox), so a passing translation here IS the proof it works
// offline, not just an assertion about it.
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/quran_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('so.abduh is offered as a translation edition', () {
    expect(QuranService.translationEditions.containsKey('so.abduh'), isTrue);
  });

  test('Al-Fatiha comes back fully translated, offline, no network hit',
      () async {
    final ayahs =
        await QuranService.getSurahAyahs(1, translationEdition: 'so.abduh');
    expect(ayahs.length, 7);
    for (final a in ayahs) {
      expect(a.translation, isNotNull,
          reason: 'ayah ${a.numberInSurah} has no Somali translation');
      expect(a.translation!.trim(), isNotEmpty);
    }
  });

  test('An-Nas (the last surah) is translated to its last ayah', () async {
    final ayahs =
        await QuranService.getSurahAyahs(114, translationEdition: 'so.abduh');
    expect(ayahs.length, 6);
    expect(ayahs.last.translation, isNotNull);
  });

  test('a run of consecutive surahs is translated with no gaps', () async {
    // Guards against the file's key ORDER being mistaken for coverage —
    // the bundled JSON is not stored in surah:ayah order, and reading
    // only a short prefix of it once looked like several ayahs of
    // Al-Fatiha were simply missing when they were not.
    for (final surah in [2, 3, 18, 36, 55]) {
      final ayahs = await QuranService.getSurahAyahs(surah,
          translationEdition: 'so.abduh');
      final missing =
          ayahs.where((a) => a.translation == null).map((a) => a.numberInSurah);
      expect(missing, isEmpty,
          reason: 'surah $surah is missing ayahs: $missing');
    }
  });

  test('no translationEdition means no translation, same as ever', () async {
    final ayahs = await QuranService.getSurahAyahs(1);
    expect(ayahs.every((a) => a.translation == null), isTrue);
  });
}

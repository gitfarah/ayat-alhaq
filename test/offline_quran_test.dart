import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/quran_service.dart';
import 'package:quran_app_v1/widgets/surah_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bundled offline Quran asset', () {
    test('loads all 114 surahs without network', () async {
      final surahs = await QuranService.getAllSurahs();
      expect(surahs.length, 114);
      // Names are fully vocalized and carry the سُورَةُ prefix.
      expect(surahs.first.name, contains('سُورَةُ'));
      expect(surahs.first.number, 1);
      expect(surahs.last.numberOfAyahs, 6);
    });

    test('surah ayahs come from the asset with correct metadata',
        () async {
      final fatiha = await QuranService.getSurahAyahs(1);
      expect(fatiha.length, 7);
      expect(fatiha.first.number, 1); // global numbering starts at 1
      expect(fatiha.first.page, 1);

      final baqarah = await QuranService.getSurahAyahs(2);
      expect(baqarah.length, 286);
      expect(baqarah.first.number, 8); // global: after Al-Fatiha's 7
      // Basmala must be stripped from the first ayah (Mushaf convention).
      expect(baqarah.first.text.startsWith('بِسْمِ'), isFalse);

      final nas = await QuranService.getSurahAyahs(114);
      expect(nas.last.number, 6236); // the Quran's final ayah
      expect(nas.last.page, 604);
    });

    test('single ayah text lookup works offline', () async {
      final text = await QuranService.getAyahText(112, 1);
      expect(text, contains('أَحَد'));
    });

    test('search works offline over bare letters', () async {
      final results = await QuranService.searchAyahs('قل هو الله');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.surahNumber == 112), isTrue);
    });
  });

  testWidgets('SurahFrame renders its ornamental band', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SurahFrame(title: 'سُورَةُ الإخلاص', isDark: false),
      ),
    ));
    expect(find.text('سُورَةُ الإخلاص'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

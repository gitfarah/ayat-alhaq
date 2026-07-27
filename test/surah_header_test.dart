import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/surah_header_service.dart';
import 'package:quran_app_v1/widgets/surah_banner_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every riwayah breaks its lines differently, so each ships its own
  // measured set and each must be complete.
  for (final edition in ['hafs', 'warsh', 'qalon']) {
    group('Surah header bands ($edition)', () {
      setUpAll(() async => SurahHeaderService.load(edition));

      /// Every band in the shipped asset, flattened.
      List<SurahHeaderBand> allBands() {
        final out = <SurahHeaderBand>[];
        for (var p = 1; p <= 604; p++) {
          out.addAll(SurahHeaderService.forPage(p, edition: edition));
        }
        return out;
      }

      test('covers every surah that needs a drawn frame', () {
        // Surahs 1 and 2 open on the illuminated pages 1-2, which the app
        // frames itself, so they are intentionally not in the asset.
        final surahs = allBands().map((b) => b.surah).toSet();
        final missing = [
          for (var s = 3; s <= 114; s++)
            if (!surahs.contains(s)) s
        ];
        expect(missing, isEmpty, reason: 'surahs without a header band');
      });

      test('each surah appears exactly once', () {
        final counts = <int, int>{};
        for (final b in allBands()) {
          counts[b.surah] = (counts[b.surah] ?? 0) + 1;
        }
        expect(counts.values.every((c) => c == 1), isTrue,
            reason: 'a surah has more than one header band');
      });

      test('bands sit inside the page with a sane height', () {
        for (final b in allBands()) {
          expect(b.top, greaterThanOrEqualTo(0));
          expect(b.bottom, lessThanOrEqualTo(550));
          expect(b.bottom, greaterThan(b.top));
          expect(b.height, inInclusiveRange(8, 60));
          expect(b.page, inInclusiveRange(3, 604));
        }
      });

      test('page 604 carries the three closing surahs', () {
        final bands = SurahHeaderService.forPage(604, edition: edition);
        expect(bands.map((b) => b.surah).toSet(), {112, 113, 114});
      });

      test('a page with no surah start has no bands', () {
        // Al-Baqarah runs across page 10 without any surah starting there.
        expect(SurahHeaderService.forPage(10, edition: edition), isEmpty);
      });
    });
  }

  testWidgets('banner painter draws without error', (tester) async {
    await SurahHeaderService.load();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 345,
          height: 550,
          child: CustomPaint(
            painter: SurahBannerPainter(
              bands: SurahHeaderService.forPage(604),
              scaleX: 1,
              scaleY: 1,
              isDark: false,
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}

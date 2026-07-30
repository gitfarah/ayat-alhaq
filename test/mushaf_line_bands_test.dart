import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/mushaf_svg_service.dart';
import 'package:quran_app_v1/widgets/mushaf_page_furniture.dart';
import 'package:quran_app_v1/widgets/mushaf_spread_page.dart';

/// The real ayah polygons of Hafs page 321 (surah Ta-Ha, 15 full lines),
/// straight from quranpedia's page JSON — including the rounding jitter
/// that makes one ayah call a boundary 117.77 and its neighbour 117.81,
/// which is the whole reason the measurement clusters near-equal edges.
const _page321 = [
  (20, 126, 'M 0.0 10.18 L 345.0 10.18 L 345.0 46.18 L 0.0 46.18 Z'),
  (
    20,
    127,
    'M 0.0 46.18 L 345.0 46.18 L 345.0 82.0 L 0.0 82.0 Z '
        'M 249.67 82.0 L 345.0 82.0 L 345.0 117.81 L 249.67 117.81 Z'
  ),
  (
    20,
    128,
    'M 0.0 82.0 L 249.67 82.0 L 249.67 117.77 L 0.0 117.77 Z '
        'M 0.0 117.77 L 345.0 117.77 L 345.0 153.72 L 0.0 153.72 Z'
  ),
  (20, 129, 'M 0.0 153.72 L 345.0 153.72 L 345.0 189.72 L 0.0 189.72 Z'),
  (
    20,
    130,
    'M 0.0 189.61 L 345.0 189.61 L 345.0 225.61 L 0.0 225.61 Z '
        'M 0.0 225.61 L 345.0 225.61 L 345.0 261.11 L 0.0 261.11 Z '
        'M 279.9 261.11 L 345.0 261.11 L 345.0 297.11 L 279.9 297.11 Z'
  ),
  (
    20,
    131,
    'M 0.0 261.11 L 279.9 261.11 L 279.9 297.07 L 0.0 297.07 Z '
        'M 60.35 297.07 L 345.0 297.07 L 345.0 333.03 L 60.35 333.03 Z'
  ),
  (
    20,
    132,
    'M 0.0 297.07 L 60.35 297.07 L 60.35 333.03 L 0.0 333.03 Z '
        'M 0.0 333.03 L 345.0 333.03 L 345.0 368.71 L 0.0 368.71 Z '
        'M 267.49 368.71 L 345.0 368.71 L 345.0 404.71 L 267.49 404.71 Z'
  ),
  (
    20,
    133,
    'M 0.0 368.71 L 267.49 368.71 L 267.49 404.62 L 0.0 404.62 Z '
        'M 147.71 404.62 L 345.0 404.62 L 345.0 440.53 L 147.71 440.53 Z'
  ),
  (
    20,
    134,
    'M 0.0 404.62 L 147.71 404.62 L 147.71 440.53 L 0.0 440.53 Z '
        'M 0.0 440.53 L 345.0 440.53 L 345.0 476.22 L 0.0 476.22 Z '
        'M 132.77 476.22 L 345.0 476.22 L 345.0 512.22 L 132.77 512.22 Z'
  ),
  (
    20,
    135,
    'M 0.0 476.22 L 132.77 476.22 L 132.77 512.16 L 0.0 512.16 Z '
        'M 0.0 512.16 L 345.0 512.16 L 345.0 548.1 L 0.0 548.1 Z'
  ),
];

MushafPageData _pageData(List<(int, int, String)> regions) => MushafPageData(
      pageNumber: 321,
      svgContent: '',
      viewBoxWidth: 345,
      viewBoxHeight: 550,
      ayahRegions: [
        for (final (surah, ayah, polygon) in regions)
          AyahHitRegion.fromJson({
            'surahNumber': surah,
            'ayahNumber': ayah,
            'x': 0.0,
            'y': 0.0,
            'polygon': polygon,
          }),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mushaf line bands', () {
    test('finds every printed line, plus the head and foot margins', () {
      final bands = MushafLineBands.measure(_pageData(_page321));
      expect(bands, isNotNull);

      // 15 lines of script, with the top margin above the first line and
      // the foot margin below the last one as bands of their own.
      expect(bands!.bandCount, 17);
      expect(bands.boundaries.first, 0);
      expect(bands.boundaries.last, 550);

      // Ascending, with no boundary repeated: a duplicate would render as
      // a zero-height strip and silently swallow a line.
      for (var i = 1; i < bands.boundaries.length; i++) {
        expect(bands.boundaries[i], greaterThan(bands.boundaries[i - 1]));
      }
    });

    test('collapses boundaries that differ only by rounding', () {
      final bands = MushafLineBands.measure(_pageData(_page321))!;
      // 117.77 and 117.81 are the same printed line boundary.
      final near = bands.boundaries.where((y) => (y - 117.79).abs() < 1).length;
      expect(near, 1);
    });

    test('each band moves down by one more gap than the band above', () {
      final bands = MushafLineBands.measure(_pageData(_page321))!.withGap(4);
      expect(bands.offsetFor(bands.boundaries[0]), 0);
      expect(bands.offsetFor(bands.boundaries[1] + 1), 4);
      expect(bands.offsetFor(bands.boundaries[2] + 1), 8);
      expect(bands.extraHeight, 4 * 16);
    });

    test('a tap on spread text lands back on the line it was printed on',
        () {
      final bands = MushafLineBands.measure(_pageData(_page321))!.withGap(4);
      // Walk the middle of every band through the spread and back.
      for (var k = 0; k < bands.bandCount; k++) {
        final middle =
            (bands.boundaries[k] + bands.boundaries[k + 1]) / 2;
        final spread = middle + bands.offsetFor(middle);
        expect(bands.unmap(spread), closeTo(middle, 0.001),
            reason: 'band $k did not round-trip');
      }
    });

    test('a page whose regions describe no lines is left unspread', () {
      // Guards the fallback: without it a page with odd data would be
      // sliced into nonsense instead of simply drawn as printed.
      expect(MushafLineBands.measure(_pageData(const [])), isNull);
      expect(
          MushafLineBands.measure(_pageData(const [
            (20, 1, 'M 0.0 10.0 L 345.0 10.0 L 345.0 46.0 L 0.0 46.0 Z'),
          ])),
          isNull);
    });
  });

  group('Mushaf page furniture', () {
    test('page numbers are written in Arabic-Indic digits', () {
      expect(arabicDigits(1), '١');
      expect(arabicDigits(321), '٣٢١');
      expect(arabicDigits(604), '٦٠٤');
    });

    testWidgets('the number sits on the outer edge of the leaf',
        (tester) async {
      for (final (page, alignment) in [
        (321, Alignment.centerRight), // recto — right-hand leaf
        (322, Alignment.centerLeft), // verso — left-hand leaf
      ]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: MushafPageFooter(page: page, isDark: false),
          ),
        ));
        final align = tester.widget<Align>(find
            .descendant(
                of: find.byType(MushafPageFooter), matching: find.byType(Align))
            .first);
        expect(align.alignment, alignment, reason: 'page $page');
        expect(find.text(arabicDigits(page)), findsOneWidget);
      }
    });

    testWidgets('the running head names the surah, the juz and the hizb',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MushafPageHeader(page: 321, isDark: false)),
      ));
      expect(find.text('طه'), findsOneWidget);
      expect(find.text('الجزء ١٦، الحزب ٣٢'), findsOneWidget);
    });

    testWidgets('the ornamental frame paints without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            for (final dark in [false, true])
              for (final page in [1, 321, 604])
                MushafPageBadge(
                    page: page, isDark: dark, pointLeft: page.isEven),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/widgets/mushaf_page_furniture.dart';
import 'package:quran_app_v1/widgets/mushaf_spread_page.dart';

/// The page artwork is one enormous vector path, so the only way to open
/// up its line spacing is to redraw the raster. Doing that by CUTTING it
/// into one strip per line clipped every alif and kasra that reached
/// into a neighbouring line — the script simply does not stay inside the
/// ayah boxes. These tests pin down the replacement: a continuous
/// mapping that stretches only the rows between the lines.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A page profile: 15 lines of ink separated by 6-row gaps, with
  /// margins top and bottom. Each row carries a plausible ink COUNT —
  /// how many sampled columns of it are not clear.
  List<int> syntheticPage({int gapInk = 0}) {
    final ink = List<int>.filled(600, gapInk);
    for (var y = 0; y < 20; y++) {
      ink[y] = 0; // head margin
    }
    for (var y = 20 + 15 * 38 - 6; y < 600; y++) {
      ink[y] = 0; // foot margin
    }
    for (var line = 0; line < 15; line++) {
      final top = 20 + line * 38;
      for (var y = top; y < top + 32; y++) {
        ink[y] = 40;
      }
    }
    return ink;
  }

  /// The real thing: per-row ink counts measured off rasterised Hafs
  /// pages, exactly as [MushafSpreadArtwork] measures them on the device
  /// (1080 px wide, every third column, alpha > 40).
  final fixtures = jsonDecode(
      File('test/fixtures/hafs_ink_profiles.json').readAsStringSync()) as Map;
  List<int> realPage(String page) =>
      (fixtures[page]['inkPerRow'] as List).cast<int>();

  group('Line-gap measurement', () {
    test('finds the gaps between lines, not the page margins', () {
      final runs = MushafPageStretch.gapRunsOf(syntheticPage())!;
      // 15 lines leave 14 interior gaps; margins are excluded.
      expect(runs.length, 14 * 2);
      // The first gap starts after the first line's ink, not at the top.
      expect(runs.first, greaterThan(20 / 600));
    });

    test('a page with no gaps is left alone', () {
      expect(MushafPageStretch.gapRunsOf(List<int>.filled(600, 40)), isNull);
      expect(MushafPageStretch.gapRunsOf(List<int>.filled(600, 0)), isNull);
    });

    test('a gap crossed by ascenders is still a gap', () {
      // THE BUG THIS REPLACED. Requiring rows with literally no ink lost
      // every gap a single alif or ya reached into — which on a real
      // page is most of them — so the page was left unstretched and all
      // of the leftover height piled up under the last line.
      final crossed = syntheticPage(gapInk: 3);
      expect(crossed.where((v) => v == 0).length, lessThan(60),
          reason: 'the gaps are no longer clear rows');
      expect(MushafPageStretch.gapRunsOf(crossed)?.length, 14 * 2);
    });

    test('a pinch inside one line is not mistaken for line spacing', () {
      // [build] gives the most height to the SHORTEST gaps, so a two-row
      // dip in the middle of a line would be prised wide open.
      final ink = syntheticPage();
      ink[20 + 3 * 38 + 10] = 2;
      ink[20 + 3 * 38 + 11] = 2;
      expect(MushafPageStretch.gapRunsOf(ink)!.length, 14 * 2);
    });

    for (final page in ['050', '255']) {
      test('finds a gap for nearly every line of real page $page', () {
        final runs = MushafPageStretch.gapRunsOf(realPage(page));
        expect(runs, isNotNull, reason: 'a set page must have line gaps');
        // A Hafs page carries 15 lines, so ~14 interior gaps, plus the
        // space under a surah band or a Basmala where the page opens one.
        expect(runs!.length ~/ 2, greaterThanOrEqualTo(12));
      });

      test('page $page is only ever stretched where the ink is thin', () {
        final ink = realPage(page);
        final runs = MushafPageStretch.gapRunsOf(ink)!;
        final busiest = [
          for (var i = 0; i + 1 < runs.length; i += 2)
            for (var y = (runs[i] * ink.length).round();
                y < (runs[i + 1] * ink.length).round();
                y++)
              ink[y]
        ].reduce((a, b) => a > b ? a : b);
        final onALine = (ink.where((v) => v > 0).toList()..sort());
        final median = onALine[onALine.length ~/ 2];
        expect(busiest, lessThan(median * 0.3),
            reason: 'a stretched row carries a line, not a stray stroke');
      });
    }
  });

  group('Page stretch', () {
    late MushafPageStretch stretch;
    late List<double> runs;

    setUp(() {
      runs = MushafPageStretch.gapRunsOf(syntheticPage())!;
      stretch = MushafPageStretch.build(runs, top: 0, height: 600, extra: 60)!;
    });

    test('adds exactly the height it was asked for', () {
      expect(stretch.extraHeight, closeTo(60, 0.001));
    });

    test('never moves anything upwards, and never overlaps', () {
      for (var i = 1; i < stretch.src.length; i++) {
        expect(stretch.src[i], greaterThanOrEqualTo(stretch.src[i - 1]));
        expect(stretch.dst[i], greaterThanOrEqualTo(stretch.dst[i - 1]));
      }
    });

    test('leaves inked rows undistorted — only the gaps stretch', () {
      // Every row carrying a line must map at unit scale, or glyphs
      // would be squashed or stretched vertically.
      final ink = syntheticPage();
      for (var line = 0; line < 15; line++) {
        final top = (20 + line * 38).toDouble();
        final bottom = top + 31;
        expect(ink[top.toInt()], greaterThan(0));
        final height = stretch.mapY(bottom) - stretch.mapY(top);
        expect(height, closeTo(bottom - top, 0.001),
            reason: 'line $line was distorted');
      }
    });

    test('the mapping is continuous — no row is skipped or duplicated', () {
      // A cut would show up as a jump between two neighbouring rows.
      var previous = stretch.mapY(0);
      for (var y = 1.0; y <= 600; y += 1) {
        final here = stretch.mapY(y);
        expect(here - previous, lessThan(3.0),
            reason: 'discontinuity at row $y would tear the page');
        expect(here, greaterThanOrEqualTo(previous));
        previous = here;
      }
    });

    test('a tap maps back to the row it was printed on', () {
      for (var y = 0.0; y <= 600; y += 7) {
        expect(stretch.unmap(stretch.mapY(y)), closeTo(y, 0.01));
      }
    });

    test('too little to work with is refused rather than guessed', () {
      expect(
          MushafPageStretch.build(runs, top: 0, height: 600, extra: 0), isNull);
      expect(MushafPageStretch.build(const [], top: 0, height: 600, extra: 60),
          isNull);
    });
  });

  group('Real Hafs artwork', () {
    // A phone-shaped box: a 345x550 leaf fitted to a 386-wide screen is
    // ~615 tall, and the reader's page area is ~733 — so ~118 logical
    // pixels of slack, which is the dead band under the last line that
    // the spread exists to remove.
    const boxHeight = 733.0;
    const renderWidth = 386.0;

    for (final page in ['050', '255']) {
      test('page $page fills the screen instead of ending in dead space', () {
        final ink = realPage(page);
        final vbWidth = (fixtures[page]['viewBoxWidth'] as num).toDouble();
        final vbHeight = (fixtures[page]['viewBoxHeight'] as num).toDouble();
        final renderHeight = renderWidth / (vbWidth / vbHeight);
        final scaleY = renderHeight / vbHeight;
        final slack = boxHeight - renderHeight;
        expect(slack, greaterThan(80), reason: 'the leaf is the wider shape');

        final runs = MushafPageStretch.gapRunsOf(ink)!;
        final stretch = MushafPageStretch.build(runs,
            top: 0, height: vbHeight, extra: slack / scaleY)!;

        expect(renderHeight + stretch.extraHeight * scaleY,
            closeTo(boxHeight, 0.5));
      });

      test('page $page distorts no row that carries a line', () {
        final ink = realPage(page);
        final vbHeight = (fixtures[page]['viewBoxHeight'] as num).toDouble();
        final runs = MushafPageStretch.gapRunsOf(ink)!;
        final stretch = MushafPageStretch.build(runs,
            top: 0, height: vbHeight, extra: vbHeight * 0.18)!;

        final onALine = (ink.where((v) => v > 0).toList()..sort());
        final median = onALine[onALine.length ~/ 2];
        final perUnit = ink.length / vbHeight;
        for (var y = 0; y < ink.length; y++) {
          if (ink[y] < median) continue; // thin rows are the gaps
          final top = y / perUnit;
          final bottom = (y + 1) / perUnit;
          expect(stretch.mapY(bottom) - stretch.mapY(top),
              closeTo(bottom - top, 0.0001),
              reason: 'raster row $y was scaled — a glyph would distort');
        }
      });
    }
  });

  group('Page furniture', () {
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
          home: Scaffold(body: MushafPageFooter(page: page, isDark: false)),
        ));
        final align = tester.widget<Align>(find
            .descendant(
                of: find.byType(MushafPageFooter), matching: find.byType(Align))
            .first);
        expect(align.alignment, alignment, reason: 'page $page');
        expect(find.text(arabicDigits(page)), findsOneWidget);
      }
    });

    testWidgets('the ornament keeps its size in a deeper band',
        (tester) async {
      // The foot band doubles as the phone's bottom inset, so it is as
      // deep as the device says — the page number must not grow with it.
      for (final height in [30.0, 48.0]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MushafPageFooter(page: 50, isDark: false, height: height)),
        ));
        expect(tester.getSize(find.byType(MushafPageFooter)).height, height);
        expect(tester.getSize(find.byType(MushafPageBadge)).height,
            lessThanOrEqualTo(32.0));
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
  });
}

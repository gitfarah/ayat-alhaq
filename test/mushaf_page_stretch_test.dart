import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/widgets/mushaf_page_furniture.dart';
import 'package:quran_app_v1/widgets/mushaf_spread_page.dart';

/// The page artwork is one enormous vector path, so the only way to open
/// up its line spacing is to redraw the raster. Doing that by CUTTING it
/// into one strip per line clipped every alif and kasra that reached
/// into a neighbouring line — the script simply does not stay inside the
/// ayah boxes. These tests pin down the replacement: a continuous
/// mapping that stretches only the rows carrying no ink.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A page profile: 15 lines of ink separated by 6-row gaps, with
  /// margins top and bottom.
  List<int> syntheticPage() {
    final ink = List<int>.filled(600, 0);
    for (var line = 0; line < 15; line++) {
      final top = 20 + line * 38;
      for (var y = top; y < top + 32; y++) {
        ink[y] = 1;
      }
    }
    return ink;
  }

  group('Blank-run measurement', () {
    test('finds the gaps between lines, not the page margins', () {
      final runs = MushafPageStretch.blankRunsOf(syntheticPage())!;
      // 15 lines leave 14 interior gaps; margins are excluded.
      expect(runs.length, 14 * 2);
      // The first gap starts after the first line's ink, not at the top.
      expect(runs.first, greaterThan(20 / 600));
    });

    test('a page with no gaps is left alone', () {
      expect(MushafPageStretch.blankRunsOf(List<int>.filled(600, 1)), isNull);
      expect(MushafPageStretch.blankRunsOf(List<int>.filled(600, 0)), isNull);
    });
  });

  group('Page stretch', () {
    late MushafPageStretch stretch;
    late List<double> runs;

    setUp(() {
      runs = MushafPageStretch.blankRunsOf(syntheticPage())!;
      stretch =
          MushafPageStretch.build(runs, top: 0, height: 600, extra: 60)!;
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

    test('leaves inked rows undistorted — only blank rows stretch', () {
      // Every row carrying ink must map at unit scale, or glyphs would
      // be squashed or stretched vertically.
      final ink = syntheticPage();
      for (var line = 0; line < 15; line++) {
        final top = (20 + line * 38).toDouble();
        final bottom = top + 31;
        expect(ink[top.toInt()], 1);
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
      expect(MushafPageStretch.build(runs, top: 0, height: 600, extra: 0),
          isNull);
      expect(MushafPageStretch.build(const [], top: 0, height: 600, extra: 60),
          isNull);
    });
  });

  group('Real Hafs artwork', () {
    // Uses a page fetched into the scratch dir; skipped otherwise so CI
    // never depends on the network.
    const svgPath =
        r'C:\Users\mroma\AppData\Local\Temp\claude\D--flutter\a17e59c2-4325-48e1-ac29-42f2416ea1ec\scratchpad\321.svg';

    test('stretching page 321 distorts no inked row', () async {
      if (!File(svgPath).existsSync()) {
        markTestSkipped('page artwork not fetched');
        return;
      }
      final info = await vg.loadPicture(
          SvgStringLoader(File(svgPath).readAsStringSync()), null);
      const w = 720;
      const h = (w * 550) ~/ 345;
      final rec = ui.PictureRecorder();
      Canvas(rec)
        ..scale(w / 345)
        ..drawPicture(info.picture);
      final pic = rec.endRecording();
      final image = await pic.toImage(w, h);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final data = bytes.buffer.asUint8List();

      final ink = List<int>.filled(h, 0);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (data[(y * w + x) * 4 + 3] > 40) {
            ink[y] = 1;
            break;
          }
        }
      }

      final runs = MushafPageStretch.blankRunsOf(ink);
      expect(runs, isNotNull, reason: 'a set page must have line gaps');
      final s = MushafPageStretch.build(runs!,
          top: 0, height: 550, extra: 550 * 0.18)!;

      // Every inked row of the REAL page must map at unit scale.
      const perUnit = h / 550;
      for (var y = 0; y < h; y++) {
        if (ink[y] == 0) continue;
        final top = y / perUnit;
        final bottom = (y + 1) / perUnit;
        expect(s.mapY(bottom) - s.mapY(top), closeTo(bottom - top, 0.0001),
            reason: 'inked raster row $y was scaled — a glyph would distort');
      }

      image.dispose();
      pic.dispose();
      info.picture.dispose();
    });
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

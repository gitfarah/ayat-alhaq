import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/mushaf_glyph_service.dart';

/// The V1 layout is written in Arabic Presentation Forms-A, which are
/// REAL Unicode characters. That is what made a missing page font
/// invisible: the engine silently drew the codes with whatever font
/// covered the block, so the page read as Quran while being the wrong
/// script entirely. These tests pin down that the app can now tell the
/// two apart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => MushafGlyphService.loadLayout());

  double widthWith(String family, String text) {
    final p = TextPainter(
      textDirection: TextDirection.rtl,
      text: TextSpan(
          text: text, style: TextStyle(fontFamily: family, fontSize: 100)),
    )..layout();
    return p.width;
  }

  test('the layout really is written in Arabic Presentation Forms', () {
    // If this ever stops being true the silent-fallback hazard is gone
    // and the verification below can be reconsidered.
    final line = MushafGlyphService.linesOf(221)
        .firstWhere((l) => !l.usesSharedFont && l.text.isNotEmpty);
    for (final rune in line.text.runes) {
      expect(rune, greaterThanOrEqualTo(0xFB50));
      expect(rune, lessThanOrEqualTo(0xFDFF));
    }
  });

  test('an unregistered page font is detected, not silently accepted', () {
    // Nothing has registered QCF_P221 in this test, so it can only be
    // the fallback — and the fallback is NOT empty boxes, which is the
    // whole problem.
    final line = MushafGlyphService.linesOf(221)
        .firstWhere((l) => !l.usesSharedFont && l.text.isNotEmpty);
    final real = widthWith('QCF_P221', line.text);
    final absent = widthWith('__mushaf_absent_family__', line.text);

    expect(real, greaterThan(0),
        reason: 'the fallback draws something — that is the hazard');
    expect(real, closeTo(absent, 0.5),
        reason: 'an unregistered family must measure exactly as a fallback');
  });

  test('a registered page font measures differently from the fallback',
      () async {
    // Uses a real KFGQPC page font if one has been fetched into the
    // scratch dir; skipped otherwise so CI never depends on the CDN.
    const path =
        r'C:\Users\mroma\AppData\Local\Temp\claude\D--flutter\a17e59c2-4325-48e1-ac29-42f2416ea1ec\scratchpad\p221.ttf';
    if (!File(path).existsSync()) {
      markTestSkipped('page font not fetched');
      return;
    }
    final bytes = File(path).readAsBytesSync();
    await (FontLoader('QCF_P221_probe')
          ..addFont(
              Future.value(ByteData.view(Uint8List.fromList(bytes).buffer))))
        .load();

    final line = MushafGlyphService.linesOf(221)
        .firstWhere((l) => !l.usesSharedFont && l.text.isNotEmpty);
    final real = widthWith('QCF_P221_probe', line.text);
    final absent = widthWith('__mushaf_absent_family__', line.text);

    expect((real - absent).abs(), greaterThan(0.5),
        reason: 'a font that is actually applied must not measure as fallback');

    // And the giveaway of a correctly applied V1 font: every ayah line
    // of a page is set to the same measure, within a rounding hair.
    final widths = [
      for (final l in MushafGlyphService.linesOf(221))
        if (!l.usesSharedFont && l.text.isNotEmpty)
          widthWith('QCF_P221_probe', l.text)
    ]..sort();
    expect(widths.last / widths.first, lessThan(1.05),
        reason: 'V1 lines are justified by the font itself');
  });
}

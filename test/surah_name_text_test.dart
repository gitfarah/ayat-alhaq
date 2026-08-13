// Every surah name in the app is SET in QUL's V4 ligature font, not
// spelled in a text face — the same font and the same ligature key the
// V4 Mushaf heads its pages with, so a surah is named identically
// wherever the app names it.
//
// The contract is narrow and easy to break silently, because a broken
// ligature does not throw: it renders the raw ASCII key "surah001" on
// screen. These pin the three things that make it work.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quran_app_v1/widgets/surah_name_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the ligature key', () {
    test('is zero-padded to three digits across the whole range', () {
      expect(SurahNameText.glyph(1), 'surah001');
      expect(SurahNameText.glyph(9), 'surah009');
      expect(SurahNameText.glyph(18), 'surah018');
      expect(SurahNameText.glyph(114), 'surah114');
    });

    test('is unique for all 114 surahs', () {
      final keys = {for (var n = 1; n <= 114; n++) SurahNameText.glyph(n)};
      expect(keys.length, 114);
    });
  });

  group('the rendered Text', () {
    Future<Text> pump(WidgetTester tester, int surah) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SurahNameText(
              surahNumber: surah, fontSize: 34, color: Colors.black),
        ),
      ));
      return tester.widget<Text>(find.byType(Text));
    }

    testWidgets('carries the ligature key, the V4 family and liga on',
        (tester) async {
      final text = await pump(tester, 2);

      expect(text.data, 'surah002');
      expect(text.style!.fontFamily, 'QUL_Surah_Name_V4',
          reason: 'the V2 name font is a different face; the app sets '
              'names in the V4 one the Mushaf uses');
      // Without an explicit liga feature the ASCII key can reach the
      // screen as literal Latin "surah002".
      expect(text.style!.fontFeatures, isNotNull);
      expect(
          text.style!.fontFeatures!
              .any((f) => f.feature == 'liga' && f.value == 1),
          isTrue,
          reason: 'the ligature feature must be explicitly enabled');
    });

    testWidgets('lays out RTL so the name sits where Arabic expects it',
        (tester) async {
      final text = await pump(tester, 2);
      expect(text.textDirection, TextDirection.rtl);
    });

    testWidgets('sets its own leading — the names ride high in the em box',
        (tester) async {
      final text = await pump(tester, 2);
      expect(text.style!.height, 1.0);
    });
  });
}

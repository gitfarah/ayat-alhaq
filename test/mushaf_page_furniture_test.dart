import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/widgets/mushaf_page_furniture.dart';

/// The running head and the page number a Mushaf leaf carries, which
/// replaced the app's own page-number bar and its arrows.
void main() {
  test('page numbers are written in Arabic-Indic digits', () {
    expect(arabicDigits(1), '١');
    expect(arabicDigits(321), '٣٢١');
    expect(arabicDigits(604), '٦٠٤');
  });

  testWidgets('the number sits on the outer edge of the leaf', (tester) async {
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

  testWidgets('the ornamental badge paints without error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          for (final dark in [false, true])
            for (final page in [1, 321, 604])
              MushafPageBadge(page: page, isDark: dark, pointLeft: page.isEven),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}

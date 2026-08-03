import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/theme.dart';
import 'package:quran_app_v1/widgets/ayah_sheet_header.dart';

void main() {
  const ayah = 'يَٰٓأَيُّهَا ٱلنَّاسُ ٱتَّقُوا۟ رَبَّكُمُ';
  const label = 'النساء — آية ١';

  Future<void> pump(WidgetTester tester,
      {String? text}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AyahSheetHeader(ayahText: text, label: label),
      ),
    ));
  }

  testWidgets('shows the ayah itself, right-to-left in the Mushaf face',
      (tester) async {
    await pump(tester, text: ayah);
    final widget = tester.widget<Text>(find.text(ayah));
    expect(widget.textDirection, TextDirection.rtl);
    expect(widget.textAlign, TextAlign.center);
    expect(widget.style!.fontFamily, 'QuranHafs');
  });

  testWidgets('keeps the surah/ayah line under the text', (tester) async {
    await pump(tester, text: ayah);
    expect(find.text(label), findsOneWidget);
    expect(tester.widget<Text>(find.text(label)).textDirection,
        TextDirection.rtl);
  });

  testWidgets('shows the label alone while the text is still loading',
      (tester) async {
    await pump(tester);
    expect(find.text(label), findsOneWidget);
    expect(find.text(ayah), findsNothing);
  });

  testWidgets('a page-long ayah is clipped instead of growing the sheet',
      (tester) async {
    await pump(tester, text: List.filled(200, ayah).join(' '));
    final widget = tester.widget<Text>(find.textContaining(ayah));
    expect(widget.maxLines, 4);
    expect(widget.overflow, TextOverflow.ellipsis);
    // Header must stay a sheet header, not take over the screen.
    expect(tester.getSize(find.byType(AyahSheetHeader)).height, lessThan(300));
  });

  testWidgets('sits on the same green panel an ayah is quoted on',
      (tester) async {
    await pump(tester, text: ayah);
    final box = tester.widget<Container>(find
        .descendant(
            of: find.byType(AyahSheetHeader), matching: find.byType(Container))
        .first);
    expect((box.decoration as BoxDecoration).color, AppColors.ayahPanel);
    expect(tester.widget<Text>(find.text(ayah)).style!.color, Colors.white);
  });

  testWidgets('the ayah is centred on the panel', (tester) async {
    await pump(tester, text: ayah);
    expect(tester.widget<Text>(find.text(ayah)).textAlign, TextAlign.center);
    expect(tester.widget<Text>(find.text(label)).textAlign, TextAlign.center);
  });
}

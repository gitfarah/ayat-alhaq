// The note editor as the user actually drives it: open the sheet on an
// ayah, type, save — and the note comes back on the mark.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/services/highlight_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';
import 'package:quran_app_v1/widgets/ayah_note_sheet.dart';

void main() {
  /// A bare host whose single button opens the note sheet for 2:255.
  Widget host({VoidCallback? onClosed}) => ChangeNotifierProvider(
        create: (_) => SettingsService(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  await showAyahNoteSheet(
                    context,
                    surahNumber: 2,
                    ayahNumber: 255,
                    surahName: 'البقرة',
                    page: 42,
                  );
                  onClosed?.call();
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('typing a note and saving stores it on the ayah',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openSheet(tester);

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'أعظم آية في القرآن');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    final h = await HighlightService.getHighlight(2, 255);
    expect(h, isNotNull, reason: 'the note created the mark');
    expect(h!.note, 'أعظم آية في القرآن');
    expect(h.page, 42, reason: 'written from the Mushaf, reopens there');
  });

  testWidgets('cancelling leaves nothing behind', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), 'مسودة');
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(await HighlightService.getHighlight(2, 255), isNull);
  });

  testWidgets('an existing note opens prefilled and can be deleted',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await HighlightService.addHighlight(Highlight(
      surahNumber: 2,
      ayahNumber: 255,
      surahName: 'البقرة',
      color: 'blue',
      note: 'ملاحظة سابقة',
      createdAt: DateTime(2026, 1, 1),
    ));

    await openSheet(tester);
    // Prefilled with what was saved…
    expect(find.text('ملاحظة سابقة'), findsOneWidget);

    // …and "delete note" is only offered because there is one.
    await tester.tap(find.text('حذف الملاحظة'));
    await tester.pumpAndSettle();

    final h = await HighlightService.getHighlight(2, 255);
    expect(h, isNotNull, reason: 'the colour mark survives');
    expect(h!.hasNote, isFalse);
    expect(h.color, 'blue');
  });

  testWidgets('no delete button when the ayah has no note yet',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openSheet(tester);

    expect(find.text('حذف الملاحظة'), findsNothing);
  });

  testWidgets('the note renders as a card under the ayah', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AyahNoteCard(
          note: 'تدبر',
          color: Colors.amber,
          isDark: false,
          isArabic: true,
        ),
      ),
    ));

    expect(find.text('تدبر'), findsOneWidget);
    expect(find.byIcon(Icons.sticky_note_2_rounded), findsOneWidget);
  });
}

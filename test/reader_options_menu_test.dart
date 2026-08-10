// Regression test for the 2026-08-02 "no popup menu opens" bug: every
// long-press options sheet (تفسير، تشغيل التلاوة، إلخ) called
// `L10n.of(context)` at the top of an event-handler method, where
// `context.watch<SettingsService>()` throws Provider's own debug
// assertion — the sheet never got built. Widget tests run with
// assertions enabled, so this exercises the exact failure the user hit
// in `flutter run -d chrome`, without needing a real browser.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/models/surah.dart';
import 'package:quran_app_v1/screens/reader_screen.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Only the ayah cards attach `onLongPress` (line 885 of
  /// reader_screen.dart) — the app bar's buttons and full-screen
  /// tap-to-toggle-bars detector are tap-only. Filtering on that is the
  /// reliable way to find an ayah card specifically, rather than
  /// `find.byType(GestureDetector).last`, whose tree position isn't
  /// guaranteed to land on an ayah — it hit a font-size button instead
  /// on the first attempt at this test.
  final ayahLongPressFinder = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onLongPress != null);

  /// Lets the real asset read (QuranService's bundled Quran text) finish
  /// under the test's fake-async zone — a plain [WidgetTester.pump]
  /// never advances genuine I/O, so this alternates real delays with
  /// pumps until the ayah list has actually loaded.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
      if (ayahLongPressFinder.evaluate().isNotEmpty) return;
    }
  }

  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(create: (_) => QuranAudioService()),
        ],
        child: MaterialApp(
          home: ReaderScreen(
            surah: Surah(
              number: 1,
              name: 'سُورَةُ الفَاتِحَةِ',
              englishName: 'Al-Faatiha',
              englishNameTranslation: 'The Opening',
              numberOfAyahs: 7,
              revelationType: 'Meccan',
            ),
          ),
        ),
      );

  testWidgets(
      'long-pressing an ayah opens the options sheet without throwing',
      (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    await tester.longPress(ayahLongPressFinder.first);
    await tester.pump(); // let the bottom sheet animate in
    await tester.pump(const Duration(milliseconds: 300));

    // The crash happened before the sheet was ever built, so its
    // absence IS the bug. Confirm it's actually open.
    expect(find.byType(BottomSheet), findsOneWidget,
        reason: 'the ayah options sheet did not open — regression of '
            'the L10n.of(context) crash');
    expect(tester.takeException(), isNull);
  });

  testWidgets('every action in the options sheet has readable text',
      (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    await tester.longPress(ayahLongPressFinder.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // These are the exact two the user reported: تفسير and تشغيل
    // التلاوة (play/pause recitation). Their labels must have rendered
    // as real text, not thrown before Text() was ever built.
    expect(find.text('التفسير'), findsOneWidget);
    expect(find.textContaining('تلاوة'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the options sheet lists actions in the same order as the Mushaf: '
      'recitation, tafsir, bookmark, highlight, note, then share (copy is '
      'a Reader-only extra before it)', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    await tester.longPress(ayahLongPressFinder.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final tiles = tester
        .widgetList<ListTile>(find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(ListTile)))
        .toList();
    final titles = tiles.map((t) => (t.title as Text).data).toList();

    expect(
        titles,
        [
          'تشغيل التلاوة',
          'التفسير',
          'الفاصل',
          'تمييز الآية',
          'إضافة ملاحظة',
          'نسخ الآية',
          'مشاركة',
        ],
        reason: 'must match the Mushaf sheet\'s order — a reader jumping '
            'between the two modes should find the same action in the '
            'same place');
  });
}

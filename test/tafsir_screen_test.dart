// The expanded ayah study screen.
//
// flutter_test answers every HTTP request with a 400, so these run the
// screen exactly as it behaves offline: the network-backed tabs must
// degrade to a retry prompt, while the asset-backed المتشابهات tab and
// the ayah text itself still work.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/screens/tafsir_screen.dart';
import 'package:quran_app_v1/services/ayah_insight_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';
import 'package:quran_app_v1/services/tafsir_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // The service's caches are static. Without this, a request still in
    // flight when one test ends is handed to the next one — and it can
    // never complete, because the zone that would resolve it is gone.
    await AyahInsightService.clearCache();
  });

  Widget host({int initialTab = 0, int surah = 2, int ayah = 2}) =>
      ChangeNotifierProvider(
        create: (_) => SettingsService(),
        child: MaterialApp(
          home: TafsirScreen(
            surahNumber: surah,
            surahName: 'البقرة',
            ayahNumber: ayah,
            initialTab: initialTab,
          ),
        ),
      );

  /// Lets the screen's real asynchronous work finish. Asset reads and
  /// HTTP both need [WidgetTester.runAsync] — under the fake async zone
  /// a plain pump never advances them, so the loading spinner would
  /// spin forever and pumpAndSettle would time out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> open(WidgetTester tester,
      {int initialTab = 0, int surah = 2, int ayah = 2}) async {
    await tester.pumpWidget(
        host(initialTab: initialTab, surah: surah, ayah: ayah));
    await settle(tester);
  }

  testWidgets('offers all six study layers as tabs', (tester) async {
    await open(tester);

    for (final tab in const [
      'التفسير',
      'الإعراب',
      'التصريف',
      'المعنى',
      'القراءات',
      'المتشابهات',
    ]) {
      expect(find.text(tab), findsWidgets, reason: 'missing the $tab tab');
    }
  });

  testWidgets('opens on the tab the caller asked for', (tester) async {
    await open(tester, initialTab: 5);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 5);
  });

  testWidgets('an out-of-range initial tab is clamped, not crashed',
      (tester) async {
    await open(tester, initialTab: 99);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the mutashabihat tab reads from the bundled index, not the '
      'network', (tester) async {
    // 2:34 (the Iblis-refusal narrative) is in the book-transcribed
    // seed, matched against three passages elsewhere in the Quran.
    await open(tester, initialTab: 5, surah: 2, ayah: 34);

    expect(find.textContaining('لا توجد مواضع متشابهة'), findsNothing);
    // Its matches are two-ayah runs (the refusal plus the follow-up
    // question), so each card is headed «… — الآيات ١١-١٢». The surah
    // name comes from the bundled text, which already reads
    // «سُورَةُ ...», so the heading must not say "سورة" a second time.
    expect(find.textContaining('— الآيات'), findsWidgets);
    expect(find.textContaining('سورة سُورَةُ'), findsNothing);
  });

  testWidgets('an ayah with no recorded mutashabiha says so plainly',
      (tester) async {
    // Nothing from Al-Imran has been transcribed yet.
    await open(tester, initialTab: 5, surah: 3, ayah: 5);
    expect(find.textContaining('لا توجد مواضع متشابهة'), findsOneWidget);
  });

  testWidgets('a failed network layer offers a retry, not a stuck spinner',
      (tester) async {
    await open(tester, initialTab: 1);

    expect(find.text('إعادة المحاولة'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the ayah card falls back to plain text when the word list '
      'cannot load', (tester) async {
    await open(tester);

    // No word tokens could be fetched, so the card shows the ayah as
    // one run rather than rendering an empty box.
    expect(find.text('سورة البقرة - آية ٢'), findsOneWidget);
    // 'البقرة ٢' is the last-resort label used when even the ayah text
    // is unavailable; seeing it would mean the card gave up early.
    expect(find.text('البقرة ٢'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tafsir picker reads right-to-left: name at the right '
      'edge, chevron at the left', (tester) async {
    await open(tester);

    final picker = find.byType(DropdownButton<int>);
    expect(picker, findsOneWidget);

    // The whole screen is pinned LTR for its chrome, so this control
    // has to carry its own RTL — without it the Arabic name hugs the
    // left and the chevron sits on the right, which is what a reader
    // reported seeing.
    expect(
        tester
            .widget<Directionality>(find
                .ancestor(
                    of: picker, matching: find.byType(Directionality))
                .first)
            .textDirection,
        TextDirection.rtl);

    // Geometry, not just intent: the selected name must actually render
    // to the RIGHT of the chevron. The screen opens on the app-wide
    // default edition (editions.first), not a hardcoded name — deriving
    // it here means this assertion survives the default changing.
    final nameX = tester
        .getCenter(find
            .descendant(
                of: picker,
                matching: find.text(TafsirService.editions.first.name))
            .first)
        .dx;
    final chevronX =
        tester.getCenter(find.byIcon(Icons.arrow_drop_down).first).dx;
    expect(nameX, greaterThan(chevronX),
        reason: 'the Arabic name should start from the right, with the '
            'dropdown chevron to its left');
  });

  testWidgets('the caller-supplied ayah text is used as-is', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => SettingsService(),
      child: const MaterialApp(
        home: TafsirScreen(
          surahNumber: 2,
          surahName: 'البقرة',
          ayahNumber: 255,
          ayahText: 'نص الآية',
        ),
      ),
    ));
    await settle(tester);

    expect(find.text('نص الآية'), findsOneWidget);
  });
}

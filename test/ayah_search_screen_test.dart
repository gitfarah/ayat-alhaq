// AyahSearchScreen is now the ONE search implementation shared by the
// home screen, the Mushaf and the reader — no scoped variant, no
// separate in-surah sheet. These pin the two things that make that
// sharing actually work:
//
//   - the search itself always reaches the whole Quran (no surahNumbers
//     filter survives anywhere in this screen any more);
//   - returnResultToCaller, which lets the Mushaf and the reader jump to
//     a result IN PLACE instead of always being dumped into a fresh
//     MushafReaderScreen — covering BOTH an ayah result and a SURAH result,
//     since the surah-tile branch is the newly-added one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/screens/ayah_search_screen.dart';
import 'package:quran_app_v1/screens/mushaf_reader_screen.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';
import 'package:quran_app_v1/services/quran_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Without this, a focused TextField left mid-transition at one
  // test's end can still hold focus when the next test's pumpWidget()
  // starts — enterText's internal element lookup then intermittently
  // throws "Bad state: No element" in a LATER test, for a widget tree
  // that has nothing wrong with it.
  tearDown(() => TestWidgetsFlutterBinding.instance.focusManager.primaryFocus
      ?.unfocus());

  // Both providers: the default result-tap path pushes MushafReaderScreen,
  // which reads QuranAudioService for its play/pause row — omitting it
  // throws a ProviderNotFoundException on that push, which surfaced
  // as unrelated-looking finder failures in whatever ran next before
  // this was tracked down.
  Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(create: (_) => QuranAudioService()),
        ],
        child: MaterialApp(home: child),
      );

  /// The search is asset-backed (offline), but still asynchronous and
  /// debounced (500ms) — real delays under runAsync, not a fake clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> typeAndSettle(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await settle(tester);
  }

  group('reach: unscoped, always the whole Quran', () {
    testWidgets(
        'a phrase from Al-Fatiha is found with no surah context supplied',
        (tester) async {
      await tester.pumpWidget(host(const AyahSearchScreen()));
      await typeAndSettle(tester, 'الحمد لله رب العالمين');

      // A rendered ListTile is a hit; the number-of-results line under
      // the search field confirms it counted at least one.
      expect(find.byType(ListTile), findsWidgets);
      expect(find.textContaining('نتيجة'), findsOneWidget);
    });

    testWidgets('a surah name match surfaces above the ayah matches',
        (tester) async {
      final surah = (await QuranService.searchSurahs('الفاتحة')).first;

      await tester.pumpWidget(host(const AyahSearchScreen()));
      await typeAndSettle(tester, 'الفاتحة');

      expect(find.text(surah.name), findsOneWidget);
      // The surah tile is item 0 of the results list — before any ayah
      // matches, not just present somewhere in it.
      final firstTile = tester.widget<ListTile>(find.byType(ListTile).first);
      expect((firstTile.title as Text).data, surah.name);
    });
  });

  // Tapping is done by POSITION (find.byType(ListTile).first), never by
  // matching a fragment of the Arabic result text: the ayah is DISPLAYED
  // with full tashkeel while the query above was typed plain, so a
  // substring match between the two is not guaranteed and proved
  // flaky in practice. Surah matches render before ayah matches (see
  // itemBuilder), so .first reliably means "the surah tile" whenever
  // the query has one, and "the top ayah hit" otherwise.
  //
  // Expected surah/ayah numbers are fetched from QuranService directly
  // rather than hard-coded, so a test asserts "tapping the top result
  // pops THAT result" — the actual feature — rather than an assumption
  // about this phrase's exact rank among all matches.

  group('default: opens the reader, like tapping a home-screen result',
      () {
    testWidgets('an ayah result pushes MushafReaderScreen', (tester) async {
      await tester.pumpWidget(host(const AyahSearchScreen()));
      await typeAndSettle(tester, 'الحمد لله رب العالمين');

      await tester.tap(find.byType(ListTile).first);
      await settle(tester);

      expect(find.byType(MushafReaderScreen), findsOneWidget);
    });

    testWidgets('a surah result pushes MushafReaderScreen too', (tester) async {
      await tester.pumpWidget(host(const AyahSearchScreen()));
      await typeAndSettle(tester, 'الفاتحة');

      await tester.tap(find.byType(ListTile).first);
      await settle(tester);

      expect(find.byType(MushafReaderScreen), findsOneWidget);
    });
  });

  group('returnResultToCaller: the Mushaf/reader "stay in place" path',
      () {
    testWidgets('an ayah result pops an AyahSearchResult, no MushafReaderScreen',
        (tester) async {
      const query = 'الحمد لله رب العالمين';
      final expected = (await QuranService.searchAyahs(query)).first;

      AyahSearchResult? popped;
      await tester.pumpWidget(host(Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            popped = await Navigator.push<AyahSearchResult>(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const AyahSearchScreen(returnResultToCaller: true)));
          },
          child: const Text('open'),
        );
      })));
      await tester.tap(find.text('open'));
      // A bare pump() only advances one frame — nowhere near enough
      // for MaterialPageRoute's push transition to finish. enterText()
      // on the incoming screen while that's still mid-flight is what
      // threw "Bad state: No element" here.
      await settle(tester);

      await typeAndSettle(tester, query);
      await tester.tap(find.byType(ListTile).first);
      await settle(tester);

      expect(find.byType(MushafReaderScreen), findsNothing,
          reason: 'the caller asked for the result back, not a navigation');
      expect(popped, isNotNull);
      expect(popped!.surahNumber, expected.surahNumber);
      expect(popped!.numberInSurah, expected.numberInSurah);
    });

    testWidgets(
        'a SURAH result pops an AyahSearchResult standing in for ayah 1',
        (tester) async {
      // This is the newly-added branch: _surahTile ignored
      // returnResultToCaller entirely before this change and always
      // pushed MushafReaderScreen, which would have silently thrown a reader
      // opened FROM the Mushaf out of the Mushaf.
      const query = 'الفاتحة';
      final expected = (await QuranService.searchSurahs(query)).first;

      AyahSearchResult? popped;
      await tester.pumpWidget(host(Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            popped = await Navigator.push<AyahSearchResult>(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const AyahSearchScreen(returnResultToCaller: true)));
          },
          child: const Text('open'),
        );
      })));
      await tester.tap(find.text('open'));
      // A bare pump() only advances one frame — nowhere near enough
      // for MaterialPageRoute's push transition to finish. enterText()
      // on the incoming screen while that's still mid-flight is what
      // threw "Bad state: No element" here.
      await settle(tester);

      await typeAndSettle(tester, query);
      await tester.tap(find.byType(ListTile).first);
      await settle(tester);

      expect(find.byType(MushafReaderScreen), findsNothing);
      expect(popped, isNotNull);
      expect(popped!.surahNumber, expected.number);
      expect(popped!.numberInSurah, 1,
          reason: 'ayah 1 stands in for "the surah itself"');
    });
  });
}

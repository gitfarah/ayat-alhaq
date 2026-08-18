// Regression test for a crash reported live: tapping the tajweed switch
// in MushafReaderScreen brought the whole page down with
// "A RenderViewport expected a child of type RenderSliver but received
// a child of type RenderErrorBox" — and, separately, leaving the screen
// afterwards hit a framework "_dependents.isEmpty" assertion.
//
// Root cause, found by reproducing directly rather than guessing from
// the render-tree error (which pointed at ScrollablePositionedList, not
// at the actual bug): `setState(() => _page = _fetch())` is an ARROW
// body, so the closure's return value is the assignment EXPRESSION's
// value — the Future itself — which trips setState's own guard against
// `setState(() async {...})`. That thrown assertion, mid-build inside
// the PageView, is what produced the sliver/RenderErrorBox mismatch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/screens/mushaf_reader_screen.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(create: (_) => QuranAudioService()),
        ],
        child: MaterialApp(home: child),
      );

  testWidgets(
      'toggling the tajweed switch does not throw or break the page',
      (tester) async {
    await tester.pumpWidget(
        host(const MushafReaderScreen(initialPage: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    final palette = find.byIcon(Icons.palette_outlined);
    expect(palette, findsOneWidget,
        reason: 'page 50 is Al Imran, a V4-tajweed page — the switch '
            'must be offered');

    await tester.tap(palette);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // Toggle back — the earlier bug's fetch-closure mistake was in the
    // same code path either direction.
    await tester.tap(palette);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the reader after opening it does not assert',
      (tester) async {
    await tester.pumpWidget(host(Builder(builder: (context) {
      return Scaffold(
        body: ElevatedButton(
          child: const Text('open'),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const MushafReaderScreen(initialPage: 50))),
        ),
      );
    })));

    await tester.tap(find.text('open'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(MushafReaderScreen))).pop();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}

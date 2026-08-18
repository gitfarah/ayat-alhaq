// The reading surface is full-bleed and the chrome floats over it (the
// same convention Mushaf mode already uses), so a tap hides the top
// and bottom bars and hands the reader the whole screen.
//
// This only works if a tap that lands ON an ayah still opens its
// options sheet instead of ALSO toggling the chrome — but this test
// environment has no network, so the page never gets past its font
// fetch to render a real, tappable ayah block (it shows the retry
// state instead, same as every other test here that touches
// MushafV2Service). That interaction is instead pinned by
// `tapping an ayah wins the gesture arena over an ancestor
// GestureDetector`, which documents the general Flutter behaviour
// mushaf_reader_screen relies on: an inner InkWell's tap recognizer
// wins exclusively over a plain ancestor GestureDetector's, so opening
// an ayah's sheet never also fires the background's hide-chrome tap.
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

  testWidgets('a tap on the reading surface hides and reshows the chrome',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester
        .pumpWidget(host(const MushafReaderScreen(initialPage: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    AnimatedSlide topSlide() => tester
        .widgetList<AnimatedSlide>(find.byType(AnimatedSlide))
        .first;
    expect(topSlide().offset, Offset.zero,
        reason: 'the chrome starts visible');

    // The vertical middle of a tall viewport, well clear of both the
    // floating top and bottom bars.
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(topSlide().offset.dy, lessThan(0),
        reason: 'the top bar should have slid upward, off screen');

    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(topSlide().offset, Offset.zero,
        reason: 'a second tap should bring the chrome back');
  });

  testWidgets(
      'tapping an ayah wins the gesture arena over an ancestor GestureDetector',
      (tester) async {
    var outerTaps = 0;
    var innerTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => outerTaps++,
          child: Center(
            child: Material(
              child: InkWell(
                onTap: () => innerTaps++,
                child:
                    const SizedBox(width: 100, height: 100, child: Text('x')),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(innerTaps, 1, reason: 'the ayah block itself must open its sheet');
    expect(outerTaps, 0,
        reason: 'the background hide-chrome tap must not ALSO fire');
  });
}

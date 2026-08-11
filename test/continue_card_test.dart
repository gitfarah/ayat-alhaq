// The continue card shipped clipped: it had a fixed 132px height and
// the استمرار pill was cut off ("BOTTOM OVERFLOWED BY 17 PIXELS"). It
// also has to put the words on the reading edge and the illustration
// opposite them, in whichever direction the UI language runs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/main.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  /// Boots the real app with a saved Mushaf position, so the home
  /// screen shows the continue card, and settles past the intro.
  Future<void> pumpHome(WidgetTester tester, {required String language}) async {
    SharedPreferences.setMockInitialValues({
      'lastPage': 77,
      'lastMode': SettingsService.modeMushaf,
      'appLanguage': language,
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(create: (_) => QuranAudioService()),
        ],
        child: const QuranApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));

    // The home body is gated on the bundled surah list, which is a REAL
    // asset read: a plain pump never advances genuine I/O, so alternate
    // real delays with pumps until the card is actually built.
    for (var i = 0; i < 20; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(Image).evaluate().any(
          (e) => (e.widget as Image).height == 104)) {
        return;
      }
    }
  }

  testWidgets('the continue pill is not clipped off the card',
      (tester) async {
    await pumpHome(tester, language: 'ar');

    expect(find.text('استمرار'), findsOneWidget,
        reason: 'the Mushaf position should be offered for continuing');
    // A RenderFlex overflow is reported as an exception in tests, which
    // is exactly the bug this guards.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the words sit on the reading edge, the artwork opposite',
      (tester) async {
    await pumpHome(tester, language: 'ar');

    final label = tester.getCenter(find.text('استمرار'));
    final art = tester.getCenter(
        find.byWidgetPredicate((w) => w is Image && w.height == 104));
    expect(label.dx, greaterThan(art.dx),
        reason: 'Arabic reads right-to-left, so the words lead on the '
            'right and the illustration sits to their left');
  });

  testWidgets('the sides swap in a left-to-right language', (tester) async {
    await pumpHome(tester, language: 'en');

    expect(tester.takeException(), isNull);
    final label = tester.getCenter(find.text('Continue'));
    final art = tester.getCenter(
        find.byWidgetPredicate((w) => w is Image && w.height == 104));
    expect(label.dx, lessThan(art.dx),
        reason: 'English reads left-to-right, so the words lead on the '
            'left and the illustration sits to their right');
  });
}

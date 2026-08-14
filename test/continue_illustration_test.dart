// The continue card's illustration cycles through three pictures keyed
// on the page/surah actually being continued, so it reads as belonging
// to that position rather than as fixed decoration on the app.

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/main.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  Future<String> illustrationFor(WidgetTester tester, int page) async {
    SharedPreferences.setMockInitialValues({
      'lastPage': page,
      'lastMode': SettingsService.modeMushaf,
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

    for (var i = 0; i < 20; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
      final found = find.byWidgetPredicate((w) =>
          w is Image &&
          w.height == 104 &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName.contains('mushaf_illustration'));
      if (found.evaluate().isNotEmpty) {
        return ((tester.widget(found) as Image).image as AssetImage)
            .assetName;
      }
    }
    fail('continue card illustration never appeared for page $page');
  }

  // Index follows page % 3 against the 3-picture list, in list order:
  // page 3 -> index 0 (mushaf_illustration.png), page 1 -> index 1
  // (_2.png), page 2 -> index 2 (_3.png).
  testWidgets('a page lands on the first illustration', (tester) async {
    final a = await illustrationFor(tester, 3);
    expect(a, 'assets/icon/mushaf_illustration.png');
  });

  testWidgets('a different page lands on a different illustration',
      (tester) async {
    final a = await illustrationFor(tester, 1);
    expect(a, 'assets/icon/mushaf_illustration_2.png');
  });

  testWidgets('page numbers cycle through all three pictures',
      (tester) async {
    final a = await illustrationFor(tester, 2);
    expect(a, 'assets/icon/mushaf_illustration_3.png');
  });

  testWidgets('the same page always shows the same picture', (tester) async {
    final first = await illustrationFor(tester, 77);
    final second = await illustrationFor(tester, 77);
    expect(first, second,
        reason: 'deterministic on position, not randomised per launch');
  });
}

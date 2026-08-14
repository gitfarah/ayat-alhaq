// The reflowing page, reached the only way it can be now: by PINCHING a
// printed Hafs page open. It used to be an edition of its own, which is
// how this test used to select it.
//
// Its whole point is that the script fits the width instead of
// overflowing it, so this renders it at a phone and a tablet size and
// lets the tester turn any overflow into a failure.
//
// Worth knowing for anyone extending this: the reflow branch returns
// BEFORE the glyph page's font future is created, which is what makes
// the test possible at all — the KFGQPC page fonts are downloaded per
// page and every network call fails under flutter_test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/screens/mushaf_svg_screen.dart';
import 'package:quran_app_v1/services/mushaf_svg_service.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';

Widget _app() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(create: (_) => QuranAudioService()),
      ],
      child: const MaterialApp(home: MushafSvgScreen(startPage: 1)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'mushafEdition': 'hafs'});
    MushafSvgService.setEdition('hafs');
  });
  tearDown(() => MushafSvgService.setEdition('hafs'));

  /// Spreads two fingers far enough apart to clear [kReflowZoom].
  Future<void> pinchOpen(WidgetTester tester, Size size) async {
    final mid = Offset(size.width / 2, size.height / 2);
    final a = await tester.startGesture(mid.translate(-50, 0));
    final b = await tester.startGesture(mid.translate(50, 0));
    // 100px apart to 300px apart — a 3x scale, well past the threshold.
    await a.moveTo(mid.translate(-150, 0));
    await b.moveTo(mid.translate(150, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();
  }

  testWidgets('a pinched-open page typesets itself, portrait and landscape',
      (tester) async {
    for (final size in [const Size(390, 844), const Size(1024, 768)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      // Not pumpAndSettle: the screen keeps a bar-fade animation alive.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      await pinchOpen(tester, size);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Al-Fatiha opens page 1: its name band and its ayah text. Under
      // the printed page this would find nothing — the glyph font it
      // needs cannot be downloaded in a test — so finding it IS the
      // proof that the pinch swapped the surface.
      expect(find.textContaining('الفاتحة'), findsWidgets,
          reason: 'pinching a Hafs page should have reflowed it at $size');
      expect(find.byType(RichText), findsWidgets);
    }
  });
}

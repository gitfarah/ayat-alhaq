// Renders the Mushaf screen on its reflowing text edition. The point of
// that edition is that the script always fits the screen, so this test
// also asserts no layout overflows (the tester turns those into
// failures) at both a phone and a tablet width.

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
    SharedPreferences.setMockInitialValues({'mushafEdition': 'text'});
    MushafSvgService.setEdition('text');
  });
  tearDown(() => MushafSvgService.setEdition('hafs'));

  testWidgets('typesets the page it was opened on, portrait and landscape',
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

      // Al-Fatiha opens page 1: its name band and its ayah text.
      expect(find.textContaining('الفاتحة'), findsWidgets);
      expect(find.byType(RichText), findsWidgets);
    }
  });
}

// On-device smoke test — the one thing the unit suite cannot prove:
// that the app actually stands up on a real iOS/Android device, with
// its real bundled assets (the Quran text, the Uthmanic typeface) and
// its real plugins registered.
//
// Deliberately shallow. Anything that needs the network, audio, the
// store or location belongs in the unit suite with a fake, not here —
// a release build must never be blocked because a CI simulator had no
// connection. This asks one question: does it boot and draw?

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:quran_app_v1/screens/main_screen.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// pumpAndSettle is WRONG for this app: the reading surfaces show
  /// indefinite progress spinners, and an animation that never settles
  /// makes pumpAndSettle time out rather than report anything useful.
  /// Pumping fixed frames lets real asset I/O land instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(create: (_) => QuranAudioService()),
        ],
        child: const MaterialApp(home: MainScreen()),
      );

  testWidgets('the app boots on a real device and draws its navigation',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tab opens without throwing', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    // Icons rather than labels: the labels follow the UI language, the
    // tab order does not.
    for (final icon in const [
      Icons.draw_rounded, // التمييزات
      Icons.bookmark_border_rounded, // الفواصل
      Icons.check_circle_outline_rounded, // الختمة
      Icons.menu_book_outlined, // الفهرس
    ]) {
      final tab = find.byIcon(icon);
      if (tab.evaluate().isEmpty) continue; // already the active tab
      await tester.tap(tab);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'tapping $icon threw');
    }
  });
}

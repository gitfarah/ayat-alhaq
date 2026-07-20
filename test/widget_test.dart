// App smoke test: builds the real app root (with its providers) and
// verifies the main navigation renders. Replaces the Flutter template's
// counter test, which never matched this app and always failed.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:quran_app_v1/main.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  testWidgets('App builds and shows the bottom navigation tabs',
      (WidgetTester tester) async {
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

    // The Bismillah intro shows first on a cold start…
    expect(find.text('آيات الحق'), findsOneWidget);

    // …and gives way to the main navigation after its timer.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('الفهرس'), findsWidgets);
    expect(find.text('الفواصل'), findsOneWidget);
    expect(find.text('التمييزات'), findsOneWidget);
    expect(find.text('الختمة'), findsOneWidget);
  });
}

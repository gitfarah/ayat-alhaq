import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/screens/prayer_tools_screen.dart';
import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  testWidgets('Adhan settings offers both sound modes and prayer imagery',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'appLanguage': 'en',
      'adhanEnabled': false,
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsService(),
        child: MaterialApp(
          theme: ThemeData.light(useMaterial3: true),
          home: const AdhanSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Adhan'), findsOneWidget);
    expect(find.text('Device tone'), findsOneWidget);
    expect(find.byIcon(Icons.wb_twilight_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.wb_sunny_rounded), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(find.byIcon(Icons.nightlight_round), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:device_preview/device_preview.dart';
import 'services/settings_service.dart';
import 'services/quran_audio_service.dart';
import 'screens/main_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    // DevicePreview only wraps the app in debug builds (enabled: !kReleaseMode)
    // so end users running the real release app on their phone never see it —
    // it's purely a development-time tool for approximating other devices'
    // screen sizes while testing on Chrome/desktop.
    DevicePreview(
      enabled: !kReleaseMode,
      builder: (context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(create: (_) => QuranAudioService()),
        ],
        child: const QuranApp(),
      ),
    ),
  );
}

class QuranApp extends StatelessWidget {
  const QuranApp({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    return MaterialApp(
      title: 'آيات الحق',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: s.themeMode,
      // Required by device_preview so it can correctly simulate the
      // selected device's screen size, safe areas, and text scaling.
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,
      home: const MainScreen(),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_preview/device_preview.dart';
import 'services/settings_service.dart';
import 'services/quran_audio_service.dart';
import 'screens/main_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // All orientations are allowed — the Mushaf and reader both have
  // dedicated landscape layouts.
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
      home: const SplashGate(),
    );
  }
}

/// Shows the Bismillah intro exactly ONCE per app launch (a cold
/// start). Returning from the background keeps the widget tree alive,
/// so the splash never re-appears mid-session.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _done ? const MainScreen() : const _BismillahSplash(),
    );
  }
}

/// The intro itself: the Bismillah as classical calligraphy — the
/// Unicode ligature ﷽ rendered by the Amiri font — fading in over the
/// app's emerald/parchment backdrop.
class _BismillahSplash extends StatelessWidget {
  const _BismillahSplash();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFC9A64D);
    final bg = isDark
        ? const [Color(0xFF0E1F1A), Color(0xFF071310)]
        : const [Color(0xFFFBF7EE), Color(0xFFEFE7D5)];
    final ink = isDark ? gold : const Color(0xFF14453A);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
              center: const Alignment(0, -0.2), radius: 1.2, colors: bg),
        ),
        child: SafeArea(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (_, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The ligature's glyph is far larger than its font
                  // metrics suggest — FittedBox scales it to genuinely
                  // FIT the screen width and stay centered.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Text(
                        '﷽', // Bismillah ligature, calligraphic in Amiri
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Amiri',
                          fontSize: 84,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'آيات الحق',
                    style: TextStyle(
                      fontFamily: 'Amiri',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: ink.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:device_preview/device_preview.dart';
import 'services/settings_service.dart';
import 'services/quran_audio_service.dart';
import 'screens/main_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Enables true background playback with lock-screen / control-center
  // media controls. MUST run before any AudioPlayer is created.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.omar.ayat_alhaq.audio',
      androidNotificationChannelName: 'تلاوة القرآن',
      androidNotificationOngoing: true,
    );
  } catch (_) {
    // Never let audio-session setup block app startup.
  }
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
      // Drives the app's text DIRECTION: Arabic → RTL, English/German →
      // LTR. Everything not explicitly overridden follows this.
      locale: Locale(s.effectiveLanguage),
      supportedLocales: const [Locale('ar'), Locale('en'), Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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

/// The intro: the Bismillah in classical calligraphy above the brand
/// logo, on the logo's own deep-teal background so the two blend
/// seamlessly. Fades in on a cold start.
class _BismillahSplash extends StatelessWidget {
  const _BismillahSplash();

  /// The logo's background colour — used for the whole splash so the
  /// logo image sits edge-to-edge with no visible box.
  static const Color _brandGreen = Color(0xFF315052);
  static const Color _gold = Color(0xFFE9B85A);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: _brandGreen,
      body: SafeArea(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Bismillah ligature (its glyph is far larger than its
                // font metrics, so FittedBox scales it to fit).
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 64),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Text(
                      '﷽',
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 56,
                        color: _gold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Brand logo — same green background, so it blends in.
                Image.asset('assets/icon/logo.png', width: w * 0.82),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

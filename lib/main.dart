import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:device_preview/device_preview.dart';
import 'services/settings_service.dart';
import 'services/quran_audio_service.dart';
import 'services/adhan_notification_service.dart';
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
  } catch (e) {
    // Never let audio-session setup block app startup — but a silent
    // catch here once hid the actual reason recitation didn't work on
    // an Android device for an entire debugging round: nothing in the
    // app could tell playback failure apart from this failing quietly
    // at launch. Recorded so the FIRST play attempt can name it instead
    // of guessing at "check your connection".
    QuranAudioService.backgroundInitFailure = e;
  }
  try {
    await AdhanNotificationService.initialize();
  } catch (_) {
    // Notification setup must never prevent the Quran from opening.
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

/// The intro: the Bismillah calligraphy (large) above the brand
/// wordmark (smaller), on the Bismillah image's own dark-green
/// background so the artwork sits edge-to-edge with no visible box.
/// Fades in on a cold start.
class _BismillahSplash extends StatelessWidget {
  const _BismillahSplash();

  /// Matches the Bismillah artwork's background so the splash blends.
  static const Color _bismillahGreen = Color(0xFF064D47);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: _bismillahGreen,
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
                // Bismillah artwork — same green background, blends in.
                Image.asset('assets/icon/bismillah.png', width: w * 0.80),
                const SizedBox(height: 20),
                // Brand wordmark, deliberately SMALLER than the
                // Bismillah (transparent background so no box shows).
                Image.asset('assets/icon/logo_transparent.png',
                    width: w * 0.42),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

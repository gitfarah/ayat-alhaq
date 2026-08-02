import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps the display fully lit while a reading surface is open — the
/// screen neither dims nor sleeps, the way a PDF reader behaves during
/// a long read. Android sets FLAG_KEEP_SCREEN_ON on the window, iOS
/// disables the idle timer; both are the platform's own "stay awake",
/// so brightness is never touched.
///
/// Reference-counted: the Mushaf and the reader can be stacked (opening
/// a mark from the Highlights tab pushes one on top of the other), and
/// the lock is only released once the last of them is gone.
class ScreenAwake {
  static const MethodChannel _channel =
      MethodChannel('com.omar.quran_app_v1/screen_awake');

  static int _holders = 0;
  static bool _applied = false;
  static _LifecycleWatcher? _watcher;

  static Future<void> acquire() async {
    _holders++;
    _watcher ??= _LifecycleWatcher()..attach();
    await _apply(true);
  }

  static Future<void> release() async {
    if (_holders > 0) _holders--;
    if (_holders == 0) await _apply(false);
  }

  static Future<void> _apply(bool on) async {
    if (on == _applied) return;
    // Recorded BEFORE the await: two screens opening together (the
    // Mushaf pushing the reader) both reach here, and checking a flag
    // only set afterwards would let both send the same call.
    _applied = on;
    try {
      await _channel.invokeMethod<void>('setKeepAwake', {'enabled': on});
    } on MissingPluginException {
      // Web/desktop or an older shell without the native side — the app
      // must keep working, it just won't hold the screen on.
    } on PlatformException {
      // Same: cosmetic capability, never fatal.
    }
  }

  /// iOS keeps `isIdleTimerDisabled` set across backgrounding, which
  /// would leak the lock into other apps; drop it while we're away and
  /// take it back on return if a reading screen is still open.
  static Future<void> _onLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      if (_holders > 0) await _apply(true);
    } else {
      if (_applied) await _apply(false);
    }
  }
}

class _LifecycleWatcher with WidgetsBindingObserver {
  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ScreenAwake._onLifecycle(state);
  }
}

/// Mix into a reading screen's State to hold the screen awake for
/// exactly as long as that screen is alive.
mixin KeepsScreenAwake<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    ScreenAwake.acquire();
  }

  @override
  void dispose() {
    ScreenAwake.release();
    super.dispose();
  }
}

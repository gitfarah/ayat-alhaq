import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android permissions a RELEASE build needs.
///
/// Flutter puts android.permission.INTERNET in the debug-only manifest,
/// so every network call works while developing and fails on a released
/// APK with "Failed host lookup (errno = 7)". That took a build on a
/// real phone to notice: downloads, translations, tafsir, recitation
/// audio and prayer times were all dead at once, and nothing in the
/// tests or the analyzer said a word.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  bool declares(String permission) => manifest
      .contains('<uses-permission android:name="android.permission.$permission"');

  test('the main manifest declares INTERNET, not just the debug one', () {
    expect(declares('INTERNET'), isTrue,
        reason: 'Without INTERNET in the MAIN manifest every network '
            'request fails in a release build.');
  });

  test('network state can be checked', () {
    expect(declares('ACCESS_NETWORK_STATE'), isTrue);
  });

  test('the permissions the app already relied on are still there', () {
    for (final p in [
      'ACCESS_COARSE_LOCATION',
      'ACCESS_FINE_LOCATION',
      'POST_NOTIFICATIONS',
      'WAKE_LOCK',
      'FOREGROUND_SERVICE',
      'FOREGROUND_SERVICE_MEDIA_PLAYBACK',
    ]) {
      expect(declares(p), isTrue, reason: '$p went missing from the manifest');
    }
  });
}

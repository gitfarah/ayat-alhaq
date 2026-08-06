import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/build_info.dart';

/// build_info.dart asks to be kept equal to pubspec's version, because
/// the two are read by different things: the store and the OS use
/// pubspec's `+N`, while the About screen and bug reports quote
/// build_info. Nothing enforced it, so they drifted six builds apart and
/// a shipped APK described itself as a build it was not.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version =
      RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)', multiLine: true)
          .firstMatch(pubspec)!;

  test('the build number matches the one the store and OS see', () {
    expect(kBuildNumber, int.parse(version.group(2)!),
        reason: 'lib/build_info.dart and pubspec.yaml disagree — the About '
            'screen would quote a build number the APK does not have.');
  });

  test('the marketing version matches too', () {
    expect(kAppVersion, version.group(1));
  });

  test('the label reads as version (build)', () {
    expect(kVersionLabel, '$kAppVersion ($kBuildNumber)');
  });
}

// The continue card used to prefer the verse-by-verse reader whenever
// it had a saved surah, so a Mushaf reader who had once opened the
// reader could never be taken back to their page. Both surfaces record
// their own position; lastReadWasMushaf is what decides which to resume.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A service with its stored settings already read back in.
  Future<SettingsService> loaded() async {
    final s = SettingsService();
    // The constructor's load is async; let it finish before asserting.
    for (var i = 0; i < 20 && s.lastMode == null && !s.hasLastRead; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
    return s;
  }

  test('a fresh install has nothing to continue', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await loaded();
    expect(s.hasLastRead, isFalse);
  });

  test('reading in the Mushaf resumes the Mushaf', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await loaded();
    await s.saveLastRead(page: 77, mode: SettingsService.modeMushaf);
    expect(s.lastReadWasMushaf, isTrue);
    expect(s.lastPage, 77);
  });

  test('reading in the reader resumes the reader', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await loaded();
    await s.saveLastRead(
        surah: 8, ayah: 3, mode: SettingsService.modeReader);
    expect(s.lastReadWasMushaf, isFalse);
    expect(s.lastSurah, 8);
    expect(s.lastAyah, 3);
  });

  test('the Mushaf wins after the reader — the reported bug', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await loaded();
    await s.saveLastRead(
        surah: 8, ayah: 3, mode: SettingsService.modeReader);
    await s.saveLastRead(page: 77, mode: SettingsService.modeMushaf);
    expect(s.lastReadWasMushaf, isTrue,
        reason: 'the Mushaf was read last, so it is what continues');
    // The reader's position is not thrown away by switching.
    expect(s.lastSurah, 8);
    expect(s.lastAyah, 3);
  });

  test('switching back to the reader flips it again', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await loaded();
    await s.saveLastRead(page: 77, mode: SettingsService.modeMushaf);
    await s.saveLastRead(
        surah: 2, ayah: 255, mode: SettingsService.modeReader);
    expect(s.lastReadWasMushaf, isFalse);
    expect(s.lastPage, 77, reason: 'the Mushaf page is still remembered');
  });

  group('upgrading from a build that recorded no mode', () {
    test('a saved page alone resumes the Mushaf', () async {
      SharedPreferences.setMockInitialValues({'lastPage': 120});
      final s = await loaded();
      expect(s.lastMode, isNull);
      expect(s.lastReadWasMushaf, isTrue);
    });

    test('a saved surah resumes the reader', () async {
      SharedPreferences.setMockInitialValues({'lastSurah': 5, 'lastAyah': 9});
      final s = await loaded();
      expect(s.lastMode, isNull);
      expect(s.lastReadWasMushaf, isFalse);
    });
  });

  test('the chosen mode survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await loaded();
    await first.saveLastRead(page: 300, mode: SettingsService.modeMushaf);

    final second = await loaded();
    expect(second.lastReadWasMushaf, isTrue);
    expect(second.lastPage, 300);
  });
}

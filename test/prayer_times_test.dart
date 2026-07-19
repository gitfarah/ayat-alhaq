import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/prayer_service.dart';

void main() {
  const times = PrayerTimes(
    fajr: '04:30',
    dhuhr: '13:10',
    asr: '17:00',
    maghrib: '20:45',
    isha: '22:15',
  );

  test('before Fajr → next is Fajr', () {
    expect(times.nextPrayerIndex(DateTime(2026, 7, 16, 3, 0)), 0);
  });

  test('mid-day → next is Asr', () {
    expect(times.nextPrayerIndex(DateTime(2026, 7, 16, 14, 0)), 2);
  });

  test('right before Isha → next is Isha', () {
    expect(times.nextPrayerIndex(DateTime(2026, 7, 16, 22, 14)), 4);
  });

  test('after Isha → null (next is tomorrow)', () {
    expect(times.nextPrayerIndex(DateTime(2026, 7, 16, 23, 30)), isNull);
  });

  test('serialization round-trip', () {
    final restored = PrayerTimes.fromJson(times.toJson());
    expect(restored.all, times.all);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'prayer_service.dart';

enum AdhanSoundMode { adhan, device }

/// Persists Adhan choices and schedules sound-enabled prayer reminders.
/// Notifications are refreshed whenever today's prayer times are loaded.
class AdhanNotificationService {
  static const prayerKeys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
  static const _masterKey = 'adhanEnabled';
  static const _soundModeKey = 'adhanSoundMode';
  static const _prayerPrefix = 'adhanPrayer_';
  static const _notificationBaseId = 7100;

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get _supportsMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() async {
    if (_initialized || !_supportsMobile) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(settings: settings);
    _initialized = true;
  }

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_masterKey) ?? false;

  static Future<AdhanSoundMode> soundMode() async {
    final value =
        (await SharedPreferences.getInstance()).getString(_soundModeKey);
    return AdhanSoundMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AdhanSoundMode.device,
    );
  }

  static Future<Map<String, bool>> prayerChoices() async {
    final p = await SharedPreferences.getInstance();
    return {
      for (final key in prayerKeys)
        key: p.getBool('$_prayerPrefix$key') ?? true,
    };
  }

  static Future<bool> setEnabled(bool enabled) async {
    await initialize();
    if (enabled && (!_supportsMobile || !await _requestPermission())) {
      return false;
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool(_masterKey, enabled);
    if (!enabled) await cancelAll();
    return true;
  }

  static Future<void> setSoundMode(AdhanSoundMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_soundModeKey, mode.name);
  }

  static Future<void> setPrayerEnabled(String prayer, bool enabled) async {
    if (!prayerKeys.contains(prayer)) return;
    final p = await SharedPreferences.getInstance();
    await p.setBool('$_prayerPrefix$prayer', enabled);
    if (!enabled && _supportsMobile) {
      await initialize();
      await _notifications.cancel(
          id: _notificationBaseId + prayerKeys.indexOf(prayer));
    }
  }

  static Future<bool> _requestPermission() async {
    if (!_supportsMobile) return false;
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await android?.requestNotificationsPermission();
    final ios = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: false,
      sound: true,
    );
    return androidGranted ?? iosGranted ?? true;
  }

  static Future<void> cancelAll() async {
    if (!_supportsMobile) return;
    await initialize();
    for (var i = 0; i < prayerKeys.length; i++) {
      await _notifications.cancel(id: _notificationBaseId + i);
    }
  }

  /// Schedules the remaining prayers today. The UTC conversion preserves
  /// the exact local instant without requiring a timezone lookup plugin.
  static Future<void> syncToday(PrayerTimes times, String language) async {
    if (!_supportsMobile || !await isEnabled()) return;
    await initialize();
    final selected = await prayerChoices();
    final mode = await soundMode();
    final useAdhan = mode == AdhanSoundMode.adhan;
    final now = DateTime.now();
    final names = _names(language);

    for (var i = 0; i < prayerKeys.length; i++) {
      final id = _notificationBaseId + i;
      await _notifications.cancel(id: id);
      if (!(selected[prayerKeys[i]] ?? true)) continue;
      final parts = times.all[i].split(':');
      final localTime = DateTime(now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]));
      if (!localTime.isAfter(now)) continue;
      final scheduled = tz.TZDateTime.from(localTime.toUtc(), tz.UTC);
      await _notifications.zonedSchedule(
        id: id,
        title: _title(language),
        body: _body(language, names[i]),
        scheduledDate: scheduled,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            useAdhan ? 'adhan_prayer_times_adhan' : 'adhan_prayer_times_device',
            _channelName(language),
            channelDescription: _channelDescription(language),
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: useAdhan
                ? const RawResourceAndroidNotificationSound('adhan')
                : null,
            category: AndroidNotificationCategory.alarm,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            sound: useAdhan ? 'adhan.wav' : null,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static List<String> _names(String lang) => lang == 'ar'
      ? ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء']
      : lang == 'de'
          ? ['Fadschr', 'Dhuhr', 'Asr', 'Maghrib', 'Ischa']
          : ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

  static String _title(String lang) => lang == 'ar'
      ? 'حان وقت الصلاة'
      : lang == 'de'
          ? 'Es ist Gebetszeit'
          : 'It is time for prayer';

  static String _body(String lang, String prayer) => lang == 'ar'
      ? 'حان الآن وقت صلاة $prayer'
      : lang == 'de'
          ? 'Jetzt ist Zeit für das $prayer-Gebet'
          : 'It is now time for $prayer prayer';

  static String _channelName(String lang) => lang == 'ar'
      ? 'تنبيهات الأذان'
      : (lang == 'de' ? 'Adhan-Hinweise' : 'Adhan alerts');

  static String _channelDescription(String lang) => lang == 'ar'
      ? 'تنبيه صوتي عند دخول وقت الصلاة'
      : lang == 'de'
          ? 'Akustische Hinweise zu den Gebetszeiten'
          : 'Sound alerts when prayer time begins';
}

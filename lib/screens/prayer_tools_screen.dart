import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../services/adhan_notification_service.dart';
import '../services/prayer_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/prayer_visuals.dart';

String _text(String lang, String ar, String en, String de) =>
    lang == 'ar' ? ar : (lang == 'de' ? de : en);

void showPrayerTools(BuildContext context) {
  final settings = context.read<SettingsService>();
  final lang = settings.effectiveLanguage;
  final isDark = settings.isDarkIn(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _text(lang, 'أدوات الصلاة', 'Prayer tools', 'Gebetswerkzeuge'),
              style: const TextStyle(
                fontFamily: '.SF Pro Text',
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _ToolCard(
            icon: Icons.notifications_active_rounded,
            title:
                _text(lang, 'تنبيهات الأذان', 'Adhan alerts', 'Adhan-Hinweise'),
            subtitle: _text(
              lang,
              'اختر الصلوات والتنبيه الصوتي',
              'Choose prayers and sound alerts',
              'Gebete und Tonhinweise auswählen',
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdhanSettingsScreen()));
            },
          ),
          const SizedBox(height: 10),
          _ToolCard(
            icon: Icons.explore_rounded,
            title:
                _text(lang, 'بوصلة القبلة', 'Qiblah compass', 'Qibla-Kompass'),
            subtitle: _text(
              lang,
              'اعرف اتجاه الكعبة من موقعك الحالي',
              'Find the Kaaba direction from your location',
              'Richtung der Kaaba vom aktuellen Standort',
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const QiblahCompassScreen()));
            },
          ),
        ]),
      ),
    ),
  );
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 27),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      )),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: accent),
          ]),
        ),
      ),
    );
  }
}

class AdhanSettingsScreen extends StatefulWidget {
  const AdhanSettingsScreen({super.key});

  @override
  State<AdhanSettingsScreen> createState() => _AdhanSettingsScreenState();
}

class _AdhanSettingsScreenState extends State<AdhanSettingsScreen> {
  bool _loading = true;
  bool _enabled = false;
  AdhanSoundMode _soundMode = AdhanSoundMode.device;
  Map<String, bool> _prayers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      AdhanNotificationService.isEnabled(),
      AdhanNotificationService.soundMode(),
      AdhanNotificationService.prayerChoices(),
    ]);
    if (!mounted) return;
    setState(() {
      _enabled = values[0] as bool;
      _soundMode = values[1] as AdhanSoundMode;
      _prayers = values[2] as Map<String, bool>;
      _loading = false;
    });
  }

  Future<void> _reschedule() async {
    if (!_enabled) return;
    final times = await PrayerService.getTodayTimes();
    if (times != null && mounted) {
      await AdhanNotificationService.syncToday(
          times, context.read<SettingsService>().effectiveLanguage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final lang = settings.effectiveLanguage;
    final dark = settings.isDarkIn(context);
    final accent = dark ? AppColors.darkPrimary : AppColors.primary;
    final names = [
      _text(lang, 'الفجر', 'Fajr', 'Fadschr'),
      _text(lang, 'الظهر', 'Dhuhr', 'Dhuhr'),
      _text(lang, 'العصر', 'Asr', 'Asr'),
      _text(lang, 'المغرب', 'Maghrib', 'Maghrib'),
      _text(lang, 'العشاء', 'Isha', 'Ischa'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
            _text(lang, 'تنبيهات الأذان', 'Adhan alerts', 'Adhan-Hinweise')),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsCard(
                  child: SwitchListTile.adaptive(
                    value: _enabled,
                    activeTrackColor: accent,
                    secondary:
                        Icon(Icons.notifications_active_rounded, color: accent),
                    title: Text(_text(lang, 'تفعيل تنبيهات الصلاة',
                        'Enable prayer alerts', 'Gebetshinweise aktivieren')),
                    subtitle: Text(_text(
                      lang,
                      'يصلك تنبيه عند دخول وقت الصلاة',
                      'Receive an alert when prayer time begins',
                      'Hinweis erhalten, wenn die Gebetszeit beginnt',
                    )),
                    onChanged: (value) async {
                      final granted =
                          await AdhanNotificationService.setEnabled(value);
                      if (!context.mounted) return;
                      setState(() => _enabled = value && granted);
                      if (value && !granted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(_text(
                            lang,
                            'يرجى السماح بالإشعارات من إعدادات الجهاز',
                            'Please allow notifications in device settings',
                            'Bitte Benachrichtigungen in den Geräteeinstellungen erlauben',
                          )),
                        ));
                      } else {
                        await _reschedule();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _text(lang, 'صوت التنبيه', 'Alert sound', 'Hinweiston'),
                  style: const TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _SoundChoice(
                      icon: Icons.mosque_rounded,
                      color: Theme.of(context).colorScheme.secondary,
                      title: _text(lang, 'الأذان', 'Adhan', 'Adhan'),
                      subtitle: _text(lang, 'نغمة أذان مضمّنة',
                          'Built-in Adhan tune', 'Integrierter Adhan'),
                      selected: _soundMode == AdhanSoundMode.adhan,
                      enabled: _enabled,
                      onTap: () async {
                        setState(() => _soundMode = AdhanSoundMode.adhan);
                        await AdhanNotificationService.setSoundMode(
                            AdhanSoundMode.adhan);
                        await _reschedule();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SoundChoice(
                      icon: Icons.phone_android_rounded,
                      color: Theme.of(context).colorScheme.tertiary,
                      title: _text(
                          lang, 'نغمة الجهاز', 'Device tone', 'Geräteton'),
                      subtitle: _text(lang, 'صوت الإشعار المعتاد',
                          'Normal notification tone', 'Normaler Hinweiston'),
                      selected: _soundMode == AdhanSoundMode.device,
                      enabled: _enabled,
                      onTap: () async {
                        setState(() => _soundMode = AdhanSoundMode.device);
                        await AdhanNotificationService.setSoundMode(
                            AdhanSoundMode.device);
                        await _reschedule();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                Text(
                  _text(lang, 'اختر الصلوات', 'Choose prayers',
                      'Gebete auswählen'),
                  style: const TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _SettingsCard(
                  child: Column(
                    children: [
                      for (var i = 0;
                          i < AdhanNotificationService.prayerKeys.length;
                          i++) ...[
                        SwitchListTile.adaptive(
                          value: _prayers[
                                  AdhanNotificationService.prayerKeys[i]] ??
                              true,
                          activeTrackColor: PrayerVisuals.colors[i],
                          secondary: Icon(
                            PrayerVisuals.icons[i],
                            color: PrayerVisuals.colors[i],
                          ),
                          title: Text(names[i]),
                          onChanged: _enabled
                              ? (value) async {
                                  final key =
                                      AdhanNotificationService.prayerKeys[i];
                                  setState(() => _prayers[key] = value);
                                  await AdhanNotificationService
                                      .setPrayerEnabled(key, value);
                                  await _reschedule();
                                }
                              : null,
                        ),
                        if (i < 4) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _text(
                    lang,
                    'تُحدَّث التنبيهات تلقائياً عند تحديث مواقيت الصلاة. قد تؤخر بعض الأجهزة التنبيه قليلاً بسبب توفير البطارية.',
                    'Alerts refresh automatically with prayer times. Battery saving on some devices may delay an alert slightly.',
                    'Hinweise werden automatisch mit den Gebetszeiten aktualisiert. Der Energiesparmodus kann sie leicht verzögern.',
                  ),
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 12.5,
                    height: 1.45,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

class _SoundChoice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _SoundChoice({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effective = enabled ? color : Theme.of(context).disabledColor;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: selected
            ? effective.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(
                color: selected ? effective : Theme.of(context).dividerColor,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: effective, size: 23),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontWeight: FontWeight.bold,
                        color: selected ? effective : null,
                      )),
                ),
              ]),
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 11.5,
                    height: 1.25,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class QiblahCompassScreen extends StatefulWidget {
  const QiblahCompassScreen({super.key});

  @override
  State<QiblahCompassScreen> createState() => _QiblahCompassScreenState();
}

class _QiblahCompassScreenState extends State<QiblahCompassScreen> {
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _heading;
  double? _bearing;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _QiblahError('locationOff');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _QiblahError('locationDenied');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final bearing = _qiblahBearing(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _bearing = bearing;
        _loading = false;
      });
      _compassSubscription = FlutterCompass.events?.listen((event) {
        if (mounted) setState(() => _heading = event.heading);
      });
    } on _QiblahError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'unavailable';
          _loading = false;
        });
      }
    }
  }

  static double _qiblahBearing(double latitude, double longitude) {
    const kaabaLat = 21.422487;
    const kaabaLng = 39.826206;
    double radians(double value) => value * math.pi / 180;
    final lat1 = radians(latitude);
    final lat2 = radians(kaabaLat);
    final deltaLng = radians(kaabaLng - longitude);
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final lang = settings.effectiveLanguage;
    final dark = settings.isDarkIn(context);
    final accent = dark ? AppColors.darkPrimary : AppColors.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _text(lang, 'بوصلة القبلة', 'Qiblah compass', 'Qibla-Kompass')),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : _error != null
              ? _errorView(lang, accent)
              : _compassView(lang, accent, dark),
    );
  }

  Widget _errorView(String lang, Color accent) {
    final message = _error == 'locationOff'
        ? _text(
            lang,
            'فعّل خدمة الموقع لاستخدام بوصلة القبلة.',
            'Turn on location services to use the Qiblah compass.',
            'Aktiviere die Ortungsdienste für den Qibla-Kompass.')
        : _error == 'locationDenied'
            ? _text(
                lang,
                'اسمح بالوصول إلى الموقع لحساب اتجاه القبلة.',
                'Allow location access to calculate the Qiblah direction.',
                'Erlaube den Standortzugriff, um die Qibla zu berechnen.')
            : _text(
                lang,
                'تعذّر تحديد اتجاه القبلة على هذا الجهاز.',
                'The Qiblah direction could not be determined on this device.',
                'Die Qibla-Richtung konnte nicht bestimmt werden.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_off_rounded, size: 64, color: accent),
          const SizedBox(height: 18),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: '.SF Pro Text', height: 1.5)),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _start();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
                _text(lang, 'إعادة المحاولة', 'Try again', 'Erneut versuchen')),
          ),
        ]),
      ),
    );
  }

  Widget _compassView(String lang, Color accent, bool dark) {
    final heading = _heading;
    final bearing = _bearing!;
    final delta = heading == null ? 0.0 : (bearing - heading) * math.pi / 180;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(children: [
          Text(
            _text(
                lang,
                'وجّه أعلى الهاتف نحو السهم',
                'Point the top of your phone along the arrow',
                'Richte die Oberkante des Handys am Pfeil aus'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: '.SF Pro Text',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(builder: (_, constraints) {
              final size = constraints.maxWidth;
              return Stack(alignment: Alignment.center, children: [
                Transform.rotate(
                  angle: heading == null ? 0 : -heading * math.pi / 180,
                  child: CustomPaint(
                    size: Size.square(size),
                    painter: _CompassDialPainter(
                      accent: accent,
                      foreground:
                          dark ? AppColors.darkText : AppColors.textPrimary,
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: delta,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.navigation_rounded,
                        size: size * 0.25, color: accent),
                    SizedBox(height: size * 0.16),
                  ]),
                ),
                Container(
                  width: size * 0.17,
                  height: size * 0.17,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.3),
                        blurRadius: 18,
                      )
                    ],
                  ),
                  child: const Icon(Icons.mosque_rounded, color: Colors.white),
                ),
              ]);
            }),
          ),
          const Spacer(),
          Text(
            '${bearing.round()}°',
            style: TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            heading == null
                ? _text(
                    lang,
                    'لا يتوفر مستشعر بوصلة — الزاوية محسوبة من الشمال',
                    'No compass sensor — bearing is measured from north',
                    'Kein Kompasssensor — Winkel wird ab Norden gemessen')
                : _text(lang, 'اتجاه القبلة من الشمال',
                    'Qiblah bearing from north', 'Qibla-Winkel von Norden'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: '.SF Pro Text',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ]),
      ),
    );
  }
}

class _QiblahError implements Exception {
  final String code;
  const _QiblahError(this.code);
}

class _CompassDialPainter extends CustomPainter {
  final Color accent;
  final Color foreground;
  const _CompassDialPainter({required this.accent, required this.foreground});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    canvas.drawCircle(
        center, radius, Paint()..color = accent.withValues(alpha: 0.08));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = accent.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < 72; i++) {
      final angle = i * 5 * math.pi / 180 - math.pi / 2;
      final major = i % 18 == 0;
      final medium = i % 6 == 0;
      final length = major ? 18.0 : (medium ? 12.0 : 6.0);
      final outer = Offset(center.dx + math.cos(angle) * (radius - 8),
          center.dy + math.sin(angle) * (radius - 8));
      final inner = Offset(center.dx + math.cos(angle) * (radius - 8 - length),
          center.dy + math.sin(angle) * (radius - 8 - length));
      canvas.drawLine(
        outer,
        inner,
        Paint()
          ..color = major ? accent : foreground.withValues(alpha: 0.45)
          ..strokeWidth = major ? 3 : 1.3
          ..strokeCap = StrokeCap.round,
      );
    }
    const labels = ['N', 'E', 'S', 'W'];
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2 - math.pi / 2;
      final offset = Offset(center.dx + math.cos(angle) * (radius - 38),
          center.dy + math.sin(angle) * (radius - 38));
      final painter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: i == 0 ? accent : foreground,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
          canvas, offset - Offset(painter.width / 2, painter.height / 2));
    }
  }

  @override
  bool shouldRepaint(_CompassDialPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.foreground != foreground;
}

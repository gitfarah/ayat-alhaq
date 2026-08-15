import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'library_events.dart';

/// One day's five prayer times, as "HH:mm" 24h strings.
class PrayerTimes {
  final String fajr, dhuhr, asr, maghrib, isha;

  const PrayerTimes({
    required this.fajr,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  List<String> get all => [fajr, dhuhr, asr, maghrib, isha];

  static const names = ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء'];

  Map<String, dynamic> toJson() => {
        'fajr': fajr,
        'dhuhr': dhuhr,
        'asr': asr,
        'maghrib': maghrib,
        'isha': isha,
      };

  factory PrayerTimes.fromJson(Map<String, dynamic> j) => PrayerTimes(
        fajr: j['fajr'],
        dhuhr: j['dhuhr'],
        asr: j['asr'],
        maghrib: j['maghrib'],
        isha: j['isha'],
      );

  /// Index (0-4) of the next upcoming prayer relative to [now], or null
  /// when today's prayers are all past (i.e. next is tomorrow's Fajr).
  int? nextPrayerIndex(DateTime now) {
    for (var i = 0; i < all.length; i++) {
      final parts = all[i].split(':');
      final t = DateTime(now.year, now.month, now.day, int.parse(parts[0]),
          int.parse(parts[1]));
      if (t.isAfter(now)) return i;
    }
    return null;
  }

  /// Index (0-4) of the prayer whose time we are currently INSIDE — the
  /// last one called, which is what the hour outside actually looks
  /// like. [nextPrayerIndex] answers the opposite question.
  ///
  /// The night wraps at both ends: before Fajr and after Isha are the
  /// same stretch of night, and both report Isha.
  int currentPrayerIndex(DateTime now) {
    final next = nextPrayerIndex(now);
    if (next == null) return 4; // after Isha — still tonight
    return (next - 1 + 5) % 5; // before Fajr wraps back to Isha
  }
}

class PrayerCity {
  final String label; // Arabic display name
  final String city; // API value
  final String country; // API value
  const PrayerCity(this.label, this.city, this.country);
}

/// Fetches and caches daily prayer times from api.aladhan.com for a
/// user-selected city (no location permission needed).
class PrayerService {
  static const List<PrayerCity> cities = [
    PrayerCity('مكة المكرمة', 'Makkah', 'Saudi Arabia'),
    PrayerCity('المدينة المنورة', 'Medina', 'Saudi Arabia'),
    PrayerCity('الرياض', 'Riyadh', 'Saudi Arabia'),
    PrayerCity('جدة', 'Jeddah', 'Saudi Arabia'),
    PrayerCity('القاهرة', 'Cairo', 'Egypt'),
    PrayerCity('الإسكندرية', 'Alexandria', 'Egypt'),
    PrayerCity('عمّان', 'Amman', 'Jordan'),
    PrayerCity('دمشق', 'Damascus', 'Syria'),
    PrayerCity('بغداد', 'Baghdad', 'Iraq'),
    PrayerCity('الكويت', 'Kuwait City', 'Kuwait'),
    PrayerCity('الدوحة', 'Doha', 'Qatar'),
    PrayerCity('دبي', 'Dubai', 'UAE'),
    PrayerCity('أبوظبي', 'Abu Dhabi', 'UAE'),
    PrayerCity('مسقط', 'Muscat', 'Oman'),
    PrayerCity('المنامة', 'Manama', 'Bahrain'),
    PrayerCity('صنعاء', 'Sanaa', 'Yemen'),
    PrayerCity('الخرطوم', 'Khartoum', 'Sudan'),
    PrayerCity('الرباط', 'Rabat', 'Morocco'),
    PrayerCity('الدار البيضاء', 'Casablanca', 'Morocco'),
    PrayerCity('الجزائر', 'Algiers', 'Algeria'),
    PrayerCity('تونس', 'Tunis', 'Tunisia'),
    PrayerCity('طرابلس', 'Tripoli', 'Libya'),
    PrayerCity('بيروت', 'Beirut', 'Lebanon'),
    PrayerCity('إسطنبول', 'Istanbul', 'Turkey'),
    PrayerCity('برلين', 'Berlin', 'Germany'),
    PrayerCity('هامبورغ', 'Hamburg', 'Germany'),
    PrayerCity('ميونخ', 'Munich', 'Germany'),
    PrayerCity('فرانكفورت', 'Frankfurt', 'Germany'),
    PrayerCity('كولونيا', 'Cologne', 'Germany'),
    PrayerCity('لندن', 'London', 'UK'),
    PrayerCity('باريس', 'Paris', 'France'),
    PrayerCity('أمستردام', 'Amsterdam', 'Netherlands'),
    PrayerCity('فيينا', 'Vienna', 'Austria'),
    PrayerCity('نيويورك', 'New York', 'USA'),
    PrayerCity('جاكرتا', 'Jakarta', 'Indonesia'),
    PrayerCity('كوالالمبور', 'Kuala Lumpur', 'Malaysia'),
    PrayerCity('إسلام أباد', 'Islamabad', 'Pakistan'),
    PrayerCity('كراتشي', 'Karachi', 'Pakistan'),
  ];

  /// aladhan calculation methods (id → Arabic label).
  static const Map<int, String> methods = {
    3: 'رابطة العالم الإسلامي',
    4: 'أم القرى (مكة)',
    5: 'الهيئة المصرية العامة للمساحة',
    1: 'جامعة العلوم الإسلامية، كراتشي',
    2: 'الجمعية الإسلامية لأمريكا الشمالية',
    8: 'الخليج',
    12: 'ديانة (تركيا)',
  };

  static const Map<int, String> _methodsEn = {
    3: 'Muslim World League',
    4: 'Umm al-Qura (Makkah)',
    5: 'Egyptian General Authority',
    1: 'Univ. of Islamic Sciences, Karachi',
    2: 'ISNA (North America)',
    8: 'Gulf Region',
    12: 'Diyanet (Turkey)',
  };

  /// Calculation-method label in the app language (Arabic name for
  /// 'ar', an English name otherwise).
  static String methodName(int id, String lang) => lang == 'ar'
      ? (methods[id] ?? '')
      : (_methodsEn[id] ?? methods[id] ?? '');

  /// Selected city, or null when unconfigured OR in GPS mode.
  static Future<PrayerCity?> selectedCity() async {
    final p = await SharedPreferences.getInstance();
    if (p.getString('prayerMode') == 'gps') return null;
    final city = p.getString('prayerCity');
    if (city == null) return null;
    for (final c in cities) {
      if (c.city == city) return c;
    }
    return null;
  }

  static Future<bool> isGpsMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('prayerMode') == 'gps';
  }

  static String _myLocation(String lang) => lang == 'ar'
      ? 'موقعي الحالي'
      : (lang == 'de' ? 'Mein Standort' : 'My location');

  /// Display label for the configured location IN [lang]:
  /// - City mode: the Arabic name for 'ar', otherwise the city's
  ///   English name.
  /// - GPS mode: the actual city name reverse-geocoded from the saved
  ///   coordinates in the requested language (cached), falling back to
  ///   a generic "my location" if geocoding is unavailable.
  /// Returns null when nothing is configured yet.
  static Future<String?> locationLabel(String lang) async {
    final p = await SharedPreferences.getInstance();
    if (await isGpsMode()) {
      final lat = p.getDouble('prayerLat');
      final lng = p.getDouble('prayerLng');
      if (lat == null || lng == null) return null;
      final key =
          'gpsName_${lang}_${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';
      final cached = p.getString(key);
      if (cached != null && cached.isNotEmpty) return cached;
      try {
        final name = await _reverseGeocode(lat, lng, lang);
        if (name.isNotEmpty) {
          await p.setString(key, name);
          await p.setString('gpsNameAny', name);
          return name;
        }
      } catch (_) {
        // Offline or geocoder unavailable — use a fallback below.
      }
      return p.getString('gpsNameAny') ?? _myLocation(lang);
    }
    final city = await selectedCity();
    if (city == null) return null;
    return lang == 'ar' ? city.label : city.city;
  }

  /// Reverse-geocodes coordinates to a city name in [lang] via the
  /// OpenStreetMap Nominatim service (no extra dependency, localized
  /// through the accept-language parameter).
  static Future<String> _reverseGeocode(
      double lat, double lng, String lang) async {
    final url =
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&zoom=10&accept-language=$lang';
    final r = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'AyatAlHaq/1.0 (quran prayer times)'
    }).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('geocode failed');
    final data = jsonDecode(r.body);
    final addr = (data['address'] ?? {}) as Map<String, dynamic>;
    return (addr['city'] ??
            addr['town'] ??
            addr['village'] ??
            addr['municipality'] ??
            addr['county'] ??
            addr['state'] ??
            data['name'] ??
            '')
        .toString();
  }

  static Future<int> selectedMethod() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('prayerMethod') ?? 3;
  }

  static Future<void> setCity(PrayerCity city) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('prayerCity', city.city);
    await p.setString('prayerMode', 'city');
    LibraryEvents.prayer.ping();
  }

  /// Switches to GPS mode: asks for location permission (browser
  /// prompt on web, system dialog on phones), stores the coordinates,
  /// and refreshes them on every later call. Throws with a readable
  /// Arabic message when the user declines or location is off.
  static Future<void> useGps() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('خدمة تحديد الموقع غير مفعّلة على جهازك');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw Exception('لم يُسمح بالوصول إلى الموقع');
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low));
    final p = await SharedPreferences.getInstance();
    await p.setDouble('prayerLat', pos.latitude);
    await p.setDouble('prayerLng', pos.longitude);
    await p.setString('prayerMode', 'gps');
    LibraryEvents.prayer.ping();
  }

  static Future<void> setMethod(int method) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('prayerMethod', method);
    LibraryEvents.prayer.ping();
  }

  /// Today's times for the configured location (city or GPS) — served
  /// from the daily cache when available (works offline for the rest
  /// of the day). Returns null when nothing is configured.
  static Future<PrayerTimes?> getTodayTimes() async {
    final p = await SharedPreferences.getInstance();
    final method = await selectedMethod();
    final now = DateTime.now();

    final String url;
    final String locKey;
    if (await isGpsMode()) {
      final lat = p.getDouble('prayerLat');
      final lng = p.getDouble('prayerLng');
      if (lat == null || lng == null) return null;
      // Round to ~1km so small GPS jitter reuses the cache.
      locKey = '${lat.toStringAsFixed(2)},${lng.toStringAsFixed(2)}';
      url =
          'https://api.aladhan.com/v1/timings?latitude=$lat&longitude=$lng&method=$method';
    } else {
      final city = await selectedCity();
      if (city == null) return null;
      locKey = city.city;
      url =
          'https://api.aladhan.com/v1/timingsByCity?city=${Uri.encodeComponent(city.city)}&country=${Uri.encodeComponent(city.country)}&method=$method';
    }
    final cacheKey =
        'prayerCache_${now.year}-${now.month}-${now.day}_${locKey}_$method';

    final cached = p.getString(cacheKey);
    if (cached != null) {
      return PrayerTimes.fromJson(jsonDecode(cached));
    }

    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw Exception('فشل تحميل مواقيت الصلاة');
    final t = jsonDecode(r.body)['data']['timings'];
    // Times may carry a timezone suffix like "05:03 (CEST)" — keep HH:mm.
    String clean(String s) => s.split(' ').first;
    final times = PrayerTimes(
      fajr: clean(t['Fajr']),
      dhuhr: clean(t['Dhuhr']),
      asr: clean(t['Asr']),
      maghrib: clean(t['Maghrib']),
      isha: clean(t['Isha']),
    );
    await p.setString(cacheKey, jsonEncode(times.toJson()));
    return times;
  }
}

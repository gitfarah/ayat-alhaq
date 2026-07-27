import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSize = 26.0;
  int? _lastSurah;
  int? _lastAyah;
  int? _lastPage;
  String? _translationEdition;
  String _appLanguage = 'ar';
  bool _tajweed = false;

  /// Colour the ayah text by tajweed rule in the responsive reader.
  bool get tajweed => _tajweed;

  Future<void> setTajweed(bool on) async {
    _tajweed = on;
    (await SharedPreferences.getInstance()).setBool('tajweed', on);
    notifyListeners();
  }

  /// The user's raw language CHOICE: 'system', 'ar', 'en', or 'de'.
  /// Use [effectiveLanguage] for the actually-applied language.
  String get appLanguage => _appLanguage;

  /// The language actually applied to the UI. When the choice is
  /// 'system', it follows the phone's language (Arabic for anything the
  /// app doesn't translate). Quran content itself always stays Arabic.
  String get effectiveLanguage {
    if (_appLanguage != 'system') return _appLanguage;
    final code =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return (code == 'en' || code == 'de') ? code : 'ar';
  }

  Future<void> setAppLanguage(String code) async {
    if (!['system', 'ar', 'en', 'de'].contains(code)) return;
    _appLanguage = code;
    (await SharedPreferences.getInstance()).setString('appLanguage', code);
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;

  /// Effective darkness WITHOUT a BuildContext — falls back to the raw
  /// device brightness for ThemeMode.system. Prefer [isDarkIn] in
  /// widgets: it respects MediaQuery overrides (e.g. DevicePreview's
  /// simulated theme), which this getter cannot see.
  bool get isDark {
    switch (_themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  /// Effective darkness as seen from [context] — this is what
  /// MaterialApp itself uses to resolve ThemeMode.system, so widgets
  /// branching on it always agree with the applied theme.
  bool isDarkIn(BuildContext context) {
    switch (_themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }

  /// Quick toggle resolved against [context] (see [isDarkIn]).
  Future<void> toggleDarkIn(BuildContext context) =>
      setThemeMode(isDarkIn(context) ? ThemeMode.light : ThemeMode.dark);

  double get fontSize => _fontSize;
  int? get lastSurah => _lastSurah;
  int? get lastAyah => _lastAyah;
  int? get lastPage => _lastPage;
  bool get hasLastRead => _lastSurah != null || _lastPage != null;

  /// alquran.cloud edition id for the per-ayah translation shown in the
  /// reader (e.g. 'de.aburida'), or null when translation is off.
  String? get translationEdition => _translationEdition;

  SettingsService() {
    // Repaint when the OS/browser switches between light and dark while
    // the theme mode is "system".
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode == ThemeMode.system) notifyListeners();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    // Follow the phone's language live when set to "system".
    if (_appLanguage == 'system') notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getString('themeMode');
    if (stored != null) {
      _themeMode = ThemeMode.values.firstWhere((m) => m.name == stored,
          orElse: () => ThemeMode.system);
    } else if (p.containsKey('dark')) {
      // Migrate the old boolean setting — the user made an explicit
      // choice back then, keep honouring it.
      _themeMode = (p.getBool('dark') ?? false)
          ? ThemeMode.dark
          : ThemeMode.light;
    }
    _fontSize = p.getDouble('fontSize') ?? 26.0;
    _lastSurah = p.getInt('lastSurah');
    _lastAyah = p.getInt('lastAyah');
    _lastPage = p.getInt('lastPage');
    final edition = p.getString('translationEdition');
    _translationEdition = (edition == null || edition.isEmpty) ? null : edition;
    _appLanguage = p.getString('appLanguage') ?? 'ar';
    _tajweed = p.getBool('tajweed') ?? false;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    (await SharedPreferences.getInstance())
        .setString('themeMode', mode.name);
    notifyListeners();
  }

  Future<void> setTranslationEdition(String? edition) async {
    _translationEdition = edition;
    final p = await SharedPreferences.getInstance();
    if (edition == null) {
      p.remove('translationEdition');
    } else {
      p.setString('translationEdition', edition);
    }
    notifyListeners();
  }

  Future<void> setFontSize(double v) async {
    _fontSize = v.clamp(18.0, 44.0);
    (await SharedPreferences.getInstance()).setDouble('fontSize', _fontSize);
    notifyListeners();
  }

  Future<void> saveLastRead({int? surah, int? ayah, int? page}) async {
    final p = await SharedPreferences.getInstance();
    if (surah != null) { _lastSurah = surah; p.setInt('lastSurah', surah); }
    if (ayah != null) { _lastAyah = ayah; p.setInt('lastAyah', ayah); }
    if (page != null) { _lastPage = page; p.setInt('lastPage', page); }
    notifyListeners();
  }
}

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';

/// Lightweight app-chrome localization: Arabic (default), English and
/// Deutsch. Quran content and the reading surfaces themselves stay
/// Arabic by design — this covers navigation, home, and settings.
///
/// Usage: `final t = L10n.of(context); Text(t('tabIndex'))`.
class L10n {
  final String code;
  const L10n(this.code);

  /// Rebuilds the caller whenever the language changes.
  static L10n of(BuildContext context) =>
      L10n(context.watch<SettingsService>().appLanguage);

  static const Map<String, String> languages = {
    'ar': 'العربية',
    'en': 'English',
    'de': 'Deutsch',
  };

  bool get isArabic => code == 'ar';

  String call(String key) =>
      _data[code]?[key] ?? _data['ar']![key] ?? key;

  /// Arabic-Indic digits for the Arabic UI, Western digits otherwise.
  String number(int n) {
    if (!isArabic) return n.toString();
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

  static const Map<String, Map<String, String>> _data = {
    'ar': {
      'tabHighlights': 'التمييزات',
      'tabBookmarks': 'الفواصل',
      'tabKhatma': 'الختمة',
      'tabIndex': 'الفهرس',
      'searchHint': 'ابحث عن سورة أو رقم...',
      'surahUnit': 'سورة',
      'ayahUnit': 'آية',
      'ayahResults': 'نتائج في الآيات',
      'lastRead': 'آخر ما قرأت',
      'prayerTimes': 'مواقيت الصلاة',
      'chooseCity': 'اختر مدينتك لعرض مواقيت الصلاة',
      'settingsTitle': 'الإعدادات',
      'appearance': 'المظهر',
      'themeSystem': 'حسب النظام',
      'themeLight': 'نهاري',
      'themeDark': 'ليلي',
      'reading': 'القراءة',
      'fontSizeLbl': 'حجم الخط',
      'pointUnit': 'نقطة',
      'language': 'لغة التطبيق',
      'location': 'الموقع',
      'locationUnset': 'غير محدد — اضغط للاختيار',
      'calcMethod': 'طريقة الحساب',
      'recitation': 'التلاوة',
      'reciterLbl': 'القارئ',
      'mushafOffline': 'المصحف دون اتصال',
      'savedPages': 'الصفحات المحفوظة',
      'tafsirOffline': 'التفاسير دون اتصال',
      'downloadTafsir': 'تحميل التفاسير',
      'about': 'عن التطبيق',
      'versionLbl': 'آيات الحق — الإصدار',
      'textSource': 'مصدر النصوص',
      'pagesSource': 'مصدر صفحات المصحف',
      'fontLbl': 'الخط',
    },
    'en': {
      'tabHighlights': 'Highlights',
      'tabBookmarks': 'Bookmarks',
      'tabKhatma': 'Khatma',
      'tabIndex': 'Index',
      'searchHint': 'Search surah, number, or text…',
      'surahUnit': 'surahs',
      'ayahUnit': 'ayahs',
      'ayahResults': 'Matches in ayah text',
      'lastRead': 'Continue reading',
      'prayerTimes': 'Prayer times',
      'chooseCity': 'Choose your city for prayer times',
      'settingsTitle': 'Settings',
      'appearance': 'Appearance',
      'themeSystem': 'System',
      'themeLight': 'Light',
      'themeDark': 'Dark',
      'reading': 'Reading',
      'fontSizeLbl': 'Font size',
      'pointUnit': 'pt',
      'language': 'App language',
      'location': 'Location',
      'locationUnset': 'Not set — tap to choose',
      'calcMethod': 'Calculation method',
      'recitation': 'Recitation',
      'reciterLbl': 'Reciter',
      'mushafOffline': 'Offline Mushaf',
      'savedPages': 'Saved pages',
      'tafsirOffline': 'Offline tafsir',
      'downloadTafsir': 'Download tafsir books',
      'about': 'About',
      'versionLbl': 'Ayat al-Haq — version',
      'textSource': 'Text source',
      'pagesSource': 'Mushaf pages source',
      'fontLbl': 'Font',
    },
    'de': {
      'tabHighlights': 'Markierungen',
      'tabBookmarks': 'Lesezeichen',
      'tabKhatma': 'Khatma',
      'tabIndex': 'Index',
      'searchHint': 'Sure, Nummer oder Text suchen…',
      'surahUnit': 'Suren',
      'ayahUnit': 'Verse',
      'ayahResults': 'Treffer im Verstext',
      'lastRead': 'Weiterlesen',
      'prayerTimes': 'Gebetszeiten',
      'chooseCity': 'Stadt für Gebetszeiten wählen',
      'settingsTitle': 'Einstellungen',
      'appearance': 'Darstellung',
      'themeSystem': 'System',
      'themeLight': 'Hell',
      'themeDark': 'Dunkel',
      'reading': 'Lesen',
      'fontSizeLbl': 'Schriftgröße',
      'pointUnit': 'pt',
      'language': 'App-Sprache',
      'location': 'Standort',
      'locationUnset': 'Nicht gewählt — zum Auswählen tippen',
      'calcMethod': 'Berechnungsmethode',
      'recitation': 'Rezitation',
      'reciterLbl': 'Rezitator',
      'mushafOffline': 'Mushaf offline',
      'savedPages': 'Gespeicherte Seiten',
      'tafsirOffline': 'Tafsir offline',
      'downloadTafsir': 'Tafsir-Werke herunterladen',
      'about': 'Über die App',
      'versionLbl': 'Ayat al-Haq — Version',
      'textSource': 'Textquelle',
      'pagesSource': 'Quelle der Mushaf-Seiten',
      'fontLbl': 'Schrift',
    },
  };
}

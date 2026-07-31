import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../l10n/app_strings.dart';
import '../services/settings_service.dart';
import '../theme.dart';

/// What the app is, where every text and typeface in it comes from, and
/// the licences those carry.
///
/// Kept as a page of its own rather than a line in Settings: the fonts
/// are used under licences that ask for their notice to travel with the
/// app, and the Quran text, the page artwork and the recitations each
/// come from a different project that deserves naming.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final isDark = context.watch<SettingsService>().isDarkIn(context);
    final text = isDark ? AppColors.darkText : AppColors.textPrimary;
    final sub = isDark ? AppColors.darkTextSec : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.background,
      appBar: AppBar(
        title: Text(t('aboutApp'),
            style: const TextStyle(
                fontFamily: 'Almarai', fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        foregroundColor: text,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Card(isDark: isDark, children: [
            // The app icon, not the wordmark: the wordmark is pale and
            // vanished against the card.
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('assets/icon/app_icon.png',
                    height: 88,
                    width: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'آيات ',
                      style: TextStyle(
                          color: isDark
                              ? AppColors.darkPrimary
                              : AppColors.primary)),
                  TextSpan(text: 'الحق', style: TextStyle(color: text)),
                ]),
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                    fontFamily: 'QuranHafs',
                    fontSize: 30,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            // The marketing version stays put until a real release; the
            // build number is what tells two sideloaded builds apart, so
            // it is the part worth quoting in a bug report.
            Center(
              child: Text('${t('versionLbl')} $kVersionLabel',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontFamily: 'Almarai', fontSize: 12.5, color: sub)),
            ),
            const SizedBox(height: 14),
            Text(t('aboutBlurb'),
                textAlign: TextAlign.start,
                style: TextStyle(
                    fontFamily: 'Almarai',
                    fontSize: 14,
                    height: 1.7,
                    color: text)),
          ]),
          const SizedBox(height: 14),
          _Section(isDark: isDark, title: t('aboutSources'), rows: [
            (t('aboutQuranText'), 'alquran.cloud — Uthmani (ar.alafasy)'),
            (
              t('aboutMushafPages'),
              'quranpedia/quran-svg — Hafs, Warsh,\n'
                  'Qalon, Shubah, ad-Duri'
            ),
            (t('aboutTajweed'), 'quran.com tajweed rule data'),
            (t('aboutTafsir'), 'spa5k/tafsir_api'),
            (t('aboutAudio'), 'islamic.network / everyayah.com'),
            (t('aboutPrayer'), 'Adhan calculation, on-device'),
          ]),
          const SizedBox(height: 14),
          _Section(isDark: isDark, title: t('aboutFonts'), rows: [
            ('Almarai', 'SIL Open Font License 1.1'),
            (
              'KFGQPC HAFS Uthmanic Script',
              'King Fahd Glorious Quran Printing Complex'
            ),
          ]),
          const SizedBox(height: 14),
          _Card(isDark: isDark, children: [
            Text(t('aboutOffline'),
                style: TextStyle(
                    fontFamily: 'Almarai',
                    fontSize: 13.5,
                    height: 1.7,
                    color: sub)),
          ]),
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'آيات الحق',
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/icon/app_icon.png',
                        height: 48,
                        width: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                ),
              ),
              icon: Icon(Icons.article_outlined,
                  color: isDark ? AppColors.darkPrimary : AppColors.primary),
              label: Text(t('aboutLicenses'),
                  style: TextStyle(
                      fontFamily: 'Almarai',
                      color:
                          isDark ? AppColors.darkPrimary : AppColors.primary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _Card({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : AppColors.border),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _Section extends StatelessWidget {
  final bool isDark;
  final String title;
  final List<(String, String)> rows;
  const _Section(
      {required this.isDark, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final text = isDark ? AppColors.darkText : AppColors.textPrimary;
    final sub = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    return _Card(isDark: isDark, children: [
      Text(title,
          style: TextStyle(
              fontFamily: 'Almarai',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.gold)),
      const SizedBox(height: 10),
      for (final (label, value) in rows) ...[
        Text(label,
            style: TextStyle(
                fontFamily: 'Almarai',
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: text)),
        Text(value,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            style: TextStyle(
                fontFamily: 'Almarai',
                fontSize: 12.5,
                height: 1.5,
                color: sub)),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

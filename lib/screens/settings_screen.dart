import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../services/settings_service.dart';
import '../services/mushaf_svg_service.dart';
import '../services/prayer_service.dart';
import '../services/quran_audio_service.dart';
import '../services/tafsir_service.dart';
import '../services/tajweed_service.dart';
import '../theme.dart';
import 'about_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _cacheBytes;
  bool _clearing = false;

  // Offline-tafsir download state, keyed by edition id.
  final Map<int, bool> _tafsirDownloaded = {};
  final Map<int, int> _tafsirSize = {};
  final Map<int, int> _tafsirProgress = {};
  final Set<int> _tafsirDownloading = {};
  final Set<int> _tafsirCancel = {};

  PrayerCity? _prayerCity;
  String? _prayerLabel;
  int _prayerMethod = 3;
  bool _locating = false;
  String _lang = 'ar';

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    _loadTafsirStatus();
    _loadPrayerConfig();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Location/method labels are language-specific — reload on change.
    final lang = context.read<SettingsService>().effectiveLanguage;
    if (lang != _lang) {
      _lang = lang;
      _loadPrayerConfig();
    }
  }

  Future<void> _loadPrayerConfig() async {
    final city = await PrayerService.selectedCity();
    final label = await PrayerService.locationLabel(_lang);
    final method = await PrayerService.selectedMethod();
    if (mounted) {
      setState(() {
        _prayerCity = city;
        _prayerLabel = label;
        _prayerMethod = method;
      });
    }
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    try {
      await PrayerService.useGps();
      await _loadPrayerConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.of(context)('locationSet'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _locating = false);
  }

  void _showCityPicker(bool isDark) {
    final t = L10n.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: PrayerService.cities.length + 1,
          itemBuilder: (_, index) {
            // First row: automatic GPS location.
            if (index == 0) {
              return ListTile(
                onTap: () {
                  Navigator.pop(ctx);
                  _useGps();
                },
                trailing: Icon(Icons.my_location_rounded,
                    size: 20,
                    color: isDark ? AppColors.darkPrimary : AppColors.primary),
                title: Text(t('gpsOption'),
                    textAlign: TextAlign.start,
                    style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkPrimary
                            : AppColors.primary)),
              );
            }
            final i = index - 1;
            final c = PrayerService.cities[i];
            final selected = c.city == _prayerCity?.city;
            return ListTile(
              dense: true,
              selected: selected,
              selectedTileColor: AppColors.gold.withValues(alpha: 0.16),
              shape: selected
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(
                          color: AppColors.gold, width: 1.3))
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                await PrayerService.setCity(c);
                _loadPrayerConfig();
              },
              trailing: selected
                  ? const Icon(Icons.check_circle_rounded,
                      color: AppColors.gold)
                  : null,
              title: Text(_lang == 'ar' ? c.label : c.city,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 18,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                      color: isDark
                          ? AppColors.darkText
                          : AppColors.textPrimary)),
            );
          },
        ),
      ),
    );
  }

  void _showMethodPicker(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in PrayerService.methods.entries)
                Builder(builder: (_) {
                  final selected = e.key == _prayerMethod;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: AppColors.gold.withValues(alpha: 0.16),
                    shape: selected
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                                color: AppColors.gold, width: 1.3))
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await PrayerService.setMethod(e.key);
                      _loadPrayerConfig();
                    },
                    trailing: selected
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.gold)
                        : null,
                    title: Text(PrayerService.methodName(e.key, _lang),
                        textAlign: TextAlign.start,
                        style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 17,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.textPrimary)),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadTafsirStatus() async {
    if (!TafsirService.supportsDownload) return;
    for (final e in TafsirService.editions) {
      _tafsirDownloaded[e.id] = await TafsirService.isDownloaded(e.id);
      _tafsirSize[e.id] = await TafsirService.downloadedSizeBytes(e.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _downloadTafsir(int id) async {
    setState(() {
      _tafsirDownloading.add(id);
      _tafsirCancel.remove(id);
      _tafsirProgress[id] = 0;
    });
    try {
      await TafsirService.downloadEdition(
        id,
        onProgress: (done, total) {
          if (mounted) setState(() => _tafsirProgress[id] = done);
        },
        isCancelled: () => _tafsirCancel.contains(id),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L10n.of(context)('tafsirDownloadError'))));
      }
    }
    _tafsirDownloading.remove(id);
    await _loadTafsirStatus();
  }

  Future<void> _deleteTafsir(int id) async {
    await TafsirService.deleteDownload(id);
    await _loadTafsirStatus();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L10n.of(context)('deletedTafsir'))));
    }
  }

  Future<void> _loadCacheSize() async {
    final size = await MushafSvgService.getCacheSizeBytes();
    if (mounted) setState(() => _cacheBytes = size);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} كيلوبايت';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميجابايت';
  }

  Future<void> _confirmClearCache() async {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final t = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('clearCacheTitle'),
            textDirection: TextDirection.rtl,
            style: const TextStyle(
                fontFamily: '.SF Pro Text', fontWeight: FontWeight.bold)),
        content: Text(t('clearCacheBody'),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: '.SF Pro Text', height: 1.6)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('clearBtn'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _clearing = true);
      await MushafSvgService.clearDiskCache();
      await _loadCacheSize();
      if (mounted) {
        setState(() => _clearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.of(context)('clearedMsg'))));
      }
    }
  }

  /// One row per tafsir: name + status on the right, action button on
  /// the left (download / progress + cancel / delete).
  Widget _tafsirRow(TafsirEdition e, bool isDark) {
    final t = L10n.of(context);
    final downloaded = _tafsirDownloaded[e.id] ?? false;
    final downloading = _tafsirDownloading.contains(e.id);
    final progress = _tafsirProgress[e.id] ?? 0;
    final size = _tafsirSize[e.id] ?? 0;
    final subColor = isDark ? AppColors.darkTextSec : AppColors.textSecondary;

    final String status;
    if (downloading) {
      status = '${t('tafsirDownloadingLbl')} ${(progress / 114 * 100).round()}٪';
    } else if (downloaded) {
      status = '${t('tafsirLoadedLbl')} • ${_formatBytes(size)}';
    } else if (size > 0) {
      status = t('tafsirIncomplete');
    } else {
      status = t('tafsirNotLoaded');
    }

    final Widget action;
    if (downloading) {
      action = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: t('stop'),
            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
            onPressed: () => setState(() => _tafsirCancel.add(e.id))),
        SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress / 114,
                color: isDark ? AppColors.darkPrimary : AppColors.primary)),
      ]);
    } else if (downloaded) {
      action = IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: t('delete'),
          icon: const Icon(Icons.delete_outline_rounded,
              size: 20, color: Colors.red),
          onPressed: () => _deleteTafsir(e.id));
    } else {
      action = IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: t('download'),
          icon: Icon(Icons.download_rounded,
              size: 20,
              color: isDark ? AppColors.darkPrimary : AppColors.primary),
          onPressed: () => _downloadTafsir(e.id));
    }

    // Name/status on the leading edge, action on the trailing edge —
    // follows the app-language direction (name right in Arabic, left in
    // English/German) instead of being forced one way.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.textPrimary)),
                Text(status,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 13,
                        color: subColor)),
              ]),
        ),
        const SizedBox(width: 8),
        action,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final isDark = s.isDarkIn(context);
    final t = L10n.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t('settingsTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel(t('appearance'), isDark),
          _Tile(
            isDark: isDark,
            icon: Icons.language_rounded,
            title: t('language'),
            subtitle: t.languageChoices[s.appLanguage],
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  children: [
                    for (final e in t.languageChoices.entries)
                      ChoiceChip(
                        label: Text(e.value,
                            style: const TextStyle(fontFamily: '.SF Pro Text')),
                        selected: s.appLanguage == e.key,
                        selectedColor: (isDark
                                ? AppColors.darkPrimary
                                : AppColors.primary)
                            .withValues(alpha: 0.18),
                        onSelected: (_) => s.setAppLanguage(e.key),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _Tile(
            isDark: isDark,
            icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            title: t('appearance'),
            subtitle: switch (s.themeMode) {
              ThemeMode.system => t('themeSystem'),
              ThemeMode.light => t('themeLight'),
              ThemeMode.dark => t('themeDark'),
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  // No leading icons and no selected-check, with tight
                  // padding — the three labels ("System"/"النظام"/…) were
                  // wrapping and breaking apart when squeezed by icons.
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                    textStyle: const TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  segments: [
                    ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(t('themeDark'),
                            maxLines: 1, overflow: TextOverflow.visible)),
                    ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(t('themeSystem'),
                            maxLines: 1, overflow: TextOverflow.visible)),
                    ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(t('themeLight'),
                            maxLines: 1, overflow: TextOverflow.visible)),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (sel) => s.setThemeMode(sel.first),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel(t('reading'), isDark),
          _Tile(
            isDark: isDark,
            icon: Icons.text_fields_rounded,
            title: t('fontSizeLbl'),
            subtitle: '${s.fontSize.toInt()} ${t('pointUnit')}',
            child: Column(children: [
              const SizedBox(height: 8),
              Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                      color: isDark ? AppColors.darkBg : AppColors.background,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: s.fontSize,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary))),
              Row(children: [
                Text('أ',
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextSec
                            : AppColors.textSecondary)),
                Expanded(
                    child: Slider(
                        value: s.fontSize,
                        min: 18,
                        max: 44,
                        divisions: 13,
                        activeColor:
                            isDark ? AppColors.darkPrimary : AppColors.primary,
                        inactiveColor:
                            (isDark ? AppColors.darkPrimary : AppColors.primary)
                                .withValues(alpha: 0.2),
                        onChanged: s.setFontSize)),
                Text('أ',
                    style: TextStyle(
                        fontSize: 22,
                        color: isDark
                            ? AppColors.darkTextSec
                            : AppColors.textSecondary)),
              ]),
            ]),
          ),
          _Tile(
            isDark: isDark,
            icon: Icons.format_color_fill_rounded,
            title: t('mushafBg'),
            subtitle: t('bg${s.mushafBackground[0].toUpperCase()}'
                '${s.mushafBackground.substring(1)}'),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final id in AppColors.mushafBackgrounds.keys)
                    GestureDetector(
                      onTap: () => s.setMushafBackground(id),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          // The swatch shows the colour as it will look
                          // in the mode the reader is actually in.
                          color: AppColors.mushafBackground(id, isDark),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: s.mushafBackground == id
                                ? AppColors.gold
                                : (isDark
                                    ? AppColors.darkTextSec
                                    : AppColors.border),
                            width: s.mushafBackground == id ? 3 : 1,
                          ),
                        ),
                        child: s.mushafBackground == id
                            ? const Icon(Icons.check_rounded,
                                size: 20, color: AppColors.gold)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
          _Tile(
            isDark: isDark,
            icon: Icons.palette_rounded,
            title: t('tajweedLbl'),
            subtitle: s.tajweed ? t('tajweedOn') : t('tajweedOff'),
            child: Column(children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Switch(
                  value: s.tajweed,
                  activeThumbColor: AppColors.gold,
                  onChanged: (v) => s.setTajweed(v),
                ),
              ),
              if (s.tajweed) ...[
                const SizedBox(height: 4),
                // Legend so the colours are learnable, not guesswork.
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  children: [
                    for (final rule in TajweedService.legendOrder)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: TajweedService.ruleColors[rule],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          TajweedService.ruleNames[_lang]?[rule] ??
                              TajweedService.ruleNames['en']![rule]!,
                          style: TextStyle(
                              fontFamily: '.SF Pro Text',
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.textPrimary),
                        ),
                      ]),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(t('tajweedNote'),
                    textAlign: TextAlign.start,
                    style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 13,
                        height: 1.5,
                        color: isDark
                            ? AppColors.darkTextSec
                            : AppColors.textSecondary)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _SectionLabel(t('prayerTimes'), isDark),
          GestureDetector(
            onTap: _locating ? null : () => _showCityPicker(isDark),
            child: _Tile(
                isDark: isDark,
                icon: _locating
                    ? Icons.my_location_rounded
                    : Icons.location_city_rounded,
                title: t('location'),
                subtitle: _locating
                    ? t('locating')
                    : _prayerLabel ?? t('locationUnset')),
          ),
          GestureDetector(
            onTap: () => _showMethodPicker(isDark),
            child: _Tile(
                isDark: isDark,
                icon: Icons.calculate_rounded,
                title: t('calcMethod'),
                subtitle: PrayerService.methodName(_prayerMethod, _lang)),
          ),
          const SizedBox(height: 16),
          _SectionLabel(t('recitation'), isDark),
          _Tile(
            isDark: isDark,
            icon: Icons.record_voice_over_rounded,
            title: t('reciterLbl'),
            subtitle: context.watch<QuranAudioService>().reciterName,
            child: Column(children: [
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: context.watch<QuranAudioService>().reciter,
                onChanged: (id) {
                  if (id != null) {
                    context.read<QuranAudioService>().setReciter(id);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in QuranAudioService.reciters.entries)
                      Builder(builder: (_) {
                        final sel = e.key ==
                            context.watch<QuranAudioService>().reciter;
                        return RadioListTile<String>(
                          value: e.key,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          selected: sel,
                          tileColor: sel
                              ? AppColors.gold.withValues(alpha: 0.16)
                              : null,
                          shape: sel
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(
                                      color: AppColors.gold, width: 1.1))
                              : null,
                          activeColor: AppColors.gold,
                          title: Text(e.value,
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontSize: 16,
                                  fontWeight:
                                      sel ? FontWeight.bold : FontWeight.normal,
                                  color: isDark
                                      ? AppColors.darkText
                                      : AppColors.textPrimary)),
                        );
                      }),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _SectionLabel(t('mushafOffline'), isDark),
          _Tile(
            isDark: isDark,
            icon: Icons.download_for_offline_rounded,
            title: t('savedPages'),
            subtitle: _cacheBytes == null
                ? t('calculating')
                : _cacheBytes == 0
                    ? t('noSavedPages')
                    : '${_formatBytes(_cacheBytes!)} ${t('onDevice')}',
            child: Column(children: [
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  t('savedPagesInfo'),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextSec
                          : AppColors.textSecondary,
                      height: 1.6),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      (_cacheBytes != null && _cacheBytes! > 0 && !_clearing)
                          ? _confirmClearCache
                          : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: _clearing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.red))
                      : const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(
                      _clearing ? t('clearing') : t('clearSavedPages'),
                      style: const TextStyle(fontFamily: '.SF Pro Text')),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _SectionLabel(t('tafsirOffline'), isDark),
          _Tile(
            isDark: isDark,
            icon: Icons.library_books_rounded,
            title: t('downloadTafsir'),
            subtitle: TafsirService.supportsDownload
                ? t('tafsirSubtitleMobile')
                : t('tafsirSubtitleWebOnly'),
            child: TafsirService.supportsDownload
                ? Column(children: [
                    const SizedBox(height: 4),
                    for (final e in TafsirService.editions)
                      _tafsirRow(e, isDark),
                  ])
                : null,
          ),
          const SizedBox(height: 16),
          _SectionLabel(t('about'), isDark),
          // Everything that used to be listed here — version, text
          // source, page source — now lives on its own page, together
          // with the typefaces and their licences.
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutScreen())),
            child: _Tile(
                isDark: isDark,
                icon: Icons.info_outline_rounded,
                title: t('aboutApp'),
                subtitle: t('aboutOpen'),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Icon(Icons.chevron_right_rounded,
                      color: isDark
                          ? AppColors.darkTextSec
                          : AppColors.textSecondary),
                )),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionLabel(this.text, this.isDark);
  @override
  Widget build(BuildContext context) => Padding(
      // Directional padding + start alignment so the label sits on the
      // leading edge in whichever direction the language uses.
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(text,
            style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontFamily: '.SF Pro Text',
                fontSize: 18)),
      ));
}

class _Tile extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? child;
  const _Tile(
      {required this.isDark,
      required this.icon,
      required this.title,
      this.subtitle,
      this.child});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border)),
        child: Column(children: [
          // Icon leads, text follows — the Row honours the ambient
          // direction, so Arabic puts the icon on the right and German
          // on the left automatically.
          Row(children: [
            Icon(icon,
                color: isDark ? AppColors.darkPrimary : AppColors.primary,
                size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontWeight: FontWeight.bold,
                            fontSize: 19,
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.textPrimary)),
                    if (subtitle != null)
                      Text(subtitle!,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextSec
                                  : AppColors.textSecondary,
                              fontSize: 15,
                              fontFamily: '.SF Pro Text')),
                  ]),
            ),
          ]),
          if (child != null) child!,
        ]),
      );
}

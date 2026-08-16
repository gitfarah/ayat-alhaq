import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/ayah_share_service.dart';
import '../services/quran_service.dart';
import '../services/settings_service.dart';
import '../services/tafsir_service.dart';
import '../theme.dart';
import 'ayah_sheet_header.dart';

/// Lets the reader share an ayah as plain text or as a rendered card,
/// with the tafsir folded in or left out.
///
/// The tafsir is fetched only if it is actually wanted — opening this
/// sheet on a verse should not cost a network call the reader never
/// asked for.
Future<void> showAyahShareSheet(
  BuildContext context, {
  required int surahNumber,
  required String surahName,
  required int ayahNumber,
  required String ayahText,

  /// Pre-fetched tafsir, when the caller already has it on screen (the
  /// tafsir screen does). Null elsewhere — the sheet fetches on demand.
  String? tafsirText,
  String? tafsirName,
  int? tafsirId,
}) {
  final isDark = context.read<SettingsService>().isDarkIn(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _AyahShareSheet(
      surahNumber: surahNumber,
      surahName: surahName,
      ayahNumber: ayahNumber,
      ayahText: ayahText,
      tafsirText: tafsirText,
      tafsirName: tafsirName,
      tafsirId: tafsirId,
      isDark: isDark,
    ),
  );
}

class _AyahShareSheet extends StatefulWidget {
  final int surahNumber;
  final String surahName;
  final int ayahNumber;
  final String ayahText;
  final String? tafsirText;
  final String? tafsirName;
  final int? tafsirId;
  final bool isDark;

  const _AyahShareSheet({
    required this.surahNumber,
    required this.surahName,
    required this.ayahNumber,
    required this.ayahText,
    required this.tafsirText,
    required this.tafsirName,
    required this.tafsirId,
    required this.isDark,
  });

  @override
  State<_AyahShareSheet> createState() => _AyahShareSheetState();
}

class _AyahShareSheetState extends State<_AyahShareSheet> {
  bool _withTafsir = false;
  bool _busy = false;

  // Needed to measure each button for the iOS share-sheet origin.
  final _textKey = GlobalKey();
  final _imageKey = GlobalKey();

  String? _fetchedTafsir;
  String? _fetchedTafsirName;

  /// How many verses the reader wants, starting at the one they opened
  /// this on. 1 is the ordinary share.
  int _count = 1;

  /// Verses after the first, loaded as the count is raised. Kept as a
  /// growing list so stepping down and back up costs nothing.
  final List<ShareVerse> _extra = [];

  /// The last verse of the surah, so the stepper stops at its end
  /// rather than asking for ayahs that do not exist.
  int? _surahLength;

  /// Cached because it means laying every paragraph of the card out,
  /// and it is read on every rebuild to draw the hint.
  bool _tooLong = false;

  /// alquran.cloud edition id for the translation to include, or null
  /// for none. Defaults to whatever the reader already reads with.
  String? _translationEdition;

  /// Translation text per ayah number, for the chosen edition.
  Map<int, String> _translations = {};
  bool _loadingTranslation = false;

  @override
  void initState() {
    super.initState();
    _loadSurahLength();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Someone reading with the German translation on almost certainly
    // wants to share it in German — so the sheet opens on their own
    // reading language rather than on nothing.
    _translationEdition ??= context.read<SettingsService>().translationEdition;
    if (_translationEdition != null && _translations.isEmpty) {
      _loadTranslation(_translationEdition!);
    }
  }

  /// Fetches the whole surah in [edition] — one call, and it then
  /// covers however many verses the reader steps through.
  Future<void> _loadTranslation(String edition) async {
    setState(() => _loadingTranslation = true);
    try {
      final ayahs = await QuranService.getSurahAyahs(widget.surahNumber,
          translationEdition: edition);
      if (!mounted) return;
      setState(() {
        _translations = {
          for (final a in ayahs)
            if ((a.translation ?? '').trim().isNotEmpty)
              a.numberInSurah: a.translation!.trim()
        };
        _loadingTranslation = false;
      });
      _remeasure();
    } catch (_) {
      if (!mounted) return;
      // Offline: the card is shared without a translation rather than
      // failing, exactly as the tafsir behaves.
      setState(() {
        _translations = {};
        _loadingTranslation = false;
      });
    }
  }

  Future<void> _loadSurahLength() async {
    try {
      final ayahs = await QuranService.getSurahAyahs(widget.surahNumber);
      if (!mounted) return;
      setState(() => _surahLength = ayahs.length);
    } catch (_) {
      // Offline: the stepper simply stops at what is already loaded.
    }
  }

  /// The most verses that can be added from here — never past the end
  /// of the surah, and never so many that the card becomes absurd.
  int get _maxCount {
    const hardCap = 20;
    final toEnd =
        _surahLength == null ? 1 : _surahLength! - widget.ayahNumber + 1;
    return toEnd.clamp(1, hardCap);
  }

  /// Loads verses up to [n] and re-measures the card.
  Future<void> _setCount(int n) async {
    final wanted = n.clamp(1, _maxCount);
    if (wanted == _count) return;
    if (wanted > 1 && _extra.length < wanted - 1) {
      try {
        final ayahs = await QuranService.getSurahAyahs(widget.surahNumber);
        _extra
          ..clear()
          ..addAll(ayahs
              .where((x) =>
                  x.numberInSurah > widget.ayahNumber &&
                  x.numberInSurah < widget.ayahNumber + wanted)
              .map((x) => ShareVerse(x.numberInSurah, x.text)));
      } catch (_) {
        return; // leave the count where it was rather than lying
      }
    }
    if (!mounted) return;
    setState(() => _count = wanted);
    _remeasure();
  }

  /// Asks the card how tall it will actually be. Measured, not guessed:
  /// one ayah of Al-Baqarah runs longer than twenty short ones, so a
  /// count-based warning would fire on the wrong passages.
  void _remeasure() {
    // Measured WITH the tafsir when it is switched on and already in
    // hand — it is usually the tallest block on the card, so leaving it
    // out would have the hint miss the very case it exists for. When
    // the tafsir has not been fetched yet there is nothing to measure,
    // and the hint appears once it arrives.
    final tafsir = _withTafsir ? (widget.tafsirText ?? _fetchedTafsir) : null;
    final tall = AyahShareService.isCardTooTall(
      _payloadSync(tafsirText: tafsir, tafsirName: 'التفسير'),
      style: shareBackgroundById(
          context.read<SettingsService>().shareCardBackground),
    );
    if (tall != _tooLong && mounted) setState(() => _tooLong = tall);
  }

  String _ar(int n) {
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

  /// The tafsir to share, fetching it the first time it is wanted.
  /// Returns null when it could not be had — the caller then shares the
  /// verse alone rather than failing outright.
  Future<(String, String)?> _tafsir() async {
    if (widget.tafsirText?.trim().isNotEmpty ?? false) {
      return (widget.tafsirText!, widget.tafsirName ?? 'التفسير');
    }
    if (_fetchedTafsir != null) {
      return (_fetchedTafsir!, _fetchedTafsirName ?? 'التفسير');
    }
    try {
      final id = widget.tafsirId ?? TafsirService.editions.first.id;
      final edition =
          TafsirService.editionById(id) ?? TafsirService.editions.first;
      final text = await TafsirService.getTafsir(
          widget.surahNumber, widget.ayahNumber,
          tafsirId: edition.id);
      if (text.trim().isEmpty) return null;
      _fetchedTafsir = text;
      _fetchedTafsirName = edition.name;
      return (text, edition.name);
    } catch (_) {
      return null;
    }
  }

  /// The verses currently chosen, without touching the network — used
  /// for measuring the card as the reader changes the count.
  ShareableAyah _payloadSync({String? tafsirText, String? tafsirName}) {
    final edition = _translationEdition;
    final name = edition == null
        ? null
        : QuranService.translationEditions[edition] ?? edition;
    return ShareableAyah(
      surahNumber: widget.surahNumber,
      surahName: widget.surahName,
      ayahNumber: widget.ayahNumber,
      ayahText: widget.ayahText,
      moreVerses: [
        for (final v in _extra.take(_count - 1))
          ShareVerse(v.number, v.text, translation: _translations[v.number])
      ],
      translationText: _translations[widget.ayahNumber],
      translationName: name,
      translationRtl: edition != null && QuranService.isRtlEdition(edition),
      tafsirText: tafsirText,
      tafsirName: tafsirName,
    );
  }

  Future<ShareableAyah> _payload() async {
    String? tafsirText;
    String? tafsirName;
    if (_withTafsir) {
      final t = await _tafsir();
      if (t != null) {
        tafsirText = t.$1;
        tafsirName = t.$2;
      }
    }
    return _payloadSync(tafsirText: tafsirText, tafsirName: tafsirName);
  }

  /// The rect of the button that was tapped, in global coordinates.
  ///
  /// iOS needs a real, non-zero source rect or the share sheet never
  /// appears — the plugin call just returns. Measured from the button's
  /// own render box, before the sheet closes and it stops existing.
  Rect? _originOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _share({required bool asImage, required GlobalKey from}) async {
    if (_busy) return;
    final origin = _originOf(from);
    setState(() => _busy = true);
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final style = _style;
    try {
      final payload = await _payload();
      if (asImage) {
        await AyahShareService.shareImage(payload,
            origin: origin, style: style);
      } else {
        await AyahShareService.shareText(payload, origin: origin);
      }
      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger
          .showSnackBar(SnackBar(content: Text('${l('shareFailed')} — $e')));
    }
  }

  /// Keeps the card in the reader's own photo library instead of
  /// sending it anywhere.
  Future<void> _saveToPhotos() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final style = _style;
    try {
      await AyahShareService.saveImageToGallery(await _payload(), style: style);
      if (mounted) navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l('savedToPhotos'))));
    } on GalException catch (e) {
      if (mounted) setState(() => _busy = false);
      // A refused photo-library prompt is the ordinary case here, and
      // deserves plain wording rather than an exception dump.
      messenger.showSnackBar(SnackBar(
          content: Text(e.type == GalExceptionType.accessDenied
              ? l('savePhotoDenied')
              : '${l('shareFailed')} — ${e.type.name}')));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger
          .showSnackBar(SnackBar(content: Text('${l('shareFailed')} — $e')));
    }
  }

  /// The ground the card will be drawn on, as last chosen.
  ShareCardStyle get _style =>
      shareBackgroundById(context.read<SettingsService>().shareCardBackground);

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isDark = widget.isDark;
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;
    final accent = isDark ? AppColors.darkPrimary : AppColors.primary;
    final secondary = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final chosen = context.watch<SettingsService>().shareCardBackground;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AyahSheetHeader(
              ayahText: widget.ayahText,
              label: _count == 1
                  ? '${widget.surahName} — آية ${_ar(widget.ayahNumber)}'
                  : '${widget.surahName} — ${l('shareVerseRange').replaceFirst('@from', _ar(widget.ayahNumber)).replaceFirst('@to', _ar(widget.ayahNumber + _count - 1))}',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _withTafsir,
                    activeThumbColor: accent,
                    onChanged: _busy
                        ? null
                        : (v) {
                            setState(() => _withTafsir = v);
                            _remeasure();
                          },
                    title: Text(l('shareIncludeTafsir'),
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                            fontFamily: '.SF Pro Text', color: textColor)),
                    secondary: Icon(Icons.menu_book_rounded, color: accent),
                  ),
                  // ── Which translation goes with the verse, if any.
                  // Applies to BOTH forms: the text share and the card.
                  Row(
                    children: [
                      Icon(Icons.translate_rounded, size: 20, color: accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(l('shareTranslation'),
                            style: TextStyle(
                                fontFamily: '.SF Pro Text',
                                fontSize: 15,
                                color: textColor)),
                      ),
                      if (_loadingTranslation)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: accent),
                        )
                      else
                        DropdownButton<String?>(
                          value: _translationEdition,
                          underline: const SizedBox.shrink(),
                          borderRadius: BorderRadius.circular(12),
                          style: TextStyle(
                              fontFamily: '.SF Pro Text',
                              fontSize: 14,
                              color: textColor),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(l('shareNoTranslation')),
                            ),
                            for (final e
                                in QuranService.translationEditions.entries)
                              DropdownMenuItem<String?>(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) {
                                  setState(() {
                                    _translationEdition = v;
                                    _translations = {};
                                  });
                                  if (v != null) {
                                    _loadTranslation(v);
                                  } else {
                                    _remeasure();
                                  }
                                },
                        ),
                    ],
                  ),
                  // ── How many verses, and the warning when that starts
                  // to make a card nobody can read in a chat.
                  if (_maxCount > 1)
                    _VerseCounter(
                      count: _count,
                      max: _maxCount,
                      enabled: !_busy,
                      isDark: isDark,
                      label: l('shareVerseCount'),
                      onChanged: _setCount,
                    ),
                  if (_tooLong)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 16, color: Color(0xFFC2703A)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(l('shareTooLong'),
                                style: const TextStyle(
                                    fontFamily: '.SF Pro Text',
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: Color(0xFFC2703A))),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  // ── The ground the card is drawn on.
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(l('shareBackground'),
                        style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: secondary)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final bg in kShareBackgrounds) ...[
                        Expanded(
                          child: _BackgroundSwatch(
                            style: bg,
                            label: l('shareBg'
                                '${bg.id[0].toUpperCase()}${bg.id.substring(1)}'),
                            selected: bg.id == chosen,
                            accent: accent,
                            labelColor: secondary,
                            onTap: _busy
                                ? null
                                : () async {
                                    await context
                                        .read<SettingsService>()
                                        .setShareCardBackground(bg.id);
                                    _remeasure();
                                  },
                          ),
                        ),
                        if (bg != kShareBackgrounds.last)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: accent),
                          const SizedBox(height: 12),
                          Text(l('shareLoadingImage'),
                              style: TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontSize: 13,
                                  color: isDark
                                      ? AppColors.darkTextSec
                                      : AppColors.textSecondary)),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _ShareButton(
                            key: _textKey,
                            icon: Icons.text_fields_rounded,
                            label: l('shareAsText'),
                            filled: false,
                            isDark: isDark,
                            onTap: () => _share(asImage: false, from: _textKey),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ShareButton(
                            key: _imageKey,
                            icon: Icons.image_rounded,
                            label: l('shareAsImage'),
                            filled: true,
                            isDark: isDark,
                            onTap: () => _share(asImage: true, from: _imageKey),
                          ),
                        ),
                      ],
                    ),
                  if (!_busy) ...[
                    const SizedBox(height: 10),
                    _ShareButton(
                      icon: Icons.download_rounded,
                      label: l('saveToPhotos'),
                      filled: false,
                      isDark: isDark,
                      onTap: _saveToPhotos,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A swatch of the ground a card can be drawn on, showing the actual
/// gradient and gold rather than a colour name — the reader is choosing
/// how the image will LOOK, so the choice shows it.
class _BackgroundSwatch extends StatelessWidget {
  final ShareCardStyle style;
  final String label;
  final bool selected;
  final Color accent;
  final Color labelColor;
  final VoidCallback? onTap;

  const _BackgroundSwatch({
    required this.style,
    required this.label,
    required this.selected,
    required this.accent,
    required this.labelColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [style.top, style.bottom],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? accent : style.gold.withValues(alpha: 0.45),
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Center(
              // A stroke of the gold that the frame and the surah band
              // are drawn in, so the swatch previews both colours the
              // card is actually made of.
              child: selected
                  ? Icon(Icons.check_rounded, size: 20, color: style.gold)
                  : Container(
                      width: 22,
                      height: 2,
                      color: style.gold.withValues(alpha: 0.8)),
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? accent : labelColor)),
        ],
      ),
    );
  }
}

/// Minus / count / plus, for choosing how many consecutive verses go on
/// the card.
class _VerseCounter extends StatelessWidget {
  final int count;
  final int max;
  final bool enabled;
  final bool isDark;
  final String label;
  final ValueChanged<int> onChanged;

  const _VerseCounter({
    required this.count,
    required this.max,
    required this.enabled,
    required this.isDark,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.darkPrimary : AppColors.primary;
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;
    final border = isDark ? AppColors.darkBorder : AppColors.border;

    Widget step(IconData icon, int to, bool on) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled && on ? () => onChanged(to) : null,
          child: Container(
            width: 38,
            height: 34,
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: enabled && on ? accent : border),
          ),
        );

    return Row(
      children: [
        Icon(Icons.format_list_numbered_rounded, size: 20, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontFamily: '.SF Pro Text', fontSize: 15, color: textColor)),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            step(Icons.remove_rounded, count - 1, count > 1),
            SizedBox(
              width: 34,
              child: Text('$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor)),
            ),
            step(Icons.add_rounded, count + 1, count < max),
          ]),
        ),
      ],
    );
  }
}

class _ShareButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool isDark;
  final VoidCallback onTap;

  const _ShareButton({
    super.key,
    required this.icon,
    required this.label,
    required this.filled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.darkPrimary : AppColors.primary;
    final fg = filled ? Colors.white : accent;
    return Material(
      color: filled ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: accent.withValues(alpha: 0.5), width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

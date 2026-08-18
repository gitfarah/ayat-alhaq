import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../l10n/app_strings.dart';
import '../models/quran_page_meta.dart';
import '../services/bookmark_service.dart';
import '../services/highlight_service.dart';
import '../services/mushaf_v2_service.dart';
import '../services/quran_audio_service.dart';
import '../services/quran_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/ayah_note_sheet.dart';
import '../widgets/ayah_share_sheet.dart';
import '../widgets/ayah_sheet_header.dart';
import '../widgets/reciter_picker.dart';
import '../widgets/tajweed_legend_bar.dart';
import 'tafsir_screen.dart';

/// Reading the Mushaf a page at a time, but set the way a reader wants
/// to READ rather than the way the print is justified: each ayah gets
/// its own block, stacked under the one before it, at a size the reader
/// chooses — with the printed page's own KFGQPC glyphs, so it is still
/// the Mushaf's calligraphy and not a reflowing substitute face.
///
/// The two things it deliberately keeps from Mushaf mode:
///   * page boundaries and finger-following page turns, so "where am I"
///     still means a real page number a reader can hold in their head;
///   * the page's own glyph font, tajweed cut or plain (the tajweed
///     switch picks between two REAL font cuts — see
///     [MushafV2Service.editionFor] — rather than colouring letters
///     ourselves, which a word-atomic glyph font cannot do).
///
/// The one thing it deliberately drops: the printed line structure. A
/// Mushaf line packs whatever words fit, so ayahs sit side by side and
/// a long ayah is cut wherever the measure ran out. Here an ayah is a
/// unit — which is what makes room for a translation under each one.
class MushafReaderScreen extends StatefulWidget {
  final int initialPage;

  /// Open on a particular verse — what a search hit, a bookmark or a
  /// resumed last-read needs. The page it lives on is looked up, and
  /// the page then opens scrolled to that verse rather than at its top.
  final int? targetSurah;
  final int? targetAyah;

  const MushafReaderScreen({
    super.key,
    this.initialPage = 1,
    this.targetSurah,
    this.targetAyah,
  });

  @override
  State<MushafReaderScreen> createState() => _MushafReaderScreenState();
}

class _MushafReaderScreenState extends State<MushafReaderScreen> {
  late final PageController _pageCtrl;
  late int _page;

  /// "surah:ayah" → colour name, for the marks drawn on the page. Held
  /// for the whole Mushaf rather than per page: they are a few dozen
  /// entries at most, and a page turn should not have to wait on a
  /// lookup to know whether the verse under the reader is marked.
  Map<String, String> _highlights = const {};
  Map<String, String> _bookmarks = const {};

  /// The full highlight record, keyed the same way — [_highlights] only
  /// carries the colour (what the page paints), but the tap sheet also
  /// needs to know whether a note already exists and preview it.
  Map<String, Highlight> _highlightRecords = const {};

  static String _k(int surah, int ayah) => '$surah:$ayah';

  /// Whether the chrome (top bar, bottom info/legend/transport) is
  /// showing. Both float OVER a full-bleed page rather than shrinking
  /// it — the same convention Mushaf mode already uses — so a tap
  /// clears the screen down to just the verses, which is what actually
  /// gives a reader more room, not a fixed trim of the bars' own
  /// padding.
  bool _barsVisible = true;

  /// Owned here rather than inside TajweedLegendBar, so the scrolling
  /// list below can reserve enough bottom padding for whichever height
  /// the legend is currently at — see [_bottomReserve].
  bool _legendExpanded = true;

  /// Whether the CURRENT font cut (whichever [_editionId] resolves to
  /// right now) is fully cached. Checked once per edition change rather
  /// than kept live — Mushaf mode's own equivalent is a rare, manual
  /// action, not something that needs a stream.
  bool _fullyDownloaded = false;
  String? _fullyDownloadedFor;

  Future<void> _checkDownloaded(String editionId) async {
    if (_fullyDownloadedFor == editionId) return;
    final done = await MushafV2Service.isFullyDownloaded(editionId);
    if (!mounted) return;
    setState(() {
      _fullyDownloaded = done;
      _fullyDownloadedFor = editionId;
    });
  }

  void _setBars(bool visible) {
    if (_barsVisible == visible) return;
    setState(() => _barsVisible = visible);
    try {
      SystemChrome.setEnabledSystemUIMode(
          visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
    } catch (_) {
      // Cosmetic only — never let it break bar toggling.
    }
  }

  /// Auto-follow: the reader turns pages (and scrolls within one) to
  /// keep the currently-reciting ayah on screen — the page-based
  /// equivalent of the old reader's continuous-scroll follow.
  QuranAudioService? _audioSvc;
  int? _lastFollowedGlobalAyah;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(1, MushafV2Service.totalPages);
    _pageCtrl = PageController(initialPage: _page - 1);
    _loadMarks();
    _goToTarget();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audio = context.read<QuranAudioService>();
      // +1/-1 across surah boundaries for free: global ayah numbers run
      // 1..6236 straight through the whole Quran, the same numbering
      // QuranAudioService already plays from.
      audio.nextAyahResolver = (current) =>
          current < 6236 ? current + 1 : null;
      _audioSvc = audio;
      audio.removeListener(_followAudio);
      audio.addListener(_followAudio);
    });
  }

  void _followAudio() {
    final audio = _audioSvc;
    if (!mounted || audio == null || !audio.hasActiveTrack) return;
    final g = audio.currentGlobalAyah;
    if (g == null || g == _lastFollowedGlobalAyah) return;
    _lastFollowedGlobalAyah = g;
    final (surah, ayah) = _surahAyahFromGlobal(g);
    _jumpTo(surah, ayah, animate: true);
  }

  static (int, int) _surahAyahFromGlobal(int global) {
    var remaining = global;
    for (var i = 0; i < QuranPageMeta.ayahCounts.length; i++) {
      if (remaining <= QuranPageMeta.ayahCounts[i]) return (i + 1, remaining);
      remaining -= QuranPageMeta.ayahCounts[i];
    }
    return (114, QuranPageMeta.ayahCounts.last);
  }

  /// Which verse the page should open scrolled to, while it is still the
  /// page that verse is on. Cleared on the next USER-driven page turn —
  /// see [_programmaticPageChange] — since once the reader has moved on
  /// their own, landing somewhere mid-page would be a surprise.
  int? _targetSurah;
  int? _targetAyah;

  /// Guards onPageChanged: a page flip [_jumpTo] itself starts (to
  /// follow recitation, or to open on a passed-in verse) must not have
  /// its own target wiped the moment the flip lands — only a swipe the
  /// READER made should clear it.
  bool _programmaticPageChange = false;

  Future<void> _goToTarget() =>
      _jumpTo(widget.targetSurah, widget.targetAyah);

  Future<void> _jumpTo(int? surah, int? ayah, {bool animate = false}) async {
    if (surah == null || ayah == null) return;
    try {
      final page = await QuranService.pageOfGlobalAyah(
          QuranPageMeta.globalAyahNumber(surah, ayah));
      if (!mounted || page < 1 || page > MushafV2Service.totalPages) return;
      _targetSurah = surah;
      _targetAyah = ayah;
      if (page == _page) {
        // Already on the right page — still need a rebuild so the
        // ayah-list inside it picks up the (possibly new) target and
        // scrolls to it.
        setState(() {});
        return;
      }
      _programmaticPageChange = true;
      setState(() => _page = page);
      if (_pageCtrl.hasClients) {
        // A verse the reader explicitly asked for lands at once; one
        // recitation is following moves there the way a page actually
        // turns, so the reader can see it happen.
        if (animate) {
          await _pageCtrl.animateToPage(page - 1,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut);
        } else {
          _pageCtrl.jumpToPage(page - 1);
        }
      }
    } catch (_) {
      // A page that cannot be resolved leaves the reader where it was.
      _programmaticPageChange = false;
    }
  }

  Future<void> _loadMarks() async {
    final results = await Future.wait([
      HighlightService.getAllHighlights(),
      BookmarkService.getAllBookmarks(),
    ]);
    if (!mounted) return;
    setState(() {
      _highlightRecords = {
        for (final h in results[0] as List<Highlight>)
          _k(h.surahNumber, h.ayahNumber): h,
      };
      _highlights = {
        for (final e in _highlightRecords.entries) e.key: e.value.color,
      };
      _bookmarks = {
        for (final b in results[1] as List<Bookmark>)
          _k(b.surahNumber, b.ayahNumber): b.color,
      };
    });
  }

  @override
  void dispose() {
    _audioSvc?.removeListener(_followAudio);
    _pageCtrl.dispose();
    // Never leave the app stuck in immersive mode after this screen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _editionId(SettingsService s) =>
      MushafV2Service.editionFor(s.mushafEdition, tajweed: s.tajweed);

  /// How much bottom padding the scrolling ayah list needs to reserve
  /// so its last visible line is never hidden BEHIND the floating
  /// bottom bar — that bar overlays the list rather than shrinking it,
  /// so nothing else keeps them apart.
  ///
  /// Deliberately a generous fixed estimate per component rather than
  /// measuring the bar's actual rendered height: the exact wrap height
  /// of ~15 legend chips shifts with font scale and screen width in a
  /// way not worth chasing pixel-for-pixel, and a little unused
  /// scroll space at the end of a page is a far cheaper mistake than
  /// a line of Quran text left sitting behind an opaque bar.
  double _bottomReserve(
      {required bool legendShowing, required bool audioShowing}) {
    var h = 0.0;
    if (legendShowing) h += _legendExpanded ? 150 : 40;
    h += audioShowing ? 90 : 46; // now-playing transport, or the plain
    //                             page/juz/hizb strip either way.
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final audio = context.watch<QuranAudioService>();
    final isDark = settings.isDarkIn(context);
    // The same true black the SVG Mushaf goes to in the dark: a reading
    // surface, not a card floating on the app's chrome.
    final ground = isDark ? Colors.black : AppColors.surface;
    final legendShowing = settings.tajweed &&
        MushafV2Service.hasTajweedCut(settings.mushafEdition);
    final bottomReserve = _bottomReserve(
        legendShowing: legendShowing, audioShowing: audio.hasActiveTrack);
    final editionId = _editionId(settings);
    _checkDownloaded(editionId); // guarded — a no-op once already known

    return Scaffold(
      backgroundColor: ground,
      body: Stack(children: [
        // ── The pages: ALWAYS full-bleed, same as Mushaf mode. The
        // chrome floats on top and never resizes the page, so hiding it
        // is what actually hands the reader the extra room — trimming
        // the bars' own padding while they stay permanently on screen
        // would not.
        Positioned.fill(
          child: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setBars(!_barsVisible),
              child: PageView.builder(
                controller: _pageCtrl,
                reverse: true,
                itemCount: MushafV2Service.totalPages,
                onPageChanged: (i) => setState(() {
                  _page = i + 1;
                  // A flip [_jumpTo] itself started keeps its target;
                  // one the reader made by swiping clears it — landing
                  // mid-page on a swipe the reader made themselves
                  // would be a surprise.
                  if (_programmaticPageChange) {
                    _programmaticPageChange = false;
                  } else {
                    _targetSurah = null;
                    _targetAyah = null;
                  }
                }),
                itemBuilder: (_, i) => _GlyphReaderPage(
                  page: i + 1,
                  editionId: _editionId(settings),
                  fontSize: settings.fontSize,
                  translationEdition: settings.translationEdition,
                  isDark: isDark,
                  bottomReserve: bottomReserve,
                  highlights: _highlights,
                  bookmarks: _bookmarks,
                  playingGlobalAyah: settings.recitationHighlight
                      ? audio.currentGlobalAyah
                      : null,
                  targetSurah: i + 1 == _page ? _targetSurah : null,
                  targetAyah: i + 1 == _page ? _targetAyah : null,
                  onTapAyah: _showAyahOptions,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedSlide(
            offset: _barsVisible ? Offset.zero : const Offset(0, -1.1),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: SafeArea(
              bottom: false,
              child: Container(
                  color: ground, child: _topBar(settings, isDark)),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: AnimatedSlide(
            offset: _barsVisible ? Offset.zero : const Offset(0, 1.1),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            // Same restructuring as Mushaf mode's equivalent overlay:
            // only the interactive now-playing TRANSPORT gets its own
            // SafeArea. The legend and the plain page/juz/hizb strip are
            // read-only text — wrapping them in the same reserved inset
            // left a stray empty band under the legend when it was the
            // last thing on screen (nothing playing).
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (legendShowing)
                TajweedLegendBar(
                  isDark: isDark,
                  expanded: _legendExpanded,
                  onToggle: () =>
                      setState(() => _legendExpanded = !_legendExpanded),
                ),
              // The same slot swaps content, exactly like the reader
              // mode this replaced: page/juz/hizb normally, the
              // now-playing transport the moment a recitation is
              // active.
              audio.hasActiveTrack
                  ? androidBottomSafeArea(_nowPlayingBar(isDark, audio))
                  : androidBottomSafeArea(_infoBar(isDark)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _topBar(SettingsService settings, bool isDark) {
    final ink = isDark ? AppColors.darkText : AppColors.textPrimary;
    final dim = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final accent = isDark ? AppColors.darkPrimary : AppColors.primary;
    final l = L10n.of(context);
    final surah = QuranPageMeta.surahName(_surahForBar());

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: ink),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              surah,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontFamily: 'QuranHafs', fontSize: 17, color: ink),
            ),
          ),
          // Only V4 ships both a tajweed and a plain cut; on V1/V2 the
          // switch would have nothing to switch between, so it is not
          // offered rather than shown doing nothing.
          if (MushafV2Service.hasTajweedCut(settings.mushafEdition))
            IconButton(
              tooltip: l(settings.tajweed ? 'tajweedOn' : 'tajweedOff'),
              icon: Icon(Icons.palette_outlined,
                  size: 21, color: settings.tajweed ? accent : dim),
              onPressed: () => settings.setTajweed(!settings.tajweed),
            ),
          IconButton(
            tooltip: l('translation'),
            icon: Icon(Icons.translate_rounded,
                size: 21,
                color: settings.translationEdition != null ? accent : dim),
            onPressed: () => _showTranslationSheet(settings, isDark),
          ),
          IconButton(
            tooltip: l('fontSizeLbl'),
            icon: Icon(Icons.format_size_rounded, size: 21, color: dim),
            onPressed: () => _showFontSizeSheet(settings, isDark),
          ),
          if (MushafV2Service.supportsFullOfflineDownload)
            _downloadButton(settings, accent, dim),
        ],
      ),
    );
  }

  /// Whole-Mushaf offline download — the reader's own version of the
  /// control Mushaf mode keeps in its ☰ menu, moved into the header
  /// here since this screen has no such menu. Downloads whichever font
  /// cut is CURRENTLY being read (tajweed or plain), matching how every
  /// edition's download already works — toggling tajweed afterward
  /// needs its own separate download, the same as switching edition
  /// does in Mushaf mode.
  Widget _downloadButton(SettingsService settings, Color accent, Color dim) {
    final editionId = _editionId(settings);
    return AnimatedBuilder(
      animation: MushafV2Service.bulkProgress,
      builder: (_, __) {
        final progress = MushafV2Service.bulkProgress.value;
        final running =
            progress != null && progress.editionId == editionId;
        final fraction =
            running && progress.total > 0 ? progress.done / progress.total : 0.0;
        // Hardcoded Arabic, not an l10n key — matching Mushaf mode's own
        // download row in its ☰ menu, which does the same for this
        // exact feature.
        return IconButton(
          tooltip: _fullyDownloaded
              ? 'المصحف كامل محفوظ دون اتصال ✓'
              : running
                  ? 'جارٍ تنزيل المصحف — ${(fraction * 100).round()}٪'
                  : 'تنزيل المصحف كاملاً دون اتصال',
          icon: Icon(
              _fullyDownloaded
                  ? Icons.offline_pin_rounded
                  : running
                      ? Icons.downloading_rounded
                      : Icons.download_rounded,
              size: 21,
              color: _fullyDownloaded ? accent : dim),
          onPressed: () async {
            if (_fullyDownloaded) return;
            if (running) {
              MushafV2Service.cancelBulkDownload();
              return;
            }
            await MushafV2Service.startBulkDownload(editionId);
            if (!mounted) return;
            setState(() => _fullyDownloadedFor = null); // force a re-check
            _checkDownloaded(editionId);
          },
        );
      },
    );
  }

  /// The bar names the surah the CURRENT page opens in. The page itself
  /// is loaded asynchronously inside the PageView, so rather than reach
  /// into it, this uses the page→surah table — close enough for a label
  /// and always available immediately.
  int _surahForBar() {
    var surah = 1;
    for (var i = 0; i < QuranPageMeta.surahStartPages.length; i++) {
      if (QuranPageMeta.surahStartPages[i] <= _page) {
        surah = i + 1;
      } else {
        break;
      }
    }
    return surah;
  }

  /// The transport bar the old reader mode showed the moment a
  /// recitation was active — same controls, same copy, same layout,
  /// just naming the ayah by (surah, ayah-in-surah) since this reader
  /// has no flat per-surah ayah list to look the playing one up in.
  Widget _nowPlayingBar(bool isDark, QuranAudioService audio) {
    final l = L10n.of(context);
    final (surah, ayah) = audio.currentGlobalAyah == null
        ? (null, null)
        : _surahAyahFromGlobal(audio.currentGlobalAyah!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.stop_circle_rounded,
                color:
                    isDark ? AppColors.darkTextSec : AppColors.textSecondary),
            onPressed: audio.stop,
          ),
          IconButton(
            icon: Icon(
              audio.isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: isDark ? AppColors.darkPrimary : AppColors.primary,
              size: 34,
            ),
            onPressed: () {
              if (audio.currentGlobalAyah != null) {
                audio.togglePlayPause(audio.currentGlobalAyah!);
              }
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ayah != null
                        ? '${QuranPageMeta.surahName(surah!)} — '
                            '${l('ayahWord')} ${l.number(ayah)}'
                        : '',
                    style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color:
                          isDark ? AppColors.darkText : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    audio.isLoading
                        ? l('loading')
                        : (audio.isPlaying
                            ? '${l('nowReciting')} — ${audio.reciterName}'
                            : l('paused')),
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: '.SF Pro Text',
                        color: isDark
                            ? AppColors.darkTextSec
                            : AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: l('changeReciter'),
            icon: Icon(
              Icons.record_voice_over_rounded,
              color: isDark ? AppColors.darkTextSec : AppColors.textSecondary,
              size: 20,
            ),
            onPressed: () => showReciterPicker(context, audio, isDark),
          ),
          IconButton(
            tooltip: l('autoNext'),
            icon: Icon(
              audio.autoAdvance
                  ? Icons.repeat_on_rounded
                  : Icons.repeat_rounded,
              color: audio.autoAdvance
                  ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                  : (isDark ? AppColors.darkTextSec : AppColors.textSecondary),
              size: 20,
            ),
            onPressed: audio.toggleAutoAdvance,
          ),
        ],
      ),
    );
  }

  Widget _infoBar(bool isDark) {
    final dim = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final style =
        TextStyle(fontFamily: '.SF Pro Text', fontSize: 12, color: dim);
    final l = L10n.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: (isDark ? AppColors.darkBorder : AppColors.surfaceDim)
                    .withValues(alpha: 0.6))),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${l('pageWord')} ${l.number(_page)}', style: style),
          Text('${l('juzWord')} ${l.number(QuranPageMeta.juzForPage(_page))}',
              style: style),
          Text('${l('hizbWord')} ${l.number(QuranPageMeta.hizbForPage(_page))}',
              style: style),
        ],
      ),
    );
  }

  void _showTranslationSheet(SettingsService settings, bool isDark) {
    final l = L10n.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        final ink = isDark ? AppColors.darkText : AppColors.textPrimary;
        Widget row(String? edition, String name) => ListTile(
              title: Text(name,
                  style: TextStyle(
                      fontFamily: '.SF Pro Text', fontSize: 15, color: ink)),
              trailing: settings.translationEdition == edition
                  ? Icon(Icons.check_rounded,
                      color: isDark ? AppColors.darkPrimary : AppColors.primary)
                  : null,
              onTap: () {
                settings.setTranslationEdition(edition);
                Navigator.pop(sheetCtx);
              },
            );
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Text(l('translation'),
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: ink)),
                ),
                row(null, l('noTranslation')),
                ...QuranService.translationEditions.entries
                    .map((e) => row(e.key, e.value)),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFontSizeSheet(SettingsService settings, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        top: false,
        child: StatefulBuilder(
          builder: (_, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.of(context)('fontSizeLbl'),
                    style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.textPrimary)),
                Slider(
                  value: settings.fontSize,
                  min: 18,
                  max: 44,
                  divisions: 26,
                  onChanged: (v) {
                    settings.setFontSize(v);
                    setSheet(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The tap panel: the same green ayah header every other surface
  /// quotes a verse on, then the actions. The Arabic text is FETCHED —
  /// the page carries glyphs, which are private-use codepoints, not the
  /// real Unicode a share, a note or a tafsir lookup needs.
  /// Same tiles, same icons, same order and colours as the reader mode
  /// this replaced ([reader_screen.dart]'s `_showOptions`) — a reader
  /// who knew that sheet should not have to relearn it here.
  Future<void> _showAyahOptions(int surah, int ayah) async {
    final settings = context.read<SettingsService>();
    final isDark = settings.isDarkIn(context);
    final l = L10n.of(context);
    final audio = context.read<QuranAudioService>();
    final surahName = QuranPageMeta.surahName(surah);
    final globalAyah = QuranPageMeta.globalAyahNumber(surah, ayah);
    final text = await QuranService.getAyahText(surah, ayah);
    if (!mounted) return;

    final key = _k(surah, ayah);
    final bookmarkColor = _bookmarks[key];
    final existingNote = _highlightRecords[key];
    final playing = audio.currentGlobalAyah == globalAyah && audio.isPlaying;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AyahSheetHeader(
                ayahText: text,
                label: '$surahName — ${l('ayahWord')} ${l.number(ayah)}',
                surahNumber: surah,
                ayahNumber: ayah,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Play / pause recitation
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        playing
                            ? Icons.pause_circle_rounded
                            : Icons.play_circle_rounded,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        playing ? l('pauseRecitation') : l('playRecitation'),
                        style: const TextStyle(fontFamily: '.SF Pro Text'),
                      ),
                      onTap: () async {
                        Navigator.pop(sheetCtx);
                        // First-ever playback: let the reader pick the
                        // reciter once; the choice then sticks until
                        // changed on purpose.
                        if (!mounted) return;
                        final ok =
                            await ensureReciterChosen(context, audio, isDark);
                        if (!ok) return;
                        await audio.togglePlayPause(globalAyah);
                        if (mounted && audio.error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(audio.error!)));
                        }
                      },
                    ),
                    // Tafsir — same position as the Mushaf sheet: right
                    // after recitation, before the marking options.
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.menu_book_rounded,
                          color: AppColors.primary),
                      title: Text(l('tafsir'),
                          style: const TextStyle(fontFamily: '.SF Pro Text')),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TafsirScreen(
                              surahNumber: surah,
                              surahName: surahName,
                              ayahNumber: ayah,
                            ),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          bookmarkColor != null
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_add_rounded,
                          color: bookmarkColor != null
                              ? AppColors.highlight(bookmarkColor)
                              : AppColors.primary),
                      title: Text(l('bookmark'),
                          style: const TextStyle(fontFamily: '.SF Pro Text')),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _showMarkPicker(
                            surah: surah,
                            ayah: ayah,
                            surahName: surahName,
                            isDark: isDark,
                            bookmark: true);
                      },
                    ),
                    // Highlight ayah — opens its own colour picker, same
                    // as the bookmark tile above; the colours never show
                    // inline in this sheet.
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.draw_rounded,
                          color: AppColors.secondary),
                      title: Text(l('highlightAyah'),
                          style: const TextStyle(fontFamily: '.SF Pro Text')),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _showMarkPicker(
                            surah: surah,
                            ayah: ayah,
                            surahName: surahName,
                            isDark: isDark,
                            bookmark: false);
                      },
                    ),
                    // Note on this ayah — lives on the colour mark, so
                    // writing one on an unmarked ayah marks it too.
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          existingNote?.hasNote == true
                              ? Icons.sticky_note_2_rounded
                              : Icons.note_add_outlined,
                          color: AppColors.secondary),
                      title: Text(
                          existingNote?.hasNote == true
                              ? l('editNote')
                              : l('addNote'),
                          style: const TextStyle(fontFamily: '.SF Pro Text')),
                      subtitle: existingNote?.hasNote == true
                          ? Text(existingNote!.note!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontSize: 12,
                                  color: isDark
                                      ? AppColors.darkTextSec
                                      : AppColors.textSecondary))
                          : null,
                      onTap: () async {
                        Navigator.pop(sheetCtx);
                        // A note is stored on the highlight record, so
                        // writing one can change the mark on the page.
                        await showAyahNoteSheet(
                          context,
                          surahNumber: surah,
                          ayahNumber: ayah,
                          surahName: surahName,
                          page: _page,
                          ayahText: text,
                        );
                        await _loadMarks();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.ios_share_rounded,
                          color: AppColors.accent),
                      title: Text(l('shareAyah'),
                          style: const TextStyle(fontFamily: '.SF Pro Text')),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        showAyahShareSheet(
                          context,
                          surahNumber: surah,
                          surahName: surahName,
                          ayahNumber: ayah,
                          ayahText: text,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _MushafReaderScreenState {
  /// One picker for both kinds of mark — they differ only in which
  /// service stores the colour and which icon the dot carries, and a
  /// reader choosing "green" means the same thing either way.
  void _showMarkPicker({
    required int surah,
    required int ayah,
    required String surahName,
    required bool isDark,
    required bool bookmark,
  }) {
    final l = L10n.of(context);
    final key = _MushafReaderScreenState._k(surah, ayah);
    final current = bookmark ? _bookmarks[key] : _highlights[key];

    Future<void> pick(String? color) async {
      Navigator.pop(context);
      if (bookmark) {
        if (color == null) {
          await BookmarkService.deleteBookmarkByAyah(surah, ayah);
        } else {
          await BookmarkService.addBookmark(Bookmark(
            surahNumber: surah,
            ayahNumber: ayah,
            surahName: surahName,
            color: color,
            createdAt: DateTime.now(),
            page: _page,
          ));
        }
      } else {
        if (color == null) {
          await HighlightService.deleteHighlight(surah, ayah);
        } else {
          await HighlightService.addHighlight(Highlight(
            surahNumber: surah,
            ayahNumber: ayah,
            surahName: surahName,
            color: color,
            createdAt: DateTime.now(),
            page: _page,
          ));
        }
      }
      await _loadMarks();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              l(bookmark ? 'chooseBookmarkColor' : 'chooseHighlightColor'),
              style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkText : AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The "no colour" dot only appears when there IS a mark
                // to clear, so it never reads as a sixth colour.
                if (current != null)
                  _MarkDot(
                    color: Colors.grey.shade300,
                    selected: false,
                    icon: Icons.close_rounded,
                    onTap: () => pick(null),
                  ),
                ...AppColors.highlights.entries.map((e) => _MarkDot(
                      color: e.value,
                      selected: current == e.key,
                      icon: bookmark ? Icons.bookmark_rounded : null,
                      onTap: () => pick(e.key),
                    )),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _MarkDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  const _MarkDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border:
              selected ? Border.all(color: AppColors.primary, width: 3) : null,
        ),
        child: icon == null
            ? null
            : Icon(icon, size: 20, color: Colors.black.withValues(alpha: 0.55)),
      ),
    );
  }
}

/// One page, regrouped from printed LINES into per-ayah blocks.
class _GlyphReaderPage extends StatefulWidget {
  final int page;
  final String editionId;
  final double fontSize;
  final String? translationEdition;
  final bool isDark;

  /// Bottom padding to reserve in the ayah list so its last visible
  /// line clears the floating bottom bar instead of sitting behind it
  /// — see [_MushafReaderScreenState._bottomReserve].
  final double bottomReserve;
  final Map<String, String> highlights;
  final Map<String, String> bookmarks;
  final int? playingGlobalAyah;
  final int? targetSurah;
  final int? targetAyah;
  final void Function(int surah, int ayah) onTapAyah;

  const _GlyphReaderPage({
    required this.page,
    required this.editionId,
    required this.fontSize,
    required this.translationEdition,
    required this.isDark,
    required this.bottomReserve,
    required this.highlights,
    required this.bookmarks,
    required this.playingGlobalAyah,
    required this.targetSurah,
    required this.targetAyah,
    required this.onTapAyah,
  });

  @override
  State<_GlyphReaderPage> createState() => _GlyphReaderPageState();
}

class _GlyphReaderPageState extends State<_GlyphReaderPage> {
  /// "edition:surah" → ayah number → translated line. Static because a
  /// PageView rebuilds and disposes its children constantly while
  /// swiping, and a translation already fetched should not be fetched
  /// again just because the reader turned back a page.
  static final Map<String, Map<int, String>> _translations = {};

  late Future<MushafV2Page> _page;
  Map<int, String> _lines = const {};

  Future<MushafV2Page> _fetch({bool retry = false}) => MushafV2Service.getPage(
        widget.page,
        editionId: widget.editionId,
        // The tajweed cut paints from its own CPAL palette and ignores
        // the colour we ask for, so the ground has to be chosen at LOAD
        // time — see MushafV2Service's palette note.
        darkPalette: widget.isDark,
        retry: retry,
      );

  @override
  void initState() {
    super.initState();
    _page = _fetch();
  }

  @override
  void didUpdateWidget(_GlyphReaderPage old) {
    super.didUpdateWidget(old);
    if (old.editionId != widget.editionId ||
        old.page != widget.page ||
        old.isDark != widget.isDark) {
      // NOT `setState(() => _page = _fetch())`: an arrow body is the
      // assignment EXPRESSION's value, which is the Future itself — so
      // that closure hands setState a Future, and setState's own
      // Future-return guard (meant to catch `setState(() async {...})`)
      // trips on it. A block body discards the expression's value and
      // returns void instead.
      setState(() {
        _page = _fetch();
      });
    }
    if (old.translationEdition != widget.translationEdition) {
      setState(() => _lines = const {});
    }
  }

  /// Translations arrive per SURAH, so a page is covered by at most the
  /// two or three surahs it touches. Fetched after the Arabic is already
  /// on screen — a translation is an addition to the page, never
  /// something the page waits for.
  Future<void> _loadTranslations(Set<int> surahs) async {
    final edition = widget.translationEdition;
    if (edition == null) return;
    final merged = <int, String>{};
    var changed = false;
    for (final surah in surahs) {
      final key = '$edition:$surah';
      var cached = _translations[key];
      if (cached == null) {
        try {
          final ayahs = await QuranService.getSurahAyahs(surah,
              translationEdition: edition);
          cached = {
            for (final a in ayahs)
              if (a.translation != null) a.numberInSurah: a.translation!,
          };
          _translations[key] = cached;
          changed = true;
        } catch (_) {
          // A translation that will not load leaves the Arabic alone.
          continue;
        }
      }
      merged.addAll(cached);
    }
    if (!mounted) return;
    if (changed || merged.length != _lines.length) {
      setState(() => _lines = merged);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MushafV2Page>(
      future: _page,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Retry(
            isDark: widget.isDark,
            onRetry: () => setState(() {
              _page = _fetch(retry: true);
            }),
          );
        }
        final page = snap.data;
        if (page == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final blocks = page.blocks;
        if (widget.translationEdition != null) {
          final surahs = {
            for (final b in blocks)
              if (b.kind == MushafBlockKind.ayah) b.surah
          };
          if (surahs.isNotEmpty) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _loadTranslations(surahs));
          }
        }

        final ink = widget.isDark ? AppColors.darkText : AppColors.onSurface;
        // Opens ON the verse the caller asked for rather than at the top
        // of its page — a search hit near the foot of a page would
        // otherwise land off-screen and look like the wrong page.
        final target = widget.targetAyah == null
            ? 0
            : blocks.indexWhere((b) =>
                b.kind == MushafBlockKind.ayah &&
                b.surah == widget.targetSurah &&
                b.ayah == widget.targetAyah);
        return ScrollablePositionedList.builder(
          initialScrollIndex: target < 0 ? 0 : target,
          padding: EdgeInsets.fromLTRB(18, 10, 18, 28 + widget.bottomReserve),
          itemCount: blocks.length,
          itemBuilder: (_, i) => _blockWidget(
            blocks[i],
            page: page,
            fontSize: widget.fontSize,
            ink: ink,
            isDark: widget.isDark,
            translation: _lines[blocks[i].ayah],
            translationRtl: widget.translationEdition != null &&
                QuranService.isRtlEdition(widget.translationEdition!),
            highlight:
                widget.highlights['${blocks[i].surah}:${blocks[i].ayah}'],
            bookmark: widget.bookmarks['${blocks[i].surah}:${blocks[i].ayah}'],
            playing: blocks[i].kind == MushafBlockKind.ayah &&
                widget.playingGlobalAyah ==
                    QuranPageMeta.globalAyahNumber(
                        blocks[i].surah, blocks[i].ayah),
            onTapAyah: widget.onTapAyah,
          ),
        );
      },
    );
  }
}

Widget _blockWidget(
  MushafBlock block, {
  required MushafV2Page page,
  required double fontSize,
  required Color ink,
  required bool isDark,
  required String? translation,
  required bool translationRtl,
  required String? highlight,
  required String? bookmark,
  required bool playing,
  required void Function(int surah, int ayah) onTapAyah,
}) {
  switch (block.kind) {
    case MushafBlockKind.surahHeader:
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'surah${block.surah.toString().padLeft(3, '0')}',
            textDirection: TextDirection.rtl,
            maxLines: 1,
            style: TextStyle(
              fontFamily: page.surahFontFamily,
              fontSize: fontSize * 1.5,
              height: 1,
              color: ink,
            ),
          ),
        ),
      );
    case MushafBlockKind.basmala:
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '﷽',
            textDirection: TextDirection.rtl,
            maxLines: 1,
            style: TextStyle(
              fontFamily: page.bismillahFontFamily,
              fontSize: fontSize * 1.5,
              height: 1,
              color: ink,
            ),
          ),
        ),
      );
    case MushafBlockKind.ayah:
      final dim = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
      // A highlight tints the block behind the verse; a bookmark rides
      // as a ribbon on the reading edge. Both stay well under the ink so
      // the calligraphy is never the thing that got dimmer. "Now
      // reciting" wins over a saved highlight when both apply — it is
      // the more transient, more relevant fact in the moment.
      //
      // This is whole-BLOCK, not word-by-word: the old reader's
      // RecitingAyahText tracks word timings against real Unicode runs,
      // which a glyph block's opaque PUA codepoints cannot be split
      // into that way.
      final accent = isDark ? AppColors.darkPrimary : AppColors.primary;
      final tint = playing
          ? accent.withValues(alpha: isDark ? 0.20 : 0.14)
          : highlight == null
              ? null
              : AppColors.highlight(highlight)
                  .withValues(alpha: isDark ? 0.22 : 0.30);
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        // A long press, not a tap — matching Mushaf mode's own ayah
        // regions. A plain tap here used to open the sheet on almost
        // any touch (this block is most of the screen), which is also
        // what the background's own tap-to-hide-chrome gesture wants;
        // long press leaves that alone and reserves itself for a
        // reader who deliberately holds on a verse.
        onLongPress: () => onTapAyah(block.surah, block.ayah),
        child: Container(
          decoration: tint == null
              ? null
              : BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                  border: playing
                      ? Border.all(color: accent.withValues(alpha: 0.6))
                      : null,
                ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (bookmark != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.bookmark_rounded,
                      size: 16, color: AppColors.highlight(bookmark)),
                ),
              // The verse fills from the RIGHT — where Arabic starts —
              // so a wrapped ayah keeps a straight reading edge instead
              // of drifting in and out on a centred axis.
              //
              // One WORD per Text, not the whole verse concatenated
              // into one string: these fonts map a glyph to a whole
              // word, and neither the printed page nor any other
              // renderer in this app ever just flows that as plain
              // text — every one of them places each word as its own
              // element with an explicit gap between them (see
              // MushafBlock.words' doc). Skipping that step here is
              // what ran every word into the next.
              Wrap(
                textDirection: TextDirection.rtl,
                spacing: fontSize * 0.22,
                runSpacing: fontSize * 0.15,
                children: [
                  for (final word in block.words)
                    Text(
                      word,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: page.fontFamily,
                        fontSize: fontSize,
                        // These faces ride high in the em box and carry
                        // tall marks; anything tighter than this
                        // collides the vowel signs of one line with the
                        // next.
                        height: 2.0,
                        color: ink,
                      ),
                    ),
                ],
              ),
              if (translation != null) ...[
                const SizedBox(height: 6),
                // A translation runs in ITS OWN direction, not the
                // page's. Laid out RTL, a German or English line pushes
                // its full stop to the far left and starts the next line
                // with it — which is exactly what it was doing.
                Text(
                  translation,
                  textAlign: TextAlign.start,
                  textDirection:
                      translationRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 14,
                    height: 1.5,
                    color: dim,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
  }
}

class _Retry extends StatelessWidget {
  final bool isDark;
  final VoidCallback onRetry;

  const _Retry({required this.isDark, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 40,
              color: isDark ? AppColors.darkTextSec : AppColors.textSecondary),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text(l('retry'))),
        ],
      ),
    );
  }
}

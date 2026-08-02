import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quran_page_meta.dart';
import '../services/mushaf_svg_service.dart';
import '../services/quran_service.dart';
import '../services/bookmark_service.dart';
import '../services/highlight_service.dart';
import '../services/khatma_service.dart';
import '../services/library_events.dart';
import '../services/quran_audio_service.dart';
import '../services/screen_awake.dart';
import '../services/settings_service.dart';
import '../services/surah_header_service.dart';
import '../services/tajweed_service.dart';
import '../l10n/app_strings.dart';
import '../theme.dart';
import '../widgets/ayah_note_sheet.dart';
import '../widgets/mushaf_page_furniture.dart';
import '../widgets/reciter_picker.dart';
import '../widgets/surah_banner_painter.dart';
import '../widgets/surah_frame.dart';
import 'tafsir_screen.dart';

class MushafSvgScreen extends StatefulWidget {
  final int? startPage;
  const MushafSvgScreen({super.key, this.startPage});

  @override
  State<MushafSvgScreen> createState() => _MushafSvgScreenState();
}

class _MushafSvgScreenState extends State<MushafSvgScreen>
    with
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin,
        // Reading is a long, hands-off activity — hold the screen fully
        // lit for as long as the Mushaf is open.
        KeepsScreenAwake<MushafSvgScreen> {
  late int _pageNum;

  /// Real swipeable paging (finger-following, like printed pages).
  /// Nullable because it is (re)created in build() where screen width
  /// is known — a wide screen pages by 2-page spreads.
  PageController? _pageCtrl;
  bool _wide = false;

  /// Per-index page-load futures so rebuilds don't refetch; pruned to
  /// the neighbourhood of the current page to keep memory flat.
  /// Page loads in flight or done, by PageView index, each remembering
  /// the edition it was started for. Comparing that on every build is
  /// what makes an edition switch take effect immediately: relying on
  /// the switch handler to clear the map meant any other route to a
  /// change — or a rebuild that beat the clear — kept showing the old
  /// riwayah until the reader turned a page.
  final Map<int, (String, Future<List<MushafPageData>>)> _pageFutures = {};

  /// Same idea for the reflowing text edition, keyed by page number,
  /// plus its per-ayah long-press recognizers keyed by global ayah —
  /// held across rebuilds (a TextSpan recognizer must outlive the span)
  /// and disposed with the screen.
  final Map<int, Future<List<PageAyah>>> _textFutures = {};
  final Map<int, LongPressGestureRecognizer> _textRecognizers = {};

  /// Measured fit sizes for the reflowing pages, keyed by page and box.
  final Map<String, double> _fitCache = {};

  /// Page artwork with its medallions tinted, held against the page
  /// object itself. A key built from the page number and the CURRENT
  /// edition looked right but was not: while a switch is loading, the
  /// FutureBuilder still holds the previous edition's page, so the old
  /// artwork got cached under the new edition's key and was served from
  /// then on. An Expando cannot mix them up, and needs no eviction —
  /// the entry dies with the page it belongs to.
  final Expando<String> _tintedCache = Expando<String>('tinted mushaf page');

  bool _isCachedOffline = false;
  bool _barsVisible = true;
  List<Bookmark> _bookmarks = [];
  List<Highlight> _highlights = [];
  QuranAudioService? _audioService;
  int? _lastFollowedAyah;

  /// Whether the whole Mushaf is stored offline. Download itself is
  /// owned by MushafSvgService and survives leaving this screen.
  bool _fullyDownloaded = false;

  /// Responsive zoom: pinching changes how WIDE the page is drawn. At
  /// 1.0 the whole page fits the screen; above that the page is laid
  /// out wider (so the script grows) and the reader scrolls vertically
  /// — the page is never dragged around in two dimensions.
  double _zoom = 1.0;
  double _zoomStart = 1.0;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 3.5;

  bool get _isZoomed => _zoom > 1.01;

  /// Whether this edition prints its own furniture on the leaf — the
  /// running head and the ornamented page number — instead of leaving
  /// that to the floating bars. Those editions also lose the bottom
  /// page-number bar and its arrows, which only duplicate it.
  ///
  /// Any edition that renders an actual PAGE — the five SVG-artwork
  /// riwayat — carries this the same way a printed leaf does. Only the
  /// reflowing text edition has no page to print it on, and keeps the
  /// floating bar for its page number.
  bool get _usesPageFurniture => MushafSvgService.edition.isArtwork;

  void _onScaleStart(ScaleStartDetails d) => _zoomStart = _zoom;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount < 2) return; // one finger = swipe/tap, not zoom
    final next = (_zoomStart * d.scale).clamp(_minZoom, _maxZoom);
    if ((next - _zoom).abs() > 0.005) setState(() => _zoom = next);
  }

  /// Tap feedback: the just-tapped ayah flashes briefly so the user
  /// sees exactly which ayah the tap registered on.
  AyahHitRegion? _flashRegion;
  late final AnimationController _flashCtrl;

  String _surahName(int n) => QuranPageMeta.surahName(n);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageNum = widget.startPage ?? 1;
    _loadMarks();
    // Repaint the ayah overlays whenever a bookmark/highlight is added
    // or removed anywhere in the app (this screen's own sheet included).
    LibraryEvents.bookmarks.addListener(_loadMarks);
    LibraryEvents.highlights.addListener(_loadMarks);
    _flashCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350))
      ..addListener(() => setState(() {}))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() => _flashRegion = null);
        }
      });
    // Follow the recitation: when auto-advance moves past the visible
    // page(s), turn the page automatically.
    _audioService = context.read<QuranAudioService>();
    _audioService!.addListener(_followRecitation);
    // Ornamental surah-name frames (measured band positions, per edition).
    _loadHeaderBands();
    // Tajweed colouring for the reflowing text edition. Loaded up front
    // so flipping the setting is instant.
    if (!TajweedService.isLoaded) {
      TajweedService.load().then((_) {
        if (mounted) setState(() {});
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Auto-advance simply moves to the next global ayah — the Mushaf
      // view isn't scoped to one surah, so recitation flows across
      // surah boundaries just like reading the pages does.
      _audioService!.nextAyahResolver = (g) => g < 6236 ? g + 1 : null;
      _onPageSettled(_pageNum);
      _maybeOfferFullDownload();
      _maybeShowGestureHint();
    });
    MushafSvgService.bulkProgress.addListener(_onBulkProgress);
  }

  // ── PageView index mapping (wide screens page by 2-page spreads) ──

  int _indexForPage(int page) =>
      _wide ? (_spreadBase(page) - 1) ~/ 2 : page - 1;
  int _pageForIndex(int index) => _wide ? index * 2 + 1 : index + 1;
  int get _pageCount => _wide ? 302 : 604;

  /// Bookkeeping when a page becomes the visible one: last-read state,
  /// khatma tracking, neighbour preloads, offline badge.
  Future<void> _onPageSettled(int basePage) async {
    if (!mounted) return;
    setState(() => _pageNum = basePage);
    context.read<SettingsService>().saveLastRead(page: basePage);
    KhatmaService.markPageRead(basePage);
    if (_wide && basePage + 1 <= 604) KhatmaService.markPageRead(basePage + 1);

    // The text edition is bundled — nothing to prefetch, and it is
    // offline by definition.
    if (MushafSvgService.edition.isText) {
      _textFutures.removeWhere((k, _) => (k - basePage).abs() > 4);
      if (!_isCachedOffline) setState(() => _isCachedOffline = true);
      return;
    }

    final step = _wide ? 2 : 1;
    MushafSvgService.preload(basePage + step);
    MushafSvgService.preload(basePage + step + 1);
    MushafSvgService.preload(basePage - 1);

    // Keep only the current neighbourhood of load-futures alive so the
    // retained page data can't grow without bound.
    final center = _indexForPage(basePage);
    _pageFutures.removeWhere((k, _) => (k - center).abs() > 3);

    final cached = await MushafSvgService.isCached(basePage);
    if (mounted) setState(() => _isCachedOffline = cached);
  }

  /// Repaints the menu/progress UI while the service downloads pages,
  /// and refreshes the offline badge when the run ends.
  void _onBulkProgress() {
    if (!mounted) return;
    setState(() {});
    if (MushafSvgService.bulkProgress.value == null) {
      MushafSvgService.isFullyDownloaded().then((v) {
        if (mounted) setState(() => _fullyDownloaded = v);
      });
    }
  }

  /// Bars visibility + system chrome together: hiding the bars also
  /// hides the status/navigation bars so the page truly fills the
  /// screen; showing them restores normal chrome.
  void _setBars(bool visible) {
    if (_barsVisible == visible) return;
    setState(() => _barsVisible = visible);
    try {
      SystemChrome.setEnabledSystemUIMode(
          visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
    } catch (_) {
      // System chrome is cosmetic — never let it break bar toggling.
    }
  }

  /// One-time coach mark for the new gesture model.
  Future<void> _maybeShowGestureHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('gestureHintShown') ?? false) return;
    await prefs.setBool('gestureHintShown', true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 5),
        content: Text(
            'اضغط مطولاً على أي آية لعرض خياراتها، واضغط ضغطة سريعة لإظهار أو إخفاء الأشرطة',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontFamily: '.SF Pro Text', height: 1.6))));
  }

  /// One-time offer (per install) to download the whole Mushaf for
  /// offline reading. Never silently pulls ~350 MB on the user's data
  /// plan — it asks first. Once accepted, an interrupted download
  /// RESUMES automatically every time the Mushaf is opened, without
  /// asking again; it can also always be started from the menu.
  Future<void> _maybeOfferFullDownload() async {
    if (!MushafSvgService.supportsFullOfflineDownload) return;
    _fullyDownloaded = await MushafSvgService.isFullyDownloaded();
    if (mounted) setState(() {});
    if (_fullyDownloaded || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('mushafDlAccepted') ?? false) {
      // User already said yes earlier — silently continue the download.
      MushafSvgService.startBulkDownload();
      return;
    }
    if (prefs.getBool('mushafDlPrompted') ?? false) return;
    await prefs.setBool('mushafDlPrompted', true);
    if (!mounted) return;
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('المصحف دون اتصال',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? AppColors.darkText : AppColors.textPrimary)),
        content: Text(
            'هل تريد تنزيل صفحات المصحف كاملة (٦٠٤ صفحات، ~٣٥٠ م.ب) لتتمكن من تصفحها دون اتصال بالإنترنت؟\nيمكنك بدء التنزيل لاحقاً من قائمة ☰ في أي وقت.',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                fontFamily: '.SF Pro Text',
                height: 1.8,
                fontSize: 14,
                color:
                    isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('لاحقاً', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تنزيل الآن',
                  style:
                      TextStyle(color: Colors.white, fontFamily: '.SF Pro Text'))),
        ],
      ),
    );
    if (go == true) {
      await prefs.setBool('mushafDlAccepted', true);
      MushafSvgService.startBulkDownload();
    }
  }

  @override
  void dispose() {
    // The bulk download deliberately keeps running — it belongs to the
    // service, not this screen.
    MushafSvgService.bulkProgress.removeListener(_onBulkProgress);
    // Never leave the app stuck in immersive mode after this screen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageCtrl?.dispose();
    _flashCtrl.dispose();
    for (final r in _textRecognizers.values) {
      r.dispose();
    }
    LibraryEvents.bookmarks.removeListener(_loadMarks);
    LibraryEvents.highlights.removeListener(_loadMarks);
    _audioService?.removeListener(_followRecitation);
    // Clear the resolver so it doesn't outlive this screen.
    _audioService?.nextAyahResolver = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Global ayah number of a hit region (only valid when the region's
  /// metadata is present, i.e. surah/ayah > 0).
  int _regionGlobal(AyahHitRegion r) =>
      QuranPageMeta.globalAyahNumber(r.surahNumber, r.ayahNumber);

  /// The ayah currently being recited, or null when audio is inactive.
  int? get _playingGlobalAyah {
    final a = _audioService;
    return (a != null && a.hasActiveTrack) ? a.currentGlobalAyah : null;
  }

  /// When recitation advances to an ayah on the NEXT page, turn the
  /// page forward — exactly like a reader following along in a printed
  /// Mushaf. (If the user started audio somewhere else entirely, the
  /// page is not yanked away.)
  void _followRecitation() {
    if (!mounted) return;
    final audio = _audioService;
    if (audio == null || !audio.hasActiveTrack) return;
    final g = audio.currentGlobalAyah;
    if (g == null || g == _lastFollowedAyah) return;
    _lastFollowedAyah = g;

    QuranService.pageOfGlobalAyah(g).then((p) {
      if (!mounted) return;
      final visibleEnd = _wide ? _pageNum + 1 : _pageNum;
      if (p == visibleEnd + 1) _loadPage(p);
    });
  }

  /// Loads all bookmarks and highlights so the matching ayah regions
  /// can be tinted on the page (same colors as the reader).
  Future<void> _loadMarks() async {
    final results = await Future.wait([
      BookmarkService.getAllBookmarks(),
      HighlightService.getAllHighlights(),
    ]);
    if (!mounted) return;
    setState(() {
      _bookmarks = results[0] as List<Bookmark>;
      _highlights = results[1] as List<Highlight>;
    });
  }

  Bookmark? _bookmarkFor(AyahHitRegion r) =>
      _bookmarks.cast<Bookmark?>().firstWhere(
          (b) =>
              b!.surahNumber == r.surahNumber && b.ayahNumber == r.ayahNumber,
          orElse: () => null);

  Highlight? _highlightFor(AyahHitRegion r) =>
      _highlights.cast<Highlight?>().firstWhere(
          (h) =>
              h!.surahNumber == r.surahNumber && h.ayahNumber == r.ayahNumber,
          orElse: () => null);

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // build() recreates the PageController when wide-mode flips.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  int _spreadBase(int page) => page.isOdd ? page : page - 1;

  /// Two-page spread only on a large screen in LANDSCAPE (tablet or
  /// desktop). A big iPad held in portrait keeps a single page: two
  /// side-by-side pages there use barely half the screen height, since
  /// each column is a tall narrow strip fitted by its width. A PHONE
  /// rotated to landscape is also still a single page, zoomed to full
  /// width and vertically scrollable (see _buildPageArtwork).
  bool _isWideScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height && size.shortestSide >= 600;
  }

  /// Landscape on a small screen: the page would shrink to an
  /// unreadable size if fitted by height, so render it full-width and
  /// let the user scroll vertically instead.
  bool _isLandscapeCompact(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height && !_isWideScreen(context);
  }

  /// Jumps straight to [page] (menu pickers, recitation follow). The
  /// PageView's onPageChanged then runs the usual bookkeeping.
  void _loadPage(int page) {
    final ctrl = _pageCtrl;
    if (ctrl != null && ctrl.hasClients) {
      ctrl.jumpToPage(_indexForPage(page));
    } else {
      _onPageSettled(_wide ? _spreadBase(page) : page);
    }
  }

  void _next() {
    final ctrl = _pageCtrl;
    if (ctrl != null && ctrl.hasClients) {
      ctrl.nextPage(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    }
  }

  void _prev() {
    final ctrl = _pageCtrl;
    if (ctrl != null && ctrl.hasClients) {
      ctrl.previousPage(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    }
  }

  String _ar(int n) {
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

  /// Converts Arabic-Indic (٠-٩) and extended (۰-۹) digits to Western
  /// digits so typed page numbers parse regardless of keyboard layout.
  static String _westernDigits(String s) => s
      .replaceAllMapped(RegExp('[٠-٩]'),
          (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x0660 + 0x30))
      .replaceAllMapped(RegExp('[۰-۹]'),
          (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x06F0 + 0x30));

  void _jumpDialog() {
    final ctrl = TextEditingController();
    final isDark = context.read<SettingsService>().isDarkIn(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('الانتقال إلى صفحة',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? AppColors.darkText : AppColors.textPrimary)),
        content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofocus: true,
            // digitsOnly rejects Arabic-Indic digits, which is what an
            // Arabic iOS keyboard types — accept both digit families.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
            ],
            style: TextStyle(
                fontSize: 20,
                fontFamily: '.SF Pro Text',
                color: isDark ? AppColors.darkText : AppColors.textPrimary),
            decoration: InputDecoration(
                hintText: '١ — ٦٠٤',
                hintStyle:
                    TextStyle(color: Colors.grey[400], fontFamily: '.SF Pro Text'),
                filled: true,
                fillColor: isDark ? AppColors.darkSurfaceAlt : Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 14))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                final p = int.tryParse(_westernDigits(ctrl.text));
                if (p != null && p >= 1 && p <= 604) {
                  Navigator.pop(context);
                  _loadPage(p);
                }
              },
              child: const Text('انتقال',
                  style:
                      TextStyle(color: Colors.white, fontFamily: '.SF Pro Text'))),
        ],
      ),
    );
  }

  /// The AppBar menu: quick navigation to a surah, juz, or page.
  void _showMenuSheet() {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;
    final iconColor = isDark ? AppColors.darkPrimary : AppColors.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 6),
              ListTile(
                  leading: Icon(Icons.menu_book_rounded, color: iconColor),
                  title: Text('الانتقال إلى سورة',
                      textDirection: TextDirection.rtl,
                      style:
                          TextStyle(fontFamily: '.SF Pro Text', color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _showSurahPicker();
                  }),
              ListTile(
                  leading:
                      Icon(Icons.auto_awesome_mosaic_rounded, color: iconColor),
                  title: Text('الانتقال إلى جزء',
                      textDirection: TextDirection.rtl,
                      style:
                          TextStyle(fontFamily: '.SF Pro Text', color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _showJuzPicker();
                  }),
              ListTile(
                  leading: Icon(Icons.tag_rounded, color: iconColor),
                  title: Text('الانتقال إلى صفحة',
                      textDirection: TextDirection.rtl,
                      style:
                          TextStyle(fontFamily: '.SF Pro Text', color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _jumpDialog();
                  }),
              // Only the reflowing text edition can be coloured — the
              // other editions are page artwork.
              if (MushafSvgService.edition.isText)
                Builder(builder: (_) {
                  final s = context.watch<SettingsService>();
                  return SwitchListTile(
                    value: s.tajweed,
                    activeThumbColor: AppColors.gold,
                    secondary: Icon(Icons.palette_rounded, color: iconColor),
                    title: Text(L10n.of(context)('tajweedLbl'),
                        style:
                            TextStyle(fontFamily: '.SF Pro Text', color: textColor)),
                    subtitle: Text(
                        L10n.of(context)(
                            s.tajweed ? 'tajweedOn' : 'tajweedOff'),
                        style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSec
                                : AppColors.textSecondary)),
                    onChanged: (v) => s.setTajweed(v),
                  );
                }),
              if (MushafSvgService.supportsFullOfflineDownload)
                Builder(builder: (_) {
                  final prog = MushafSvgService.bulkProgress.value;
                  return ListTile(
                      leading: Icon(
                          _fullyDownloaded
                              ? Icons.offline_pin_rounded
                              : (prog != null
                                  ? Icons.downloading_rounded
                                  : Icons.download_rounded),
                          color: iconColor),
                      title: Text(
                          _fullyDownloaded
                              ? 'المصحف كامل محفوظ دون اتصال ✓'
                              : (prog != null
                                  ? 'جارٍ التنزيل (${_ar(prog.$1)}/${_ar(prog.$2)}) — اضغط للإيقاف'
                                  : 'تنزيل المصحف كاملاً دون اتصال'),
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                              fontFamily: '.SF Pro Text', color: textColor)),
                      onTap: () {
                        Navigator.pop(context);
                        if (_fullyDownloaded) return;
                        if (MushafSvgService.bulkRunning) {
                          MushafSvgService.cancelBulkDownload();
                        } else {
                          MushafSvgService.startBulkDownload();
                        }
                      });
                }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// A small book icon standing for each edition, so the dropdown reads
  /// at a glance instead of by name alone.
  IconData _editionIcon(String id) => switch (id) {
        'warsh' => Icons.import_contacts_rounded,
        'qalon' => Icons.collections_bookmark_rounded,
        'text' => Icons.format_size_rounded,
        _ => Icons.menu_book_rounded,
      };

  /// Header control for the Mushaf edition (riwayah): the current
  /// edition's icon with a caret, opening a dropdown anchored under it.
  Widget _buildEditionButton(bool isDark, Color textColor) {
    final l = L10n.of(context);
    final current = MushafSvgService.edition;
    final accent = isDark ? AppColors.darkPrimary : AppColors.primary;

    return PopupMenuButton<String>(
      tooltip: l('mushafEdition'),
      position: PopupMenuPosition.under,
      color: isDark ? AppColors.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: AppColors.mushafBorderGold.withValues(alpha: 0.45))),
      onSelected: _applyEdition,
      itemBuilder: (_) => [
        for (final e in MushafSvgService.editions)
          PopupMenuItem<String>(
            value: e.id,
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: (e.id == current.id ? AppColors.gold : accent)
                        .withValues(alpha: e.id == current.id ? 0.22 : 0.10),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(_editionIcon(e.id),
                    size: 19,
                    color: e.id == current.id ? AppColors.gold : accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l.isArabic ? e.nameAr : e.nameEn,
                    style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 16,
                        fontWeight: e.id == current.id
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.textPrimary)),
              ),
              if (e.id == current.id)
                const Icon(Icons.check_rounded,
                    size: 18, color: AppColors.gold),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.mushafBorderGold.withValues(alpha: 0.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_editionIcon(current.id), size: 18, color: textColor),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: textColor),
        ]),
      ),
    );
  }

  /// Loads the current edition's surah-name bands if they aren't in yet.
  /// Called from build as well as from the switch, so the frames appear
  /// however the edition came to change.
  void _loadHeaderBands() {
    final id = MushafSvgService.edition.id;
    if (SurahHeaderService.isLoaded(id)) return;
    SurahHeaderService.load(id).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Switches the Mushaf edition: persists the choice, drops the loaded
  /// pages so the new edition builds its own, and refits the page.
  Future<void> _applyEdition(String id) async {
    if (id == MushafSvgService.edition.id) return;
    await context.read<SettingsService>().setMushafEdition(id);
    if (!mounted) return;
    _loadHeaderBands();
    setState(() {
      _pageFutures.clear();
      _textFutures.clear();
      _fitCache.clear();
      _zoom = 1.0;
    });
    _onPageSettled(_pageNum);
  }

  void _showSurahPicker() {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: QuranPageMeta.surahNames.length,
          itemBuilder: (ctx, i) => ListTile(
            dense: true,
            onTap: () {
              Navigator.pop(ctx);
              _loadPage(QuranPageMeta.surahStartPages[i]);
            },
            trailing: Text('${_ar(i + 1)}.',
                style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 14,
                    color: isDark
                        ? AppColors.darkTextSec
                        : AppColors.textSecondary)),
            title: Text(QuranPageMeta.surahNames[i],
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontFamily: 'QuranHafs', fontSize: 16, color: textColor)),
            leading: Text('ص ${_ar(QuranPageMeta.surahStartPages[i])}',
                style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSec
                        : AppColors.textSecondary)),
          ),
        ),
      ),
    );
  }

  void _showJuzPicker() {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final gold = isDark ? AppColors.darkSecondary : AppColors.accent;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6, mainAxisSpacing: 10, crossAxisSpacing: 10),
            itemCount: 30,
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _loadPage(QuranPageMeta.juzStartPages[i]);
              },
              child: Container(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: gold.withValues(alpha: 0.5))),
                child: Center(
                    child: Text(_ar(i + 1),
                        style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontWeight: FontWeight.bold,
                            color: gold))),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAyahOptions(AyahHitRegion region) {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final l = L10n.of(context);
    final bookmark = _bookmarkFor(region);
    final existingHighlight = _highlightFor(region);
    final audio = context.read<QuranAudioService>();
    final globalAyah =
        QuranPageMeta.globalAyahNumber(region.surahNumber, region.ayahNumber);
    final playingThis =
        audio.currentGlobalAyah == globalAyah && audio.isPlaying;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      // Scrollable so the sheet never overflows on short (landscape)
      // screens — the content is taller than the sheet's max height there.
      builder: (_) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2)))),
              Text(
                  '${_surahName(region.surahNumber)} — آية ${_ar(region.ayahNumber)}',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'QuranHafs',
                      color:
                          isDark ? AppColors.darkText : AppColors.textPrimary)),
              const Divider(height: 24),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      playingThis
                          ? Icons.pause_circle_rounded
                          : Icons.play_circle_rounded,
                      color:
                          isDark ? AppColors.darkPrimary : AppColors.primary),
                  title: Text(
                      playingThis ? l('pauseRecitation') : l('playRecitation'),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary)),
                  onTap: () async {
                    Navigator.pop(context);
                    // First-ever playback: pick a reciter once; the
                    // choice then sticks until changed on purpose.
                    if (!mounted) return;
                    final ok =
                        await ensureReciterChosen(context, audio, isDark);
                    if (!ok) return;
                    await audio.togglePlayPause(globalAyah);
                    // Playback failures only set audio.error — surface it.
                    if (mounted && audio.error != null) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(audio.error!)));
                    }
                  }),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.menu_book_rounded,
                      color:
                          isDark ? AppColors.darkPrimary : AppColors.primary),
                  title: Text(l('tafsir'),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TafsirScreen(
                                  surahNumber: region.surahNumber,
                                  surahName: _surahName(region.surahNumber),
                                  ayahNumber: region.ayahNumber,
                                )));
                  }),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      bookmark != null
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_add_rounded,
                      color: bookmark != null
                          ? AppColors.highlight(bookmark.color)
                          : (isDark
                              ? AppColors.darkPrimary
                              : AppColors.primary)),
                  title: Text(l('bookmark'),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    _showBookmarkPicker(region);
                  }),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.highlight_rounded,
                      color: AppColors.secondary),
                  title: Text(l('highlightAyah'),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    _showHighlightPicker(region);
                  }),
              // Note on this ayah — lives on the colour mark, so writing
              // one on an unmarked ayah marks it too.
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      existingHighlight?.hasNote == true
                          ? Icons.sticky_note_2_rounded
                          : Icons.note_add_outlined,
                      color: AppColors.secondary),
                  title: Text(
                      existingHighlight?.hasNote == true
                          ? l('editNote')
                          : l('addNote'),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary)),
                  subtitle: existingHighlight?.hasNote == true
                      ? Text(existingHighlight!.note!,
                          textDirection: TextDirection.rtl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: '.SF Pro Text',
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkTextSec
                                  : AppColors.textSecondary))
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _editNote(region);
                  }),
            ],
          ),
        ),
      ),
    );
  }

  /// Ribbon-marker picker — one bookmark per color app-wide (choosing
  /// a color moves that ribbon here); the block dot removes this
  /// ayah's bookmark.
  void _showBookmarkPicker(AyahHitRegion region) {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final existing = _bookmarkFor(region);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('اختر لون الفاصل',
                style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontWeight: FontWeight.bold,
                    color:
                        isDark ? AppColors.darkText : AppColors.textPrimary)),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (existing != null)
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await BookmarkService.deleteBookmarkByAyah(
                            region.surahNumber, region.ayahNumber);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم إزالة الفاصل')));
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4)
                            ]),
                        child: const Icon(Icons.block,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ...AppColors.highlights.entries.map((e) => GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          await BookmarkService.addBookmark(Bookmark(
                            surahNumber: region.surahNumber,
                            ayahNumber: region.ayahNumber,
                            surahName: _surahName(region.surahNumber),
                            color: e.key,
                            createdAt: DateTime.now(),
                            // Remember this was made in the Mushaf, so
                            // opening it later returns to the page.
                            page: _pageNum,
                          ));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('✓ تم حفظ الفاصل')));
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: e.value,
                              shape: BoxShape.circle,
                              border: existing?.color == e.key
                                  ? Border.all(
                                      color: AppColors.primary, width: 3)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 4)
                              ]),
                          child: const Icon(Icons.bookmark_rounded,
                              color: Colors.white, size: 18),
                        ),
                      )),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Opens the note editor for an ayah on the page. Marks reload through
  /// LibraryEvents, so the note dot on the page appears right away.
  Future<void> _editNote(AyahHitRegion region) async {
    final l = L10n.of(context);
    final saved = await showAyahNoteSheet(
      context,
      surahNumber: region.surahNumber,
      ayahNumber: region.ayahNumber,
      surahName: _surahName(region.surahNumber),
      // Remember this was written in the Mushaf, so opening it from the
      // Highlights tab returns to the page.
      page: _pageNum,
    );
    if (!saved || !mounted) return;
    await _loadMarks();
    if (!mounted) return;
    final nowHas = _highlightFor(region)?.hasNote ?? false;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nowHas ? l('noteSaved') : l('noteRemoved'))));
  }

  void _showHighlightPicker(AyahHitRegion region) {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final existing = _highlightFor(region);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (existing != null)
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    await HighlightService.deleteHighlight(
                        region.surahNumber, region.ayahNumber);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم إزالة التمييز')));
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4)
                        ]),
                    child:
                        const Icon(Icons.block, color: Colors.white, size: 20),
                  ),
                ),
              ...AppColors.highlights.entries.map((e) => GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      await HighlightService.addHighlight(Highlight(
                        surahNumber: region.surahNumber,
                        ayahNumber: region.ayahNumber,
                        surahName: _surahName(region.surahNumber),
                        color: e.key,
                        createdAt: DateTime.now(),
                        // Remember this was made in the Mushaf, so
                        // opening it later returns to the page.
                        page: _pageNum,
                      ));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('✓ تم التمييز')));
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: e.value,
                          shape: BoxShape.circle,
                          border: existing?.color == e.key
                              ? Border.all(color: AppColors.primary, width: 3)
                              : null,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4)
                          ]),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final audio = context.watch<QuranAudioService>();
    final isDark = s.isDarkIn(context);
    // The edition can change from anywhere; make sure its frames are on
    // their way whenever this screen rebuilds.
    _loadHeaderBands();
    // ONE background colour for the whole Mushaf, whatever the edition:
    // the pages sit straight on it with no card, no border and no
    // rounded corners, so a future setting can repaint every edition at
    // once by changing this single value.
    final bgColor = AppColors.mushafBackground(s.mushafBackground, isDark);
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;

    // (Re)create the controller when wide-mode flips — index math
    // differs between single pages and 2-page spreads.
    final wide = _isWideScreen(context);
    if (_pageCtrl == null || wide != _wide) {
      _wide = wide;
      // Disposing a controller a PageView is still attached to is an
      // error, and this runs mid-build — let the old one go once the
      // frame that replaces it has been laid out.
      final previous = _pageCtrl;
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
      _pageCtrl = PageController(initialPage: _indexForPage(_pageNum));
      _pageFutures.clear();
    }

    // The Mushaf keeps its original fixed layout and page-turn
    // direction regardless of the app's UI language — it is Quran
    // reading, not app chrome.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Stack(children: [
          // ── The pages: ALWAYS full-bleed. The bars float on top and
          // never resize the page, so toggling them causes no zoom jump.
          // PageView gives real finger-following page turns; reverse =
          // RTL book order (swipe right, like flipping a printed page,
          // advances).
          Positioned.fill(
            child: PageView.builder(
              // Keyed on the layout mode so a rotation builds a FRESH
              // page view instead of reusing the old one's scroll
              // position, which belongs to a different index space.
              key: ValueKey(wide),
              controller: _pageCtrl,
              reverse: true,
              // A zoomed page IMAGE has to be panned, so a drag there
              // must not flip the page. The reflowing text reflows to
              // the width instead of overflowing it, so it keeps its
              // page turns at every zoom level.
              physics: _isZoomed && !MushafSvgService.edition.isText
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: _pageCount,
              onPageChanged: (i) {
                // An index only means a page WITHIN the layout mode it
                // was reported for. Rotating an iPad flips single pages
                // to 2-page spreads, and a stale index arriving after
                // the flip used to be read with the new mapping — page
                // 30 became page 59, and a second flip 119, which is
                // how a rotation could land the reader anywhere.
                if (wide != _wide) return;
                _setBars(false);
                // The zoom level deliberately CARRIES to the next page:
                // a reader who enlarged the type wants it enlarged for
                // the rest of the reading, not reset every turn.
                _onPageSettled(_pageForIndex(i));
              },
              itemBuilder: (ctx, i) => _buildPageItem(i, isDark),
            ),
          ),
          // ── Top bar overlay (slides away in immersive reading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: _barsVisible ? Offset.zero : const Offset(0, -1.1),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: _buildTopBar(isDark, bgColor, textColor),
            ),
          ),
          // ── Bottom overlay: audio controls + page navigation
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: _barsVisible ? Offset.zero : const Offset(0, 1.1),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (audio.hasActiveTrack) _buildAudioBar(audio, isDark),
                // The page-number bar and its two arrows are redundant
                // once the leaf prints its own number: the number is on
                // the page, and turning pages is a swipe. Tapping the
                // printed number opens the same go-to dialog the old
                // circle did.
                if (!_usesPageFurniture) _buildNavBar(isDark),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// One PageView item: a single page, or a 2-page spread on wide
  /// screens. Loads through a cached future so rebuilds don't refetch.
  Widget _buildPageItem(int index, bool isDark) {
    final base = _pageForIndex(index);

    // The reflowing text edition is typeset from the bundled text —
    // no artwork to fetch, and no illuminated-frame special case.
    if (MushafSvgService.edition.isText) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setBars(!_barsVisible),
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: SafeArea(
          child: !_wide || base + 1 > 604
              ? _buildTextPage(base, isDark)
              : Row(children: [
                  Expanded(child: _buildTextPage(base + 1, isDark)),
                  Expanded(child: _buildTextPage(base, isDark)),
                ]),
        ),
      );
    }

    final edition = MushafSvgService.edition.id;
    var entry = _pageFutures[index];
    if (entry == null || entry.$1 != edition) {
      entry = (
        edition,
        () async {
          final first = await MushafSvgService.getPage(base);
          if (!_wide || base + 1 > 604) return [first];
          try {
            return [first, await MushafSvgService.getPage(base + 1)];
          } catch (_) {
            return [first];
          }
        }()
      );
      _pageFutures[index] = entry;
    }
    final future = entry.$2;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setBars(!_barsVisible),
      child: FutureBuilder<List<MushafPageData>>(
        future: future,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text('تعذّر تحميل صفحة ${_ar(base)}\nتحقق من اتصالك',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          color: isDark
                              ? AppColors.darkTextSec
                              : AppColors.textSecondary,
                          height: 1.6)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      onPressed: () =>
                          setState(() => _pageFutures.remove(index)),
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white),
                      label: const Text('إعادة المحاولة',
                          style: TextStyle(
                              color: Colors.white, fontFamily: '.SF Pro Text'))),
                ]));
          }
          if (!snap.hasData) {
            return Center(
                child: CircularProgressIndicator(
                    color: isDark ? AppColors.darkPrimary : AppColors.primary));
          }
          final pages = snap.data!;
          final content = pages.length == 1
              ? _buildSinglePage(pages[0], isDark)
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    Expanded(child: _buildSinglePage(pages[1], isDark)),
                    // Book spine divider
                    Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.15),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: _buildSinglePage(pages[0], isDark)),
                  ]),
                );
          return SafeArea(child: content);
        },
      ),
    );
  }

  /// Floating top bar: back / page number / menu plus the juz-hizb and
  /// surah info strip — all overlaying the page, never resizing it.
  Widget _buildTopBar(bool isDark, Color bgColor, Color textColor) {
    const gold = AppColors.mushafBorderGold;
    final headerText = isDark ? AppColors.darkPrimary : AppColors.primary;
    final subText = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final juz = QuranPageMeta.juzForPage(_pageNum);
    final hizb = QuranPageMeta.hizbForPage(_pageNum);
    final surahLabel = QuranPageMeta.headerLabelForPage(_pageNum);

    return Container(
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.97),
        border: Border(bottom: BorderSide(color: gold.withValues(alpha: 0.5))),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            IconButton(
                icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child: Icon(Icons.arrow_back_ios_rounded,
                        size: 16, color: textColor)),
                onPressed: () => Navigator.pop(context)),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                      _wide && _pageNum + 1 <= 604
                          ? 'صفحة ${_ar(_pageNum)} — ${_ar(_pageNum + 1)}'
                          : 'صفحة ${_ar(_pageNum)}',
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: textColor)),
                  if (_isCachedOffline) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.offline_pin_rounded,
                        size: 16,
                        color: AppColors.primary.withValues(alpha: 0.6)),
                  ],
                ],
              ),
            ),
            _buildEditionButton(isDark, textColor),
            IconButton(
                icon: Icon(Icons.menu_rounded, color: textColor),
                onPressed: _showMenuSheet),
          ]),
          // Where the reader is, for editions whose pages don't yet
          // carry their own running head.
          if (!_usesPageFurniture)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Directionality(
                textDirection: TextDirection.rtl,
                // A long surah label next to the juz/hizb text can be
                // wider than a narrow phone — shrink the strip to fit
                // rather than clipping it.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(surahLabel,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: 'QuranHafs',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: headerText,
                                height: 1.25)),
                      ),
                      const SizedBox(width: 14),
                      Container(
                          width: 1,
                          height: 18,
                          color: gold.withValues(alpha: 0.45)),
                      const SizedBox(width: 14),
                      Text('الجزء ${_ar(juz)} • الحزب ${_ar(hizb)}',
                          style: TextStyle(
                              fontFamily: '.SF Pro Text',
                              fontSize: 12,
                              color: subText)),
                    ],
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  /// The reader's chosen page colour, for frames that must sit ON the
  /// page rather than look pasted onto it.
  Color _pageColor(bool isDark) => AppColors.mushafBackground(
      context.read<SettingsService>().mushafBackground, isDark);

  Widget _buildSinglePage(MushafPageData data, bool isDark) {
    // Pages 1-2 get the illuminated opening frame
    if (data.pageNumber <= 2) {
      return _buildIlluminatedPage(data, isDark);
    }
    final artwork = Padding(
      padding: const EdgeInsets.all(2),
      child: _buildPageArtwork(data, isDark),
    );
    return _withPageFurniture(data.pageNumber, isDark, artwork);
  }

  /// Wraps a page in the furniture a printed Mushaf carries: the running
  /// head above and the page number below.
  ///
  /// Both stay put when the floating bars slide away — they belong to
  /// the leaf, not to the app. Editions still on the old chrome get the
  /// page back untouched, with that information in the bars instead.
  Widget _withPageFurniture(int page, bool isDark, Widget page0) {
    if (!_usesPageFurniture) return page0;
    return Column(children: [
      MushafPageHeader(page: page, isDark: isDark),
      Expanded(child: page0),
      MushafPageFooter(
        page: page,
        isDark: isDark,
        pageColor: _pageColor(isDark),
        onTap: _jumpDialog,
      ),
    ]);
  }

  /// Illuminated frame for the opening spread (pages 1-2 only).
  Widget _buildIlluminatedPage(MushafPageData data, bool isDark) {
    final emerald = isDark ? AppColors.primaryContainer : AppColors.primary;
    const gold = AppColors.secondaryContainer;
    final cream = isDark ? AppColors.darkSurfaceAlt : AppColors.mushafParchment;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: emerald,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: emerald.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5)),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: gold, width: 1.4)),
          padding: const EdgeInsets.all(4),
          child: Container(
            decoration: BoxDecoration(
                color: cream,
                borderRadius: BorderRadius.circular(9),
                border:
                    Border.all(color: gold.withValues(alpha: 0.55), width: 1)),
            child: Column(children: [
              const SizedBox(height: 10),
              // Surah name cartouche — plain text
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 6),
                decoration: BoxDecoration(
                    color: emerald,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: gold, width: 1.2)),
                child: Text(QuranPageMeta.headerLabelForPage(data.pageNumber),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: gold)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _buildPageArtwork(data, isDark),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// The reflowing text edition of page [page].
  ///
  /// The printed editions are page IMAGES: zooming can only make the
  /// sheet bigger, so past a point the reader is panning around a page
  /// wider than the screen. Here the same ayahs are typeset live, so
  /// zoom changes the TYPE size and the lines re-wrap to whatever the
  /// screen is — the text is always fully within the screen width, at
  /// any zoom and in any orientation.
  Widget _buildTextPage(int page, bool isDark) {
    final future = _textFutures[page] ??= QuranService.ayahsOnPage(page);
    final ink = isDark ? AppColors.darkText : AppColors.textPrimary;

    return LayoutBuilder(builder: (context, constraints) {
      return FutureBuilder<List<PageAyah>>(
        future: future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return Center(
                child: CircularProgressIndicator(
                    color: isDark ? AppColors.darkPrimary : AppColors.primary));
          }
          final ayahs = snap.data!;

          // Split the page into runs of consecutive ayahs from the same
          // surah; a page can start mid-surah and finish inside the next.
          final blocks = <List<PageAyah>>[];
          for (final a in ayahs) {
            if (blocks.isEmpty ||
                blocks.last.first.surahNumber != a.surahNumber) {
              blocks.add([a]);
            } else {
              blocks.last.add(a);
            }
          }

          // The type size IS the zoom, and its baseline is the size at
          // which THIS page's text fills the box it is typeset into.
          // That is measured, not estimated: the text is laid out at
          // trial sizes until the largest one that still fits is found.
          // Guessing from a character count was never going to be right
          // for every page — pages hold anywhere from 7 to 25 lines.
          final base = _fitFontSize(page, blocks, constraints);
          final fontSize = base * _zoom;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            physics: const ClampingScrollPhysics(),
            // No card of its own: the page draws straight onto the
            // chosen Mushaf background, like every other edition. It
            // still claims the full height so a short page reads as a
            // page rather than a floating block of text.
            child: Container(
              width: double.infinity,
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 32),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in blocks) ...[
                    // A surah that BEGINS on this page gets its name band
                    // and the Basmala, as the printed page does.
                    if (block.first.numberInSurah == 1) ...[
                      _textSurahHeader(
                          block.first.surahNumber, isDark, fontSize),
                      if (block.first.surahNumber != 1 &&
                          block.first.surahNumber != 9)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(QuranService.basmala,
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                  fontFamily: 'QuranHafs',
                                  fontSize: fontSize * 0.92,
                                  height: 1.9,
                                  color: isDark
                                      ? AppColors.darkPrimary
                                      : AppColors.primary)),
                        ),
                    ],
                    Text.rich(
                      TextSpan(children: [
                        for (final a in block)
                          ..._ayahSpans(a, isDark, fontSize),
                      ]),
                      // Justified edge to edge, like the printed page.
                      textAlign: TextAlign.justify,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontFamily: 'QuranHafs',
                          fontSize: fontSize,
                          height: 2.0,
                          color: ink),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          );
        },
      );
    });
  }

  /// The page artwork with its ayah medallions tinted.
  ///
  /// The artwork draws every ayah-end medallion in one group, so giving
  /// that group a fill colours them all and leaves the script black —
  /// the same distinction a printed Mushaf makes. Memoised: the source
  /// is around 600 KB and the PageView rebuilds constantly.
  String _tintedSvg(MushafPageData data) {
    final hit = _tintedCache[data];
    if (hit != null) return hit;

    const gold = '#B8892B';
    const ink = 'fill="#231f20"';
    final svg = data.svgContent;
    var out = svg;

    // Each medallion path sets its own fill, so a fill on the group
    // would be overridden — the colour has to be swapped path by path,
    // and only inside the marker group. The page's script is one more
    // path with the same fill just outside it.
    const open = '<g id="ayah_markers"';
    final start = svg.indexOf(open);
    if (start >= 0) {
      var depth = 0, end = -1;
      for (var i = start; i < svg.length; i++) {
        if (svg.startsWith('<g', i)) {
          depth++;
        } else if (svg.startsWith('</g>', i)) {
          depth--;
          if (depth == 0) {
            end = i + 4;
            break;
          }
        }
      }
      if (end > start) {
        out = svg.substring(0, start) +
            svg.substring(start, end).replaceAll(ink, 'fill="$gold"') +
            svg.substring(end);
      }
    }

    _tintedCache[data] = out;
    return out;
  }

  /// Largest type size at which [blocks] still fit [constraints], found
  /// by binary search over an actual text layout.
  ///
  /// Cached per page and box: the search costs a dozen layouts, and a
  /// PageView rebuilds its children constantly while swiping.
  double _fitFontSize(
      int page, List<List<PageAyah>> blocks, BoxConstraints constraints) {
    final key = '$page:${constraints.maxWidth.round()}'
        'x${constraints.maxHeight.round()}';
    final cached = _fitCache[key];
    if (cached != null) return cached;

    // The page's own furniture: card padding, and per surah opening a
    // name frame and a Basmala line.
    const cardPadding = 32.0 + 16.0;
    final openings = blocks.where((b) => b.first.numberInSurah == 1).length;
    final width = constraints.maxWidth - 28 - 28;
    final height = constraints.maxHeight - cardPadding - 32;

    double textHeight(double size) {
      var total = openings * size * 3.4; // frame + Basmala line
      for (final block in blocks) {
        final painter = TextPainter(
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.justify,
          text: TextSpan(
            style:
                TextStyle(fontFamily: 'QuranHafs', fontSize: size, height: 2.0),
            children: [
              for (final a in block)
                TextSpan(text: '${a.text} ${_ar(a.numberInSurah)} '),
            ],
          ),
        )..layout(maxWidth: width);
        total += painter.height + 6;
      }
      return total;
    }

    var lo = 16.0, hi = 64.0;
    for (var i = 0; i < 12; i++) {
      final mid = (lo + hi) / 2;
      if (textHeight(mid) <= height) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    _fitCache[key] = lo;
    if (_fitCache.length > 24) _fitCache.remove(_fitCache.keys.first);
    return lo;
  }

  /// Name band for a surah starting on a reflowing text page — the same
  /// ornamental cartouche the reader uses, not a plain box.
  Widget _textSurahHeader(int surah, bool isDark, double fontSize) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        // The bare name ([_surahName]) carries no tashkeel — it is meant
        // for a compact navigation label, not a title band read as
        // calligraphy — so the band is set from the voweled name
        // instead, already prefixed with "سُورَةُ".
        child: SurahFrame(
          title: QuranPageMeta.voweledSurahName(surah),
          isDark: isDark,
          fontSize: fontSize * 0.9,
          pageColor: _pageColor(isDark),
        ),
      );

  /// One ayah's text plus its end-of-ayah marker, tinted for the mark
  /// it carries (bookmark/highlight) or for being recited right now,
  /// and long-pressable for the same options sheet as the page view.
  List<InlineSpan> _ayahSpans(PageAyah a, bool isDark, double fontSize) {
    final region = AyahHitRegion(
        surahNumber: a.surahNumber,
        ayahNumber: a.numberInSurah,
        x: 0,
        y: 0,
        rings: const []);
    final bookmark = _bookmarkFor(region);
    final highlight = _highlightFor(region);
    final playing = _playingGlobalAyah != null &&
        _regionGlobal(region) == _playingGlobalAyah;

    Color? bg;
    if (playing) {
      bg = (isDark ? AppColors.darkSecondary : AppColors.secondary)
          .withValues(alpha: isDark ? 0.30 : 0.16);
    } else if (bookmark != null) {
      bg = AppColors.highlight(bookmark.color)
          .withValues(alpha: isDark ? 0.32 : 0.22);
    } else if (highlight != null) {
      bg = AppColors.highlight(highlight.color)
          .withValues(alpha: isDark ? 0.35 : 0.25);
    }

    final recognizer = _textRecognizers.putIfAbsent(
        _regionGlobal(region), () => LongPressGestureRecognizer())
      ..onLongPress = () => _showAyahOptions(region);

    // Colour by tajweed rule when the setting is on, exactly as the
    // reader does; a plain single span otherwise.
    final tajweed = context.read<SettingsService>().tajweed;
    final segs = tajweed
        ? TajweedService.segments(a.surahNumber, a.numberInSurah)
        : null;

    return [
      if (segs == null)
        TextSpan(
            text: a.text,
            recognizer: recognizer,
            style: TextStyle(backgroundColor: bg))
      else
        for (final seg in segs)
          TextSpan(
              text: seg.text,
              recognizer: recognizer,
              style: TextStyle(
                  backgroundColor: bg,
                  color:
                      seg.isPlain ? null : TajweedService.colorFor(seg.rule))),
      // End-of-ayah mark: bare Arabic-Indic digits. The KFGQPC HAFS
      // font itself sets them inside the ornate medallion — that is its
      // own convention — and unlike a drawn WidgetSpan (directionally
      // neutral, so it drifts out of reading order in an RTL paragraph)
      // real digits take part in the bidi algorithm and always land
      // beside their own ayah.
      // Tinted, so the medallions read as marks between ayahs rather
      // than as part of the script — as a printed Mushaf prints them.
      TextSpan(
          text: ' ${_ar(a.numberInSurah)} ',
          recognizer: recognizer,
          style: TextStyle(
              backgroundColor: bg,
              color:
                  isDark ? AppColors.darkSecondary : const Color(0xFFB8892B))),
    ];
  }

  Widget _buildPageArtwork(MushafPageData data, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = data.viewBoxWidth / data.viewBoxHeight;
        final scrollZoom = _isLandscapeCompact(context);
        double renderWidth = constraints.maxWidth;
        double renderHeight = renderWidth / aspectRatio;
        if (!scrollZoom && renderHeight > constraints.maxHeight) {
          renderHeight = constraints.maxHeight;
          renderWidth = renderHeight * aspectRatio;
        }
        // Responsive zoom: the page grows in place, keeping its full
        // width on screen, and the extra height is scrolled through.
        if (_zoom > 1.0) {
          renderWidth = constraints.maxWidth * _zoom;
          renderHeight = renderWidth / aspectRatio;
        }

        final scaleX = renderWidth / data.viewBoxWidth;
        final scaleY = renderHeight / data.viewBoxHeight;

        // The page is drawn EXACTLY as it was printed — no attempt to
        // re-space its lines.
        //
        // Opening up the line spacing was tried twice and both attempts
        // damaged the page. Cutting it into strips clipped every letter
        // that reached into a neighbouring line, and stretching only the
        // ink-free rows left the spacing lumpy (many lines' ink touches,
        // so there is nowhere to add space between them) and forced the
        // page through a raster, which cost sharpness and made switching
        // edition flash stale artwork. A printed leaf is one fixed
        // image: the honest thing is to show it as it is, and let the
        // reader pinch when they want it bigger.
        final page = Center(
          child: SizedBox(
            width: renderWidth,
            height: renderHeight,
            child: Stack(children: [
              // Ornamental surah-name frames — painted BEHIND the page
              // artwork so the surah names the SVG already draws land
              // inside the band, like a printed Mushaf.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: SurahBannerPainter(
                      bands: SurahHeaderService.forPage(data.pageNumber,
                          edition: MushafSvgService.edition.id),
                      scaleX: scaleX,
                      scaleY: scaleY,
                      minX: data.viewBoxMinX,
                      minY: data.viewBoxMinY,
                      isDark: isDark,
                      pageColor: _pageColor(isDark),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: _artworkLayer(data, isDark)),
              // Tint marked ayahs using their exact polygon outlines (a
              // bounding-box tint would bleed onto neighbouring ayahs
              // for multi-line ayahs). Priority: currently-recited gold
              // tint, then bookmark, then highlight — same as the reader.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _AyahMarkPainter(
                      marks: _ayahMarks(data, isDark),
                      scaleX: scaleX,
                      scaleY: scaleY,
                      minX: data.viewBoxMinX,
                      minY: data.viewBoxMinY,
                    ),
                  ),
                ),
              ),
              // Gesture layer. Model (matching well-known Mushaf apps):
              // a FAST TAP anywhere — ayah or empty space — toggles
              // the header/footer; a LONG-PRESS on an ayah opens its
              // options (tafsir/bookmark/highlight/audio). This makes
              // recovering from full-screen a single tap, always.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setBars(!_barsVisible),
                  onLongPressStart: (details) {
                    final vx =
                        details.localPosition.dx / scaleX + data.viewBoxMinX;
                    final vy =
                        details.localPosition.dy / scaleY + data.viewBoxMinY;
                    for (final region in data.ayahRegions) {
                      if (region.ayahNumber > 0 &&
                          region.surahNumber > 0 &&
                          region.containsPoint(vx, vy)) {
                        // Visual + haptic confirmation of WHICH ayah
                        // the press landed on.
                        HapticFeedback.selectionClick();
                        setState(() => _flashRegion = region);
                        _flashCtrl.forward(from: 0);
                        _showAyahOptions(region);
                        return;
                      }
                    }
                  },
                ),
              ),
            ]),
          ),
        );

        // Pinch to zoom (two fingers), then drag to pan — like a
        // printed Mushaf held closer. Wrapping the whole page stack
        // keeps ayah hit-testing correct, because Flutter maps taps
        // back through the zoom transform before they reach the
        // gesture layer below.
        // Pinching sets how WIDE the page is drawn (width grows with the
        // zoom level), and the page is then read by scrolling. Scrolling
        // is bounded to the page, so unlike free 2-D panning the page can
        // never be flung off-screen or left half-visible.
        final scrollable = _isZoomed || scrollZoom;
        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          child: SingleChildScrollView(
            // vertical
            physics: scrollable
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            // A Mushaf page is proportionally WIDER than a phone screen,
            // so fitting its width always leaves vertical slack. Claim
            // the full viewport height and centre the page in it, or the
            // slack all piles up as dead space under the last line.
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: _isZoomed
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: renderWidth,
                    height: renderHeight,
                    child: page,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The page artwork itself, drawn straight from the SVG so it stays
  /// vector-sharp at every zoom level and on every screen density.
  ///
  /// Dark mode inverts the whole layer rather than recolouring the
  /// artwork: the pages are black ink on white, and inverting is the one
  /// transform that keeps the ayah medallions and the script in step.
  Widget _artworkLayer(MushafPageData data, bool isDark) {
    final artwork = SvgPicture.string(_tintedSvg(data), fit: BoxFit.contain);
    if (!isDark) return artwork;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -1,
        0, 0, 0, 255, //
        0, -1, 0, 0, 255, //
        0, 0, -1, 0, 255, //
        0, 0, 0, 1, 0, //
      ]),
      child: artwork,
    );
  }

  /// Which ayahs on [data] are tinted, and in what colour. Priority:
  /// the just-tapped flash, then the ayah being recited, then a
  /// bookmark, then a highlight — the same order the reader uses.
  /// The third field flags an ayah carrying a note, which the painter
  /// dots so the page shows at a glance where something was written.
  List<(AyahHitRegion, Color, bool)> _ayahMarks(
      MushafPageData data, bool isDark) {
    final lit = isDark ? AppColors.darkSecondary : AppColors.secondary;
    return [
      for (final r in data.ayahRegions)
        if (r.ayahNumber > 0 && r.surahNumber > 0)
          if (identical(r, _flashRegion))
            (r, lit.withValues(alpha: (1 - _flashCtrl.value) * 0.40), false)
          else if (_playingGlobalAyah != null &&
              _regionGlobal(r) == _playingGlobalAyah)
            (
              r,
              lit.withValues(alpha: isDark ? 0.30 : 0.16),
              _highlightFor(r)?.hasNote ?? false
            )
          else if (_bookmarkFor(r) != null)
            (
              r,
              AppColors.highlight(_bookmarkFor(r)!.color)
                  .withValues(alpha: isDark ? 0.32 : 0.22),
              _highlightFor(r)?.hasNote ?? false
            )
          else if (_highlightFor(r) != null)
            (
              r,
              AppColors.highlight(_highlightFor(r)!.color)
                  .withValues(alpha: isDark ? 0.35 : 0.25),
              _highlightFor(r)!.hasNote
            ),
    ];
  }

  /// Compact recitation controls shown while audio is active — without
  /// this the user would have to find and re-tap the currently playing
  /// ayah (which keeps moving with auto-advance) just to stop it.
  Widget _buildAudioBar(QuranAudioService audio, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          border: Border(
              top: BorderSide(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.06)))),
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
              size: 30,
            ),
            onPressed: () {
              if (audio.currentGlobalAyah != null) {
                audio.togglePlayPause(audio.currentGlobalAyah!);
              }
            },
          ),
          IconButton(
            tooltip: 'تغيير القارئ',
            icon: Icon(Icons.record_voice_over_rounded,
                color: isDark ? AppColors.darkTextSec : AppColors.textSecondary,
                size: 20),
            onPressed: () => showReciterPicker(context, audio, isDark),
          ),
          Expanded(
            child: Text(
              audio.isLoading
                  ? 'جارٍ التحميل...'
                  : (audio.isPlaying
                      ? (audio.isDownloadingSurah
                          ? 'قيد التلاوة — تنزيل السورة ${audio.downloadDone}/${audio.downloadTotal}'
                          : 'قيد التلاوة — ${audio.reciterName}')
                      : 'متوقف مؤقتاً'),
              textAlign: TextAlign.end,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontSize: 12,
                  fontFamily: '.SF Pro Text',
                  color:
                      isDark ? AppColors.darkTextSec : AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar(bool isDark) {
    // Kept deliberately slim — every vertical pixel here is stolen from
    // the page itself, which hurts most in phone landscape.
    final compact = _isLandscapeCompact(context);
    final gold = isDark ? AppColors.darkSecondary : AppColors.accent;
    final disabled = isDark ? AppColors.darkBorder : Colors.grey[300];
    final circleSize = compact ? 30.0 : 36.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 0 : 2),
      decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, -2))
          ]),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: _pageNum > 1 ? _prev : null,
                icon: Icon(Icons.chevron_right, size: compact ? 22 : 26),
                color: _pageNum > 1 ? gold : disabled),
            GestureDetector(
                onTap: _jumpDialog,
                child: Container(
                    width: circleSize,
                    height: circleSize,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: gold.withValues(alpha: 0.4), width: 1.2)),
                    child: Center(
                        child: Text(_ar(_pageNum),
                            style: TextStyle(
                                fontSize: compact ? 11 : 12,
                                fontWeight: FontWeight.bold,
                                color: gold,
                                fontFamily: '.SF Pro Text'))))),
            IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: _pageNum < 604 ? _next : null,
                icon: Icon(Icons.chevron_left, size: compact ? 22 : 26),
                color: _pageNum < 604 ? gold : disabled),
          ],
        ),
      ),
    );
  }
}

/// Fills each marked ayah's exact polygon outline (scaled from viewBox
/// to render coordinates) so the tint follows the ayah's actual text
/// flow across lines instead of a rectangular bounding box.
class _AyahMarkPainter extends CustomPainter {
  /// (region, tint, carries a note)
  final List<(AyahHitRegion, Color, bool)> marks;
  final double scaleX;
  final double scaleY;

  /// viewBox origin — polygons are in the page's coordinate space, which
  /// does not start at 0 0 for every edition.
  final double minX;
  final double minY;

  _AyahMarkPainter({
    required this.marks,
    required this.scaleX,
    required this.scaleY,
    this.minX = 0,
    this.minY = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final (region, color, hasNote) in marks) {
      final path = Path();
      for (final ring in region.rings) {
        if (ring.length < 6) continue;
        path.moveTo((ring[0] - minX) * scaleX, (ring[1] - minY) * scaleY);
        for (var i = 2; i + 1 < ring.length; i += 2) {
          path.lineTo((ring[i] - minX) * scaleX, (ring[i + 1] - minY) * scaleY);
        }
        path.close();
      }
      canvas.drawPath(path, Paint()..color = color);
      if (hasNote && !path.getBounds().isEmpty) {
        // A small dot at the ayah's reading start (top-right, the page
        // is RTL) — enough to say "there is a note here" without
        // covering any of the printed script.
        final b = path.getBounds();
        final r = (size.width * 0.008).clamp(1.6, 4.0);
        final c = Offset(b.right - r, b.top + r);
        canvas.drawCircle(
            c, r, Paint()..color = color.withValues(alpha: 0.95));
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.4
              ..color = AppColors.secondary.withValues(alpha: 0.9));
      }
    }
  }

  @override
  bool shouldRepaint(_AyahMarkPainter oldDelegate) =>
      oldDelegate.scaleX != scaleX ||
      oldDelegate.scaleY != scaleY ||
      oldDelegate.minX != minX ||
      oldDelegate.minY != minY ||
      !_sameMarks(oldDelegate.marks);

  bool _sameMarks(List<(AyahHitRegion, Color, bool)> other) {
    if (other.length != marks.length) return false;
    for (var i = 0; i < marks.length; i++) {
      if (!identical(other[i].$1, marks[i].$1) ||
          other[i].$2 != marks[i].$2 ||
          other[i].$3 != marks[i].$3) {
        return false;
      }
    }
    return true;
  }
}

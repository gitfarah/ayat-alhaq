import 'package:flutter/material.dart';
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
import '../services/settings_service.dart';
import '../l10n/app_strings.dart';
import '../theme.dart';
import '../widgets/reciter_picker.dart';
import 'tafsir_screen.dart';

class MushafSvgScreen extends StatefulWidget {
  final int? startPage;
  const MushafSvgScreen({super.key, this.startPage});

  @override
  State<MushafSvgScreen> createState() => _MushafSvgScreenState();
}

class _MushafSvgScreenState extends State<MushafSvgScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late int _pageNum;

  /// Real swipeable paging (finger-following, like printed pages).
  /// Nullable because it is (re)created in build() where screen width
  /// is known — a wide screen pages by 2-page spreads.
  PageController? _pageCtrl;
  bool _wide = false;

  /// Per-index page-load futures so rebuilds don't refetch; pruned to
  /// the neighbourhood of the current page to keep memory flat.
  final Map<int, Future<List<MushafPageData>>> _pageFutures = {};

  bool _isCachedOffline = false;
  bool _barsVisible = true;
  List<Bookmark> _bookmarks = [];
  List<Highlight> _highlights = [];
  QuranAudioService? _audioService;
  int? _lastFollowedAyah;

  /// Whether the whole Mushaf is stored offline. Download itself is
  /// owned by MushafSvgService and survives leaving this screen.
  bool _fullyDownloaded = false;

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
            style: TextStyle(fontFamily: 'Amiri', height: 1.6))));
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
                fontFamily: 'Amiri',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? AppColors.darkText : AppColors.textPrimary)),
        content: Text(
            'هل تريد تنزيل صفحات المصحف كاملة (٦٠٤ صفحات، ~٣٥٠ م.ب) لتتمكن من تصفحها دون اتصال بالإنترنت؟\nيمكنك بدء التنزيل لاحقاً من قائمة ☰ في أي وقت.',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                fontFamily: 'Amiri',
                height: 1.8,
                fontSize: 14,
                color: isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('لاحقاً', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تنزيل الآن',
                  style: TextStyle(color: Colors.white, fontFamily: 'Amiri'))),
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

  Bookmark? _bookmarkFor(AyahHitRegion r) => _bookmarks
      .cast<Bookmark?>()
      .firstWhere(
          (b) =>
              b!.surahNumber == r.surahNumber && b.ayahNumber == r.ayahNumber,
          orElse: () => null);

  Highlight? _highlightFor(AyahHitRegion r) => _highlights
      .cast<Highlight?>()
      .firstWhere(
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

  /// Two-page spread only on genuinely large screens (desktop or a
  /// tablet in landscape). A PHONE rotated to landscape is still a
  /// small screen — it keeps a single page, zoomed to full width and
  /// vertically scrollable (see _buildPageArtwork).
  bool _isWideScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (size.width >= 1000) return true;
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
                fontFamily: 'Amiri',
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
                fontFamily: 'Amiri',
                color: isDark ? AppColors.darkText : AppColors.textPrimary),
            decoration: InputDecoration(
                hintText: '١ — ٦٠٤',
                hintStyle:
                    TextStyle(color: Colors.grey[400], fontFamily: 'Amiri'),
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
                  style: TextStyle(color: Colors.white, fontFamily: 'Amiri'))),
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
                    style: TextStyle(fontFamily: 'Amiri', color: textColor)),
                onTap: () {
                  Navigator.pop(context);
                  _showSurahPicker();
                }),
            ListTile(
                leading: Icon(Icons.auto_awesome_mosaic_rounded,
                    color: iconColor),
                title: Text('الانتقال إلى جزء',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontFamily: 'Amiri', color: textColor)),
                onTap: () {
                  Navigator.pop(context);
                  _showJuzPicker();
                }),
            ListTile(
                leading: Icon(Icons.tag_rounded, color: iconColor),
                title: Text('الانتقال إلى صفحة',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontFamily: 'Amiri', color: textColor)),
                onTap: () {
                  Navigator.pop(context);
                  _jumpDialog();
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
                        style:
                            TextStyle(fontFamily: 'Amiri', color: textColor)),
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
                    fontFamily: 'Amiri',
                    fontSize: 14,
                    color: isDark
                        ? AppColors.darkTextSec
                        : AppColors.textSecondary)),
            title: Text(QuranPageMeta.surahNames[i],
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontFamily: 'Amiri', fontSize: 16, color: textColor)),
            leading: Text('ص ${_ar(QuranPageMeta.surahStartPages[i])}',
                style: TextStyle(
                    fontFamily: 'Amiri',
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
                crossAxisCount: 6,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10),
            itemCount: 30,
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _loadPage(QuranPageMeta.juzStartPages[i]);
              },
              child: Container(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: gold.withValues(alpha: 0.5))),
                child: Center(
                    child: Text(_ar(i + 1),
                        style: TextStyle(
                            fontFamily: 'Amiri',
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
                    fontFamily: 'Amiri',
                    color:
                        isDark ? AppColors.darkText : AppColors.textPrimary)),
            const Divider(height: 24),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    playingThis
                        ? Icons.pause_circle_rounded
                        : Icons.play_circle_rounded,
                    color: isDark ? AppColors.darkPrimary : AppColors.primary),
                title: Text(
                    playingThis ? l('pauseRecitation') : l('playRecitation'),
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontFamily: 'Amiri',
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
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(audio.error!)));
                  }
                }),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.menu_book_rounded,
                    color: isDark ? AppColors.darkPrimary : AppColors.primary),
                title: Text(l('tafsir'),
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontFamily: 'Amiri',
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
                        : (isDark ? AppColors.darkPrimary : AppColors.primary)),
                title: Text(l('bookmark'),
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontFamily: 'Amiri',
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
                        fontFamily: 'Amiri',
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _showHighlightPicker(region);
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
                    fontFamily: 'Amiri',
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
                              const SnackBar(
                                  content: Text('تم إزالة الفاصل')));
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
                                    color:
                                        Colors.black.withValues(alpha: 0.1),
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
    final bgColor = isDark ? AppColors.darkBg : AppColors.background;
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;

    // (Re)create the controller when wide-mode flips — index math
    // differs between single pages and 2-page spreads.
    final wide = _isWideScreen(context);
    if (_pageCtrl == null || wide != _wide) {
      _wide = wide;
      _pageCtrl?.dispose();
      _pageCtrl = PageController(initialPage: _indexForPage(_pageNum));
      _pageFutures.clear();
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(children: [
        // ── The pages: ALWAYS full-bleed. The bars float on top and
        // never resize the page, so toggling them causes no zoom jump.
        // PageView gives real finger-following page turns; reverse =
        // RTL book order (swipe right, like flipping a printed page,
        // advances).
        Positioned.fill(
          child: PageView.builder(
            controller: _pageCtrl,
            reverse: true,
            itemCount: _pageCount,
            onPageChanged: (i) {
              _setBars(false);
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
              _buildNavBar(isDark),
            ]),
          ),
        ),
      ]),
    );
  }

  /// One PageView item: a single page, or a 2-page spread on wide
  /// screens. Loads through a cached future so rebuilds don't refetch.
  Widget _buildPageItem(int index, bool isDark) {
    final base = _pageForIndex(index);
    final future = _pageFutures[index] ??= () async {
      final first = await MushafSvgService.getPage(base);
      if (!_wide || base + 1 > 604) return [first];
      try {
        return [first, await MushafSvgService.getPage(base + 1)];
      } catch (_) {
        return [first];
      }
    }();

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
                          fontFamily: 'Amiri',
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
                              color: Colors.white, fontFamily: 'Amiri'))),
                ]));
          }
          if (!snap.hasData) {
            return Center(
                child: CircularProgressIndicator(
                    color:
                        isDark ? AppColors.darkPrimary : AppColors.primary));
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
        border:
            Border(bottom: BorderSide(color: gold.withValues(alpha: 0.5))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08), blurRadius: 6),
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
                          fontFamily: 'Amiri',
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
            IconButton(
                icon: Icon(Icons.menu_rounded, color: textColor),
                onPressed: _showMenuSheet),
          ]),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Directionality(
              textDirection: TextDirection.rtl,
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
                            fontFamily: 'Amiri',
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
                          fontFamily: 'Amiri',
                          fontSize: 12,
                          color: subText)),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildSinglePage(MushafPageData data, bool isDark) {
    // Pages 1-2 get the illuminated opening frame
    if (data.pageNumber <= 2) {
      return _buildIlluminatedPage(data, isDark);
    }
    // Just the page artwork at its maximum size — the info header
    // lives in the floating top bar now, so the page NEVER resizes.
    return Padding(
      padding: const EdgeInsets.all(2),
      child: _buildPageArtwork(data, isDark),
    );
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
                        fontFamily: 'Amiri',
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

        final scaleX = renderWidth / data.viewBoxWidth;
        final scaleY = renderHeight / data.viewBoxHeight;

        final page = Center(
          child: SizedBox(
            width: renderWidth,
            height: renderHeight,
            child: Stack(children: [
              Positioned.fill(
                child: isDark
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.matrix([
                          -1,
                          0,
                          0,
                          0,
                          255,
                          0,
                          -1,
                          0,
                          0,
                          255,
                          0,
                          0,
                          -1,
                          0,
                          255,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]),
                        child: SvgPicture.string(data.svgContent,
                            fit: BoxFit.contain))
                    : SvgPicture.string(data.svgContent, fit: BoxFit.contain),
              ),
              // Tint marked ayahs using their exact polygon outlines (a
              // bounding-box tint would bleed onto neighbouring ayahs
              // for multi-line ayahs). Priority: currently-recited gold
              // tint, then bookmark, then highlight — same as the reader.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _AyahMarkPainter(
                      marks: [
                        for (final r in data.ayahRegions)
                          if (r.ayahNumber > 0 && r.surahNumber > 0)
                            if (identical(r, _flashRegion))
                              (
                                r,
                                (isDark
                                        ? AppColors.darkSecondary
                                        : AppColors.secondary)
                                    .withValues(
                                        alpha:
                                            (1 - _flashCtrl.value) * 0.40)
                              )
                            else if (_playingGlobalAyah != null &&
                                _regionGlobal(r) == _playingGlobalAyah)
                              (
                                r,
                                (isDark
                                        ? AppColors.darkSecondary
                                        : AppColors.secondary)
                                    .withValues(alpha: isDark ? 0.30 : 0.16)
                              )
                            else if (_bookmarkFor(r) != null)
                              (
                                r,
                                AppColors.highlight(_bookmarkFor(r)!.color)
                                    .withValues(alpha: isDark ? 0.32 : 0.22)
                              )
                            else if (_highlightFor(r) != null)
                              (
                                r,
                                AppColors.highlight(_highlightFor(r)!.color)
                                    .withValues(alpha: isDark ? 0.35 : 0.25)
                              ),
                      ],
                      scaleX: scaleX,
                      scaleY: scaleY,
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
                    final vx = details.localPosition.dx / scaleX;
                    final vy = details.localPosition.dy / scaleY;
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

        if (!scrollZoom) return page;
        // Phone landscape: full-width page, scrolled vertically.
        return SingleChildScrollView(
          child: SizedBox(
            width: renderWidth,
            height: renderHeight,
            child: page,
          ),
        );
      },
    );
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
                color: isDark
                    ? AppColors.darkTextSec
                    : AppColors.textSecondary),
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
                color:
                    isDark ? AppColors.darkTextSec : AppColors.textSecondary,
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
                  fontFamily: 'Amiri',
                  color: isDark ? AppColors.darkTextSec : AppColors.textSecondary),
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
                                fontFamily: 'Amiri'))))),
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
  final List<(AyahHitRegion, Color)> marks;
  final double scaleX;
  final double scaleY;

  _AyahMarkPainter({
    required this.marks,
    required this.scaleX,
    required this.scaleY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final (region, color) in marks) {
      final path = Path();
      for (final ring in region.rings) {
        if (ring.length < 6) continue;
        path.moveTo(ring[0] * scaleX, ring[1] * scaleY);
        for (var i = 2; i + 1 < ring.length; i += 2) {
          path.lineTo(ring[i] * scaleX, ring[i + 1] * scaleY);
        }
        path.close();
      }
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_AyahMarkPainter oldDelegate) =>
      oldDelegate.scaleX != scaleX ||
      oldDelegate.scaleY != scaleY ||
      !_sameMarks(oldDelegate.marks);

  bool _sameMarks(List<(AyahHitRegion, Color)> other) {
    if (other.length != marks.length) return false;
    for (var i = 0; i < marks.length; i++) {
      if (!identical(other[i].$1, marks[i].$1) ||
          other[i].$2 != marks[i].$2) {
        return false;
      }
    }
    return true;
  }
}

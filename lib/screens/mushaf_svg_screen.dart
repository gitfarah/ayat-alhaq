import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quran_page_meta.dart';
import '../services/mushaf_svg_service.dart';
import '../services/bookmark_service.dart';
import '../services/highlight_service.dart';
import '../services/khatma_service.dart';
import '../services/library_events.dart';
import '../services/quran_audio_service.dart';
import '../services/settings_service.dart';
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
  MushafPageData? _pageData;
  MushafPageData? _secondPageData;
  bool _loading = true;
  String? _error;
  bool _isCachedOffline = false;
  bool _barsVisible = true;
  List<Bookmark> _bookmarks = [];
  List<Highlight> _highlights = [];
  QuranAudioService? _audioService;
  int? _lastFollowedAyah;

  /// Full-Mushaf background download state (one run per screen).
  bool _bulkDownloading = false;
  bool _bulkCancel = false;
  int _bulkDone = 0;
  bool _fullyDownloaded = false;

  /// +1 = turning forward (new page slides in from the left, matching
  /// RTL page order), -1 = turning back.
  int _turnDirection = 1;

  /// A page turn is loading while the current page stays visible.
  bool _turning = false;

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
      _loadPage(_pageNum);
      // Auto-advance simply moves to the next global ayah — the Mushaf
      // view isn't scoped to one surah, so recitation flows across
      // surah boundaries just like reading the pages does.
      _audioService!.nextAyahResolver = (g) => g < 6236 ? g + 1 : null;
      _maybeOfferFullDownload();
    });
  }

  /// Bars visibility + system chrome together: hiding the bars also
  /// hides the status/navigation bars so the page truly fills the
  /// screen; showing them restores normal chrome.
  void _setBars(bool visible) {
    if (_barsVisible == visible) return;
    setState(() => _barsVisible = visible);
    SystemChrome.setEnabledSystemUIMode(
        visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  /// One-time offer (per install) to download the whole Mushaf for
  /// offline reading. Never silently pulls ~350 MB on the user's data
  /// plan — it asks first; afterwards the download can always be
  /// started from the menu.
  Future<void> _maybeOfferFullDownload() async {
    if (!MushafSvgService.supportsFullOfflineDownload) return;
    _fullyDownloaded = await MushafSvgService.isFullyDownloaded();
    if (_fullyDownloaded || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
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
    if (go == true) _startBulkDownload();
  }

  Future<void> _startBulkDownload() async {
    if (_bulkDownloading) return;
    setState(() {
      _bulkDownloading = true;
      _bulkCancel = false;
      _bulkDone = 0;
    });
    await MushafSvgService.downloadEntireMushaf(
      onProgress: (done, total) {
        if (!mounted) return;
        // Repaint sparsely; every page would rebuild 604 times.
        if (done % 5 == 0 || done == total) {
          setState(() => _bulkDone = done);
        } else {
          _bulkDone = done;
        }
      },
      isCancelled: () => _bulkCancel || !mounted,
    );
    if (!mounted) return;
    _fullyDownloaded = await MushafSvgService.isFullyDownloaded();
    if (!mounted) return;
    setState(() => _bulkDownloading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_fullyDownloaded
            ? '✓ اكتمل تنزيل المصحف — التصفح متاح دون اتصال'
            : 'توقف التنزيل — يمكنك المتابعة لاحقاً من القائمة')));
  }

  @override
  void dispose() {
    _bulkCancel = true;
    // Never leave the app stuck in immersive mode after this screen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

  bool _pageHasAyah(MushafPageData? d, int g) =>
      d != null &&
      d.ayahRegions.any((r) =>
          r.surahNumber > 0 && r.ayahNumber > 0 && _regionGlobal(r) == g);

  /// When recitation advances to an ayah that is no longer on the
  /// visible page(s), turn the page forward — exactly like a reader
  /// following along in a printed Mushaf.
  void _followRecitation() {
    if (!mounted || _loading || _pageData == null) return;
    final audio = _audioService;
    if (audio == null || !audio.hasActiveTrack) return;
    final g = audio.currentGlobalAyah;
    if (g == null || g == _lastFollowedAyah) return;
    _lastFollowedAyah = g;

    if (_pageHasAyah(_pageData, g) || _pageHasAyah(_secondPageData, g)) {
      return; // still visible — build() repaints the tint via watch.
    }

    // Only follow FORWARD flow (the ayah right after the last visible
    // one); if the user started audio elsewhere, don't yank the page.
    var maxG = 0;
    for (final d in [_pageData, _secondPageData]) {
      if (d == null) continue;
      for (final r in d.ayahRegions) {
        if (r.surahNumber > 0 && r.ayahNumber > 0) {
          final rg = _regionGlobal(r);
          if (rg > maxG) maxG = rg;
        }
      }
    }
    final step = _isWideScreen(context) ? 2 : 1;
    if (maxG > 0 && g == maxG + 1 && _pageNum + step <= 604) {
      _loadPage(_pageNum + step);
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading) return;
      final wide = _isWideScreen(context);
      final hasSecond = _secondPageData != null;
      if (wide != hasSecond) _loadPage(_pageNum);
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

  Future<void> _loadPage(int page) async {
    final wide = _isWideScreen(context);
    final basePage = wide ? _spreadBase(page) : page;
    // Which way the incoming page should slide in (Mushaf pages run
    // right-to-left, so forward = enters from the left).
    if (basePage != _pageNum) _turnDirection = basePage > _pageNum ? 1 : -1;
    // Only the very first load blanks the screen with a spinner —
    // page TURNS keep the current page visible until the next one is
    // ready, so the slide animation goes page-to-page directly.
    final firstLoad = _pageData == null;

    setState(() {
      _error = null;
      if (firstLoad) {
        _loading = true;
        _secondPageData = null;
      } else {
        _turning = true;
      }
      _pageNum = basePage;
    });

    context.read<SettingsService>().saveLastRead(page: basePage);

    try {
      final wasCached = await MushafSvgService.isCached(basePage);
      final data = await MushafSvgService.getPage(basePage);

      MushafPageData? secondData;
      if (wide && basePage + 1 <= 604) {
        try {
          secondData = await MushafSvgService.getPage(basePage + 1);
        } catch (_) {
          secondData = null;
        }
      }

      if (!mounted) return;
      setState(() {
        _pageData = data;
        _secondPageData = secondData;
        _loading = false;
        _turning = false;
        _isCachedOffline = wasCached;
      });

      // Khatma auto-tracking: count the viewed page(s) as read.
      KhatmaService.markPageRead(basePage);
      if (secondData != null) KhatmaService.markPageRead(basePage + 1);

      final step = wide ? 2 : 1;
      MushafSvgService.preload(basePage + step);
      MushafSvgService.preload(basePage + step + 1);
      MushafSvgService.preload(basePage - step);
      MushafSvgService.preload(basePage - 1);
    } catch (e) {
      debugPrint('MushafSvgScreen error loading page $page: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _turning = false;
        if (firstLoad) {
          _error = 'تعذّر تحميل الصفحة\n$e';
        }
      });
      if (!firstLoad) {
        // The previous page is still on screen — a snackbar suffices.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر تحميل الصفحة، تحقق من اتصالك')));
      }
    }
  }

  void _next() {
    final step = _isWideScreen(context) ? 2 : 1;
    if (_pageNum + step <= 604) _loadPage(_pageNum + step);
  }

  void _prev() {
    final step = _isWideScreen(context) ? 2 : 1;
    if (_pageNum - step >= 1) _loadPage(_pageNum - step);
  }

  String _ar(int n) {
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

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
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                final p = int.tryParse(ctrl.text);
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
              ListTile(
                  leading: Icon(
                      _fullyDownloaded
                          ? Icons.offline_pin_rounded
                          : (_bulkDownloading
                              ? Icons.downloading_rounded
                              : Icons.download_rounded),
                      color: iconColor),
                  title: Text(
                      _fullyDownloaded
                          ? 'المصحف كامل محفوظ دون اتصال ✓'
                          : (_bulkDownloading
                              ? 'جارٍ التنزيل ($_bulkDone/٦٠٤) — اضغط للإيقاف'
                              : 'تنزيل المصحف كاملاً دون اتصال'),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontFamily: 'Amiri', color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    if (_fullyDownloaded) return;
                    if (_bulkDownloading) {
                      setState(() => _bulkCancel = true);
                    } else {
                      _startBulkDownload();
                    }
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
                title: Text(playingThis ? 'إيقاف التلاوة' : 'تشغيل التلاوة',
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
                title: Text('التفسير',
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
                title: Text('الفاصل',
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
                title: Text('تمييز الآية',
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

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _barsVisible
          ? AppBar(
              backgroundColor: bgColor,
              leading: IconButton(
                  icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_ios_rounded,
                          size: 16, color: textColor)),
                  onPressed: () => Navigator.pop(context)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                      _secondPageData != null
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
              actions: [
                IconButton(
                    icon: Icon(Icons.menu_rounded, color: textColor),
                    onPressed: _showMenuSheet),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => _setBars(!_barsVisible),
        // Finger swipe page turning. Mushaf pages advance right-to-left,
        // so a rightward fling (like flipping a printed page over to the
        // right) goes FORWARD and a leftward fling goes back. Swiping
        // also hides the bars so the page takes the full screen while
        // reading; a tap brings them back.
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v > 200) {
            _setBars(false);
            _next();
          } else if (v < -200) {
            _setBars(false);
            _prev();
          }
        },
        child: _loading
            ? Center(
                child: CircularProgressIndicator(
                    color: isDark ? AppColors.darkPrimary : AppColors.primary))
            : _error != null
                ? Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
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
                            onPressed: () => _loadPage(_pageNum),
                            icon: const Icon(Icons.refresh_rounded,
                                color: Colors.white),
                            label: const Text('إعادة المحاولة',
                                style: TextStyle(
                                    color: Colors.white, fontFamily: 'Amiri'))),
                      ]))
                : Column(children: [
                    // Slim indicator while the next page loads over the
                    // still-visible current page (slow networks only —
                    // preloaded neighbours turn instantly).
                    if (_turning)
                      LinearProgressIndicator(
                          minHeight: 2,
                          color: isDark
                              ? AppColors.darkPrimary
                              : AppColors.primary,
                          backgroundColor: Colors.transparent),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) =>
                            SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(_turnDirection * -0.25, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child:
                              FadeTransition(opacity: animation, child: child),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(
                              'p${_pageData?.pageNumber}-${_secondPageData?.pageNumber}'),
                          child: _buildPageView(isDark),
                        ),
                      ),
                    ),
                    if (audio.hasActiveTrack) _buildAudioBar(audio, isDark),
                    if (_barsVisible) _buildNavBar(isDark),
                  ]),
      ),
    );
  }

  Widget _buildPageView(bool isDark) {
    final wide = _isWideScreen(context) && _secondPageData != null;

    if (!wide) return _buildSinglePage(_pageData!, isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Expanded(child: _buildSinglePage(_secondPageData!, isDark)),
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
                (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Expanded(child: _buildSinglePage(_pageData!, isDark)),
      ]),
    );
  }

  Widget _buildSinglePage(MushafPageData data, bool isDark) {
    // Pages 1-2 get the illuminated opening frame
    if (data.pageNumber <= 2) {
      return _buildIlluminatedPage(data, isDark);
    }

    const gold = AppColors.mushafBorderGold;
    final headerBg = isDark ? AppColors.darkSurface : Colors.white;
    final headerText = isDark ? AppColors.darkPrimary : AppColors.primary;
    final subText = isDark ? AppColors.darkTextSec : AppColors.textSecondary;

    final juz = QuranPageMeta.juzForPage(data.pageNumber);
    final hizb = QuranPageMeta.hizbForPage(data.pageNumber);
    final surahLabel = QuranPageMeta.headerLabelForPage(data.pageNumber);
    final surahCount = QuranPageMeta.surahsOnPage(data.pageNumber).length;

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: _barsVisible ? 4 : 0, vertical: _barsVisible ? 4 : 0),
      child: Column(children: [
        // The page info header is part of the chrome: it disappears
        // with the bars so the page itself gets every pixel while the
        // user is immersed in reading.
        if (_barsVisible)
        // ── Header: a single compact, CENTERED group — juz/hizb block,
        // a thin divider, then the surah name(s). Deliberately NOT
        // stretched edge-to-edge (that created a large dead gap in the
        // middle when there was only one short surah name). Wrapped in
        // Directionality so the surah name renders on the visual right
        // and the juz/hizb block on the visual left, matching the
        // printed Mushaf convention, regardless of the surrounding
        // widget tree's directionality.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: headerBg,
              border: Border(
                  bottom: BorderSide(
                      color: gold.withValues(alpha: 0.5), width: 1))),
          child: Center(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Rightmost (first in RTL): surah name(s)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      surahLabel,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: surahCount > 1 ? 12 : 14,
                        fontWeight: FontWeight.bold,
                        color: headerText,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                      width: 1,
                      height: 26,
                      color: gold.withValues(alpha: 0.45)),
                  const SizedBox(width: 14),
                  // Leftmost (last in RTL): juz + hizb
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('الجزء ${_ar(juz)}',
                          style: TextStyle(
                              fontFamily: 'Amiri',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: headerText)),
                      Text('الحزب ${_ar(hizb)}',
                          style: TextStyle(
                              fontFamily: 'Amiri',
                              fontSize: 10,
                              color: subText)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Page artwork ──────────────────────────────────────────────
        Expanded(child: _buildPageArtwork(data, isDark)),
      ]),
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
              // Single tap layer doing polygon hit-testing, so a tap
              // always resolves to the ayah actually under the finger.
              // Skip regions with missing metadata (some dataset pages
              // have surahNumber/ayahNumber = 0). A tap on empty space
              // falls through to the bars toggle, matching the old
              // behaviour outside the artwork.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {}, // required so onTapUp wins the arena
                  onTapUp: (details) {
                    final vx = details.localPosition.dx / scaleX;
                    final vy = details.localPosition.dy / scaleY;
                    for (final region in data.ayahRegions) {
                      if (region.ayahNumber > 0 &&
                          region.surahNumber > 0 &&
                          region.containsPoint(vx, vy)) {
                        // Visual + haptic confirmation of WHICH ayah
                        // the tap landed on.
                        HapticFeedback.selectionClick();
                        setState(() => _flashRegion = region);
                        _flashCtrl.forward(from: 0);
                        _showAyahOptions(region);
                        return;
                      }
                    }
                    _setBars(!_barsVisible);
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

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/surah.dart';
import '../services/quran_service.dart';
import '../services/bookmark_service.dart';
import '../services/highlight_service.dart';
import '../services/khatma_service.dart';
import '../services/settings_service.dart';
import '../services/quran_audio_service.dart';
import '../services/tajweed_service.dart';
import '../l10n/app_strings.dart';
import '../theme.dart';
import '../widgets/reciter_picker.dart';
import '../widgets/surah_frame.dart';
import 'tafsir_screen.dart';

class ReaderScreen extends StatefulWidget {
  final Surah surah;
  final int? targetAyah;
  final int? targetAyahNumber;
  const ReaderScreen({
    Key? key,
    required this.surah,
    this.targetAyah,
    this.targetAyahNumber,
  }) : super(key: key);
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  List<Ayah> _ayahs = [];
  bool _loading = true;
  String? _error;
  List<Bookmark> _bookmarks = [];
  List<Highlight> _highlights = [];
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  int _page = 1, _juz = 1, _hizb = 1;
  bool _barsVisible = true;

  /// Auto-follow: the reader scrolls to keep the currently-reciting
  /// ayah on screen. [_lastAudioAyah] guards against re-scrolling to
  /// the same ayah on every audio notification.
  QuranAudioService? _audioSvc;
  int? _lastAudioAyah;

  void _followAudio() {
    final a = _audioSvc;
    if (!mounted || a == null || !a.hasActiveTrack) return;
    final g = a.currentGlobalAyah;
    if (g == null || g == _lastAudioAyah) return;
    _lastAudioAyah = g;
    final idx = _ayahs.indexWhere((x) => x.number == g);
    if (idx == -1 || !_scroll.isAttached) return;
    _scroll.scrollTo(
      index: idx + _headerOffset,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.3, // keep the ayah in the upper third
    );
  }

  /// Bars + system chrome together (same model as the Mushaf screen):
  /// a fast tap anywhere toggles them, scrolling hides them, and
  /// long-pressing an ayah opens its options.
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

  /// Every surah opens with the Basmala on its own line, except
  /// Al-Fatiha (the Basmala is ayah 1 there) and At-Tawbah (has none).
  bool get _showBasmala =>
      widget.surah.number != 1 && widget.surah.number != 9;

  /// List-index shift caused by the decorated surah-name frame (always
  /// item 0) plus the Basmala header item when shown.
  int get _headerOffset => 1 + (_showBasmala ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _loadAll();
    // Tajweed colouring data (only actually used when the setting is on,
    // but loading it up front keeps the toggle instant).
    if (!TajweedService.isLoaded) {
      TajweedService.load().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// Edition the currently shown ayahs were loaded with (may lag the
  /// setting until the reload completes).
  String? _loadedEdition;

  Future<void> _loadAll() async {
    final edition = context.read<SettingsService>().translationEdition;
    try {
      // Fetch everything needed for the first paint concurrently, but
      // wait for ALL three before calling setState a single time. The
      // previous version called setState separately inside each of
      // _loadAyahs/_loadBookmark/_loadHighlights as soon as that one
      // future resolved — since ayahs (network) and bookmark/highlight
      // (local SharedPreferences) don't finish at the same moment, this
      // caused the target ayah to render first with no color, then
      // "pop in" a bookmark/highlight color a moment later. Combining
      // them into one setState removes that visible flash entirely.
      final results = await Future.wait([
        QuranService.getSurahAyahs(widget.surah.number,
            translationEdition: edition),
        BookmarkService.getBookmarksBySurah(widget.surah.number),
        HighlightService.getHighlightsBySurah(widget.surah.number),
      ]);

      if (!mounted) return;
      final data = results[0] as List<Ayah>;
      final bookmarks = results[1] as List<Bookmark>;
      final highlights = results[2] as List<Highlight>;

      setState(() {
        _ayahs = data;
        _bookmarks = bookmarks;
        _highlights = highlights;
        _loadedEdition = edition;
        _loading = false;
        if (data.isNotEmpty) {
          _page = data.first.page;
          _juz = data.first.juz;
          _hizb = data.first.hizb;
        }
      });
      if (data.isNotEmpty) KhatmaService.markPageRead(data.first.page);

      // Give the audio service a way to resolve "what comes next" for
      // auto-advance, scoped to THIS surah's loaded ayah list. Cleared
      // in dispose() so a stale closure never outlives this screen.
      final audio = context.read<QuranAudioService>();
      audio.nextAyahResolver = (currentGlobalAyah) {
        final idx = _ayahs.indexWhere((a) => a.number == currentGlobalAyah);
        if (idx == -1 || idx + 1 >= _ayahs.length) return null;
        return _ayahs[idx + 1].number;
      };
      // Follow the recitation on screen (scroll to the playing ayah).
      _audioSvc = audio;
      audio.removeListener(_followAudio);
      audio.addListener(_followAudio);

      final scrollTarget = widget.targetAyah ?? widget.targetAyahNumber;
      if (scrollTarget != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollTo(scrollTarget));
      }
      _positions.itemPositions.addListener(_onScroll);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'خطأ في تحميل الآيات';
      });
    }
  }

  void _onScroll() {
    final pos = _positions.itemPositions.value;
    if (pos.isEmpty) return;
    final idx = pos.first.index - _headerOffset;
    if (idx >= 0 && idx < _ayahs.length) {
      final a = _ayahs[idx];
      if (a.page != _page || a.juz != _juz) {
        setState(() {
          _page = a.page;
          _juz = a.juz;
          _hizb = a.hizb;
        });
        context.read<SettingsService>().saveLastRead(
              surah: widget.surah.number,
              ayah: a.numberInSurah,
            );
        // Khatma auto-tracking: scrolling into a page counts it as read.
        KhatmaService.markPageRead(a.page);
      }
    }
  }

  void _scrollTo(int ayahNum) {
    final idx = _ayahs.indexWhere((a) => a.numberInSurah == ayahNum);
    if (idx != -1) {
      _scroll.scrollTo(
        index: idx + _headerOffset,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        alignment: 0.2,
      );
    }
  }

  /// Reloads just the bookmark/highlight state after the user adds or
  /// removes one from the options sheet, without refetching ayah text.
  Future<void> _refreshBookmarkAndHighlights() async {
    final results = await Future.wait([
      BookmarkService.getBookmarksBySurah(widget.surah.number),
      HighlightService.getHighlightsBySurah(widget.surah.number),
    ]);
    if (!mounted) return;
    setState(() {
      _bookmarks = results[0] as List<Bookmark>;
      _highlights = results[1] as List<Highlight>;
    });
  }

  Bookmark? _bookmarkFor(int n) => _bookmarks
      .cast<Bookmark?>()
      .firstWhere((b) => b?.ayahNumber == n, orElse: () => null);

  Highlight? _getHL(int n) => _highlights
      .cast<Highlight?>()
      .firstWhere((h) => h?.ayahNumber == n, orElse: () => null);

  /// Ribbon-marker picker: the app supports one bookmark PER COLOR
  /// (like colored ribbons in a printed Mushaf). Choosing a color moves
  /// that ribbon here; the block dot removes this ayah's bookmark.
  void _showBookmarkPicker(int ayahNumber) {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final l = L10n.of(context);
    final existing = _bookmarkFor(ayahNumber);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(l('chooseBookmarkColor'),
                style: TextStyle(
                    fontFamily: 'Almarai',
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
                    _Dot(
                      name: 'none',
                      color: Colors.grey.shade300,
                      selected: false,
                      onTap: () async {
                        Navigator.pop(context);
                        await BookmarkService.deleteBookmarkByAyah(
                            widget.surah.number, ayahNumber);
                        await _refreshBookmarkAndHighlights();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l('removedBookmark'))));
                        }
                      },
                    ),
                  ...AppColors.highlights.entries.map(
                    (e) => _Dot(
                      name: e.key,
                      color: e.value,
                      selected: existing?.color == e.key,
                      icon: Icons.bookmark_rounded,
                      onTap: () async {
                        Navigator.pop(context);
                        await BookmarkService.addBookmark(Bookmark(
                          surahNumber: widget.surah.number,
                          ayahNumber: ayahNumber,
                          surahName: widget.surah.name,
                          color: e.key,
                          createdAt: DateTime.now(),
                        ));
                        await _refreshBookmarkAndHighlights();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l('savedBookmark'))));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _copyAyah(String text, int n) async {
    await Clipboard.setData(
      ClipboardData(text: '${widget.surah.name} (${_ar(n)})\n$text'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context)('copiedAyah'))),
      );
    }
  }

  Future<void> _showOptions(Ayah ayah) async {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final l = L10n.of(context);
    final audio = context.read<QuranAudioService>();
    final existing = await HighlightService.getHighlight(
        widget.surah.number, ayah.numberInSurah);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Scrollable so the sheet never overflows on short (landscape)
      // screens.
      builder: (_) => SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              ayah.text,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                height: 1.8,
                fontFamily: 'QuranHafs',
                color: isDark ? AppColors.darkText : AppColors.textPrimary,
              ),
            ),
            const Divider(height: 24),
            // Highlight color row
            SizedBox(
              height: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (existing != null)
                    _Dot(
                      name: 'none',
                      color: Colors.grey.shade300,
                      selected: false,
                      onTap: () async {
                        Navigator.pop(context);
                        await HighlightService.deleteHighlight(
                            widget.surah.number, ayah.numberInSurah);
                        await _refreshBookmarkAndHighlights();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l('removedHighlight'))),
                          );
                        }
                      },
                    ),
                  ...AppColors.highlights.entries.map(
                    (e) => _Dot(
                      name: e.key,
                      color: e.value,
                      selected: existing?.color == e.key,
                      onTap: () async {
                        Navigator.pop(context);
                        await HighlightService.addHighlight(Highlight(
                          surahNumber: widget.surah.number,
                          ayahNumber: ayah.numberInSurah,
                          surahName: widget.surah.name,
                          color: e.key,
                          createdAt: DateTime.now(),
                        ));
                        await _refreshBookmarkAndHighlights();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l('highlighted'))),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 8),
            // Play / pause recitation
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                (audio.currentGlobalAyah == ayah.number && audio.isPlaying)
                    ? Icons.pause_circle_rounded
                    : Icons.play_circle_rounded,
                color: AppColors.primary,
              ),
              title: Text(
                (audio.currentGlobalAyah == ayah.number && audio.isPlaying)
                    ? l('pauseRecitation')
                    : l('playRecitation'),
                style: const TextStyle(fontFamily: 'Almarai'),
              ),
              onTap: () async {
                Navigator.pop(context);
                // First-ever playback: let the user pick the reciter
                // once; the choice then sticks until changed on purpose.
                if (!mounted) return;
                final ok = await ensureReciterChosen(context, audio, isDark);
                if (!ok) return;
                await audio.togglePlayPause(ayah.number);
                // Playback failures only set audio.error — without this
                // the tap would silently do nothing.
                if (mounted && audio.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(audio.error!)),
                  );
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  _bookmarkFor(ayah.numberInSurah) != null
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_add_rounded,
                  color: _bookmarkFor(ayah.numberInSurah) != null
                      ? AppColors.highlight(
                          _bookmarkFor(ayah.numberInSurah)!.color)
                      : AppColors.primary),
              title: Text(l('bookmark'),
                  style: const TextStyle(fontFamily: 'Almarai')),
              onTap: () {
                Navigator.pop(context);
                _showBookmarkPicker(ayah.numberInSurah);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  const Icon(Icons.menu_book_rounded, color: AppColors.primary),
              title: Text(l('tafsir'),
                  style: const TextStyle(fontFamily: 'Almarai')),
              onTap: () {
                Navigator.pop(context);
                _showTafsir(ayah.numberInSurah, ayah.text);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy_rounded, color: AppColors.accent),
              title: Text(l('copyAyah'),
                  style: const TextStyle(fontFamily: 'Almarai')),
              onTap: () {
                Navigator.pop(context);
                _copyAyah(ayah.text, ayah.numberInSurah);
              },
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// In-surah search: filters THIS surah's loaded ayahs as the user
  /// types; tapping a match scrolls straight to that ayah.
  void _showSurahSearch() {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final l = L10n.of(context);
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(builder: (ctx, setSheet) {
        final q = QuranService.normalizeArabic(ctrl.text);
        final matches = q.length < 2
            ? const <Ayah>[]
            : _ayahs
                .where((a) =>
                    QuranService.normalizeArabic(a.text).contains(q))
                .toList();
        return Padding(
          // Keep the sheet above the keyboard.
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  onChanged: (_) => setSheet(() {}),
                  style: TextStyle(
                      fontFamily: 'Almarai',
                      color:
                          isDark ? AppColors.darkText : AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '${l('searchInSurah')} — ${widget.surah.name}',
                    hintTextDirection: TextDirection.rtl,
                    hintStyle: TextStyle(
                        fontFamily: 'Almarai',
                        color: isDark
                            ? AppColors.darkTextSec
                            : AppColors.textLight),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: Colors.grey[400]),
                    filled: true,
                    fillColor:
                        isDark ? AppColors.darkBg : AppColors.background,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              Expanded(
                child: matches.isEmpty
                    ? Center(
                        child: Text(
                            ctrl.text.trim().length < 2
                                ? l('typeAyahWord')
                                : l('noResultsInSurah'),
                            style: TextStyle(
                                fontFamily: 'Almarai',
                                color: isDark
                                    ? AppColors.darkTextSec
                                    : AppColors.textSecondary)))
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: matches.length,
                        itemBuilder: (_, i) {
                          final a = matches[i];
                          return ListTile(
                            dense: true,
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              _scrollTo(a.numberInSurah);
                            },
                            leading: Text(_ar(a.numberInSurah),
                                style: TextStyle(
                                    fontFamily: 'Almarai',
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.darkSecondary
                                        : AppColors.accent)),
                            title: Text(a.text,
                                textDirection: TextDirection.rtl,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: 'Almarai',
                                    fontSize: 15,
                                    height: 1.7,
                                    color: isDark
                                        ? AppColors.darkText
                                        : AppColors.textPrimary)),
                          );
                        }),
              ),
            ]),
          ),
        );
      }),
    );
  }

  void _showTafsir(int ayahNumber, String text) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TafsirScreen(
            surahNumber: widget.surah.number,
            surahName: widget.surah.name,
            ayahNumber: ayahNumber,
            ayahText: text,
          ),
        ));
  }

  String _ar(int number) {
    const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((d) => ar[int.parse(d)]).join();
  }

  /// The ayah's text as spans — one plain span normally, or a coloured
  /// span per tajweed rule when the setting is on and data is available.
  List<InlineSpan> _ayahSpans(
      Ayah ayah, SettingsService settings, bool isDark) {
    if (!settings.tajweed) return [TextSpan(text: ayah.text)];
    final segs =
        TajweedService.segments(widget.surah.number, ayah.numberInSurah);
    if (segs == null) return [TextSpan(text: ayah.text)];
    return [
      for (final s in segs)
        TextSpan(
          text: s.text,
          style: s.isPlain
              ? null
              : TextStyle(color: TajweedService.colorFor(s.rule)),
        ),
    ];
  }

  @override
  void dispose() {
    // Never leave the app stuck in immersive mode after this screen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _positions.itemPositions.removeListener(_onScroll);
    _audioSvc?.removeListener(_followAudio);
    // Clear the resolver so it doesn't reference this screen's disposed
    // _ayahs list if audio is still playing when the user navigates away.
    try {
      context.read<QuranAudioService>().nextAyahResolver = null;
    } catch (_) {
      // Context may already be unusable during teardown — safe to ignore.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsService>();
    final audio = context.watch<QuranAudioService>();
    final isDark = settings.isDarkIn(context);
    final theme = Theme.of(context);

    // Reading surfaces keep their original fixed layout (RTL content,
    // LTR-positioned chrome) regardless of the app's UI language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
      body: _loading
          ? Center(
              child:
                  CircularProgressIndicator(color: theme.colorScheme.primary))
          : _error != null
              ? _buildError()
              : Stack(children: [
                  // The text is full-bleed with CONSTANT padding — the
                  // bars float above it, so toggling them never shifts
                  // the page up or down.
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => _setBars(!_barsVisible),
                      child: NotificationListener<UserScrollNotification>(
                        // Scrolling = reading: give the text the whole
                        // screen. A tap brings the bars back.
                        onNotification: (n) {
                          if (n.direction != ScrollDirection.idle) {
                            _setBars(false);
                          }
                          return false;
                        },
                        child: ScrollablePositionedList.builder(
                          itemScrollController: _scroll,
                          itemPositionsListener: _positions,
                          padding: EdgeInsets.fromLTRB(
                              16,
                              MediaQuery.of(context).padding.top +
                                  kToolbarHeight +
                                  8,
                              16,
                              110),
                          itemCount: _ayahs.length + _headerOffset,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              // Ornamental surah-name frame, like the
                              // decorated headers of the printed Mushaf.
                              // The surah name from the data already
                              // carries the "سُورَةُ" prefix.
                              return SurahFrame(
                                title: widget.surah.name,
                                isDark: isDark,
                              );
                            }
                            if (_showBasmala && index == 1) {
                              return Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 16),
                                child: Text(
                                  QuranService.basmala,
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    fontSize: settings.fontSize + 2,
                                    height: 1.8,
                                    fontFamily: 'QuranHafs',
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.darkText
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              );
                            }
                            final ayah = _ayahs[index - _headerOffset];
                            final bookmark =
                                _bookmarkFor(ayah.numberInSurah);
                            final isBookmarked = bookmark != null;
                            final highlight = _getHL(ayah.numberInSurah);
                            final isPlayingThis =
                                audio.currentGlobalAyah == ayah.number;

                            final bgColor = isPlayingThis
                                ? AppColors.secondary
                                    .withOpacity(isDark ? 0.22 : 0.12)
                                : isBookmarked
                                    ? AppColors.highlight(bookmark.color)
                                        .withOpacity(isDark ? 0.28 : 0.18)
                                    : highlight != null
                                        ? AppColors.highlight(highlight.color)
                                            .withOpacity(0.25)
                                        : (isDark
                                            ? AppColors.darkSurface
                                            : Colors.white);
                            final borderColor = isPlayingThis
                                ? AppColors.secondary
                                : isBookmarked
                                    ? AppColors.highlight(bookmark.color)
                                    : highlight != null
                                        ? AppColors.highlight(highlight.color)
                                        : (isDark
                                            ? AppColors.darkBorder
                                            : AppColors.border);

                            return GestureDetector(
                              // Fast tap = toggle the bars (same as
                              // empty space); options live behind a
                              // LONG-PRESS, like the big Mushaf apps.
                              onTap: () => _setBars(!_barsVisible),
                              onLongPress: () {
                                HapticFeedback.selectionClick();
                                _showOptions(ayah);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding:
                                    const EdgeInsets.fromLTRB(12, 14, 14, 14),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: borderColor,
                                    width: (isBookmarked || isPlayingThis)
                                        ? 1.5
                                        : 0.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    // Ribbon indicator — tells a
                                    // bookmark apart from a highlight
                                    // of the same color.
                                    if (isBookmarked)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Icon(Icons.bookmark_rounded,
                                            size: 16,
                                            color: AppColors.highlight(
                                                bookmark.color)),
                                      ),
                                    if (isPlayingThis)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              audio.isLoading
                                                  ? Icons.hourglass_top_rounded
                                                  : (audio.isPlaying
                                                      ? Icons.volume_up_rounded
                                                      : Icons
                                                          .pause_circle_outline_rounded),
                                              size: 14,
                                              color: AppColors.secondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              audio.isLoading
                                                  ? l('loading')
                                                  : l('nowReciting'),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontFamily: 'Almarai',
                                                color: AppColors.secondary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    RichText(
                                      // Right-aligned (not justified):
                                      // justification inserted spacing
                                      // that broke the visual flow of
                                      // Arabic words.
                                      textAlign: TextAlign.right,
                                      textDirection: TextDirection.rtl,
                                      text: TextSpan(
                                        style: TextStyle(
                                          fontSize: settings.fontSize,
                                          height: 2.1,
                                          color: isDark
                                              ? AppColors.darkText
                                              : AppColors.textPrimary,
                                          // Quran verses only.
                                          fontFamily: 'QuranHafs',
                                        ),
                                        children: [
                                          ..._ayahSpans(ayah, settings,
                                              isDark),
                                          const WidgetSpan(
                                              child: SizedBox(width: 6)),
                                          WidgetSpan(
                                            alignment:
                                                PlaceholderAlignment.middle,
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                  right: 4),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: (isDark
                                                            ? AppColors
                                                                .darkSecondary
                                                            : AppColors.accent)
                                                        .withOpacity(0.5)),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: isDark
                                                    ? AppColors.darkBg
                                                    : AppColors.background,
                                              ),
                                              child: Text(
                                                _ar(ayah.numberInSurah),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark
                                                      ? AppColors.darkSecondary
                                                      : AppColors.accent,
                                                  fontFamily: 'Almarai',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (ayah.translation != null) ...[
                                      Divider(
                                          height: 18,
                                          color: (isDark
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withValues(alpha: 0.08)),
                                      SizedBox(
                                        width: double.infinity,
                                        child: Text(
                                          '${ayah.numberInSurah}. ${ayah.translation!}',
                                          textDirection: _loadedEdition !=
                                                      null &&
                                                  QuranService.isRtlEdition(
                                                      _loadedEdition!)
                                              ? TextDirection.rtl
                                              : TextDirection.ltr,
                                          style: TextStyle(
                                            fontSize: (settings.fontSize - 10)
                                                .clamp(13.0, 22.0),
                                            height: 1.5,
                                            color: isDark
                                                ? AppColors.darkTextSec
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  // Floating top bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedSlide(
                      offset:
                          _barsVisible ? Offset.zero : const Offset(0, -1.1),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: _buildTopBar(settings, isDark),
                    ),
                  ),
                  // Floating bottom bar: Now-Playing controls take over
                  // when audio is active; otherwise hizb/juz/page info.
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedSlide(
                      offset:
                          _barsVisible ? Offset.zero : const Offset(0, 1.1),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: Container(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        child: SafeArea(
                          top: false,
                          child: audio.hasActiveTrack
                              ? _buildNowPlayingBar(isDark, audio)
                              : _buildInfoBar(isDark),
                        ),
                      ),
                    ),
                  ),
                ]),
    ),
    );
  }

  /// Floating app-bar replacement — overlays the text instead of
  /// resizing it, same model as the Mushaf screen.
  Widget _buildTopBar(SettingsService settings, bool isDark) {
    final l = L10n.of(context);
    final bg = isDark ? AppColors.darkBg : AppColors.background;
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;
    return Container(
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.97),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 5),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(children: [
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_back_ios_rounded,
                    size: 16, color: textColor),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.surah.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'QuranHafs',
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: textColor)),
                    Text(
                        '${widget.surah.revelationType == 'Meccan' ? l('meccan') : l('medinan')} • ${l.number(widget.surah.numberOfAyahs)} ${l('ayahUnit')}',
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Almarai',
                            color: isDark
                                ? AppColors.darkTextSec
                                : AppColors.textSecondary)),
                  ]),
            ),
            IconButton(
              tooltip: l('searchInSurah'),
              icon: Icon(Icons.search_rounded, color: textColor),
              onPressed: _showSurahSearch,
            ),
            IconButton(
              icon: Icon(Icons.translate_rounded,
                  color: settings.translationEdition != null
                      ? AppColors.primary
                      : textColor),
              onPressed: () => _showTranslationSheet(settings),
            ),
            IconButton(
              icon: Icon(Icons.text_fields_rounded, color: textColor),
              onPressed: () => _showFontSizeSheet(settings),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildNowPlayingBar(bool isDark, QuranAudioService audio) {
    final l = L10n.of(context);
    final ayah = _ayahs.cast<Ayah?>().firstWhere(
          (a) => a?.number == audio.currentGlobalAyah,
          orElse: () => null,
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          )
        ],
      ),
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
                        ? '${l('ayahWord')} ${l.number(ayah.numberInSurah)}'
                        : '',
                    style: TextStyle(
                      fontFamily: 'Almarai',
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
                        fontFamily: 'Almarai',
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
                  : (isDark
                      ? AppColors.darkTextSec
                      : AppColors.textSecondary),
              size: 20,
            ),
            onPressed: audio.toggleAutoAdvance,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBar(bool isDark) {
    final l = L10n.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${l('hizbWord')} ${l.number(_hizb)}',
              style: TextStyle(
                  color: isDark ? AppColors.darkTextSec : Colors.grey[600],
                  fontSize: 12,
                  fontFamily: 'Almarai')),
          Text('${l('juzWord')} ${l.number(_juz)}',
              style: TextStyle(
                  color: isDark ? AppColors.darkTextSec : Colors.grey[600],
                  fontSize: 12,
                  fontFamily: 'Almarai')),
          Text('${l('pageWord')} ${l.number(_page)}',
              style: TextStyle(
                  color: isDark ? AppColors.darkPrimary : AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Almarai')),
        ],
      ),
    );
  }

  /// Picker for the per-ayah translation language. Selecting an entry
  /// saves the choice and refetches the surah with that edition.
  void _showTranslationSheet(SettingsService settings) {
    final isDark = settings.isDarkIn(context);
    final l = L10n.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        final current = settings.translationEdition;
        Future<void> select(String? edition) async {
          Navigator.pop(sheetCtx);
          if (edition == current) return;
          await settings.setTranslationEdition(edition);
          if (!mounted) return;
          setState(() => _loading = true);
          await _loadAll();
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l('translation'),
                    style: TextStyle(
                      color:
                          isDark ? AppColors.darkText : AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Almarai',
                    )),
                const SizedBox(height: 8),
                RadioGroup<String?>(
                  groupValue: current,
                  onChanged: select,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String?>(
                        value: null,
                        activeColor: AppColors.primary,
                        title: Text(l('noTranslation'),
                            style: TextStyle(
                                fontFamily: 'Almarai',
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.textPrimary)),
                      ),
                      ...QuranService.translationEditions.entries.map(
                        (e) => RadioListTile<String?>(
                          value: e.key,
                          activeColor: AppColors.primary,
                          title: Text(e.value,
                              style: TextStyle(
                                  color: isDark
                                      ? AppColors.darkText
                                      : AppColors.textPrimary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFontSizeSheet(SettingsService settings) {
    final isDark = settings.isDarkIn(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(L10n.of(context)('fontSizeLbl'),
                  style: TextStyle(
                    color: isDark ? AppColors.darkText : AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Almarai',
                  )),
              const SizedBox(height: 20),
              Text('بِسْمِ اللَّهِ',
                  style: TextStyle(
                    fontSize: settings.fontSize,
                    fontFamily: 'Almarai',
                    color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  )),
              Slider(
                value: settings.fontSize,
                min: 18,
                max: 44,
                divisions: 13,
                activeColor:
                    isDark ? AppColors.darkPrimary : AppColors.primary,
                onChanged: (v) {
                  settings.setFontSize(v);
                  setSheet(() {});
                },
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('أ',
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextSec
                            : AppColors.textSecondary)),
                Text('أ',
                    style: TextStyle(
                        fontSize: 22,
                        color: isDark
                            ? AppColors.darkTextSec
                            : AppColors.textSecondary)),
              ]),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSec
                    : AppColors.textSecondary)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _loading = true;
              _error = null;
            });
            _loadAll();
          },
          child: const Text('إعادة المحاولة'),
        ),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// Optional glyph inside the dot (e.g. a bookmark ribbon).
  final IconData? icon;

  const _Dot(
      {required this.name,
      required this.color,
      required this.selected,
      required this.onTap,
      this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border:
              selected ? Border.all(color: AppColors.primary, width: 3) : null,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)
          ],
        ),
        child: name == 'none'
            ? const Icon(Icons.block, color: Colors.white, size: 20)
            : icon != null
                ? Icon(icon, color: Colors.white, size: 18)
                : null,
      ),
    );
  }
}


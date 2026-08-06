import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/surah.dart';
import '../services/library_events.dart';
import '../services/prayer_service.dart';
import '../services/quran_service.dart';
import '../services/settings_service.dart';
import '../services/adhan_notification_service.dart';
import '../theme.dart';
import '../widgets/prayer_visuals.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'mushaf_svg_screen.dart';
import 'prayer_tools_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Surah> _all = [], _filtered = [];

  /// Ayah-text matches shown INLINE below the surah matches — search
  /// happens right here on the home screen, no separate page.
  List<AyahSearchResult> _ayahResults = [];
  Timer? _debounce;

  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  final _scrollController = ScrollController();
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  void _onScroll() {
    final show = _scrollController.hasClients && _scrollController.offset > 360;
    if (show != _showScrollToTop && mounted) {
      setState(() => _showScrollToTop = show);
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await QuranService.getAllSurahs();
      setState(() {
        _all = s;
        _filtered = s;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'فشل تحميل السور\nتحقق من اتصالك';
      });
    }
  }

  void _filter(String q) {
    final query = q.trim();
    // Diacritic- and prefix-insensitive surah filter: the data's names
    // are fully vocalized (سُورَةُ ٱلْفَاتِحَةِ) while users type plain
    // letters — raw contains() almost never matched.
    //
    // The matching itself lives in SurahQuery, shared with
    // QuranService.searchSurahs. This screen used to carry its own copy
    // of the rules, which is how it ended up matching every surah in
    // the Mushaf for a query of "ال".
    final surahQuery = SurahQuery(query);

    setState(() {
      _filtered = query.isEmpty || surahQuery.isEmpty
          ? _all
          : _all.where(surahQuery.matches).toList();
    });

    // Ayah-text search, debounced, results shown inline below.
    _debounce?.cancel();
    if (query.length < 2) {
      setState(() => _ayahResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final res = await QuranService.searchAyahs(query);
      if (!mounted || _search.text.trim() != query) return;
      setState(() => _ayahResults = res.take(30).toList());
    });
  }

  static const Map<int, int> _surahPage = {
    1: 1,
    2: 2,
    3: 50,
    4: 77,
    5: 106,
    6: 128,
    7: 151,
    8: 177,
    9: 187,
    10: 208,
    11: 221,
    12: 235,
    13: 249,
    14: 255,
    15: 262,
    16: 267,
    17: 282,
    18: 293,
    19: 305,
    20: 312,
    21: 322,
    22: 332,
    23: 342,
    24: 350,
    25: 359,
    26: 367,
    27: 377,
    28: 385,
    29: 396,
    30: 404,
    31: 411,
    32: 415,
    33: 418,
    34: 428,
    35: 434,
    36: 440,
    37: 446,
    38: 453,
    39: 458,
    40: 467,
    41: 477,
    42: 483,
    43: 489,
    44: 496,
    45: 499,
    46: 502,
    47: 507,
    48: 511,
    49: 515,
    50: 518,
    51: 520,
    52: 523,
    53: 526,
    54: 528,
    55: 531,
    56: 534,
    57: 537,
    58: 542,
    59: 545,
    60: 549,
    61: 551,
    62: 553,
    63: 554,
    64: 556,
    65: 558,
    66: 560,
    67: 562,
    68: 564,
    69: 566,
    70: 568,
    71: 570,
    72: 572,
    73: 574,
    74: 575,
    75: 577,
    76: 578,
    77: 580,
    78: 582,
    79: 583,
    80: 585,
    81: 586,
    82: 587,
    83: 587,
    84: 589,
    85: 590,
    86: 591,
    87: 591,
    88: 592,
    89: 593,
    90: 593,
    91: 594,
    92: 594,
    93: 595,
    94: 595,
    95: 596,
    96: 596,
    97: 597,
    98: 597,
    99: 598,
    100: 598,
    101: 599,
    102: 599,
    103: 600,
    104: 600,
    105: 600,
    106: 601,
    107: 601,
    108: 602,
    109: 602,
    110: 602,
    111: 603,
    112: 603,
    113: 603,
    114: 604,
  };

  void _openOptions(Surah surah) {
    final l = L10n(context.read<SettingsService>().effectiveLanguage);
    final isDark = context.read<SettingsService>().isDarkIn(context);
    showModalBottomSheet(
      context: context,
      // Without this the sheet is capped at 9/16 of the screen — on a
      // tall phone that window is shorter than this content, so the
      // cards ended up half off the bottom edge. Scroll-controlled, the
      // sheet takes the height its content actually needs.
      //
      // useSafeArea covers the top, left and right only; the navigation
      // bar at the bottom is the SafeArea inside the builder.
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      // Scrollable so the sheet never overflows on short (landscape)
      // screens.
      builder: (_) => SafeArea(
        top: false,
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2))),
            Text(surah.name,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'QuranHafs',
                    color:
                        isDark ? AppColors.darkText : AppColors.textPrimary)),
            Text(
                '${l(surah.revelationType == 'Meccan' ? 'meccan' : 'medinan')} • ${l.number(surah.numberOfAyahs)} ${l('ayahWord')}',
                style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSec
                        : AppColors.textSecondary,
                    fontFamily: '.SF Pro Text')),
            const SizedBox(height: 24),
            // Fixed order in every language: Mushaf on the LEFT, the
            // responsive reader on the RIGHT (pinned LTR so the app
            // language can't reverse them).
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(children: [
                Expanded(
                    child: _ModeBtn(
                        icon: Icons.menu_book_rounded,
                        label: 'المصحف',
                        sub: 'قراءة بالصفحات',
                        color: AppColors.primary,
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => MushafSvgScreen(
                                      startPage:
                                          _surahPage[surah.number] ?? 1)));
                        })),
                const SizedBox(width: 14),
                Expanded(
                    child: _ModeBtn(
                        icon: Icons.format_align_right_rounded,
                        label: 'الآيات',
                        sub: 'قراءة متجاوبة',
                        color: AppColors.accent,
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ReaderScreen(surah: surah)));
                        })),
              ]),
            ),
          ]),
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final isDark = s.isDarkIn(context);
    final theme = Theme.of(context);

    return Scaffold(
      // Pinned LTR so the two icons always sit on fixed sides —
      // settings on the LEFT, day/night toggle on the RIGHT — with the
      // (centered) title unaffected, regardless of the app language.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppBar(
            centerTitle: true,
            leading: IconButton(
                icon: Icon(Icons.settings_rounded,
                    color: theme.colorScheme.primary),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            title: Text(L10n.of(context)('tabIndex'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                  icon: Icon(
                      isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      color: theme.colorScheme.primary),
                  onPressed: () => s.toggleDarkIn(context)),
            ],
          ),
        ),
      ),
      body: Stack(children: [
        Positioned.fill(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                      color: theme.colorScheme.primary))
              : _error != null
                  ? _buildError(theme)
                  : _buildScrollBody(s, isDark, theme),
        ),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: IgnorePointer(
            ignoring: !_showScrollToTop,
            child: AnimatedScale(
              scale: _showScrollToTop ? 1 : 0.72,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: _showScrollToTop ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Semantics(
                  key: const ValueKey('scrollToTopButton'),
                  button: true,
                  label: L10n.of(context)('backToTop'),
                  child: Material(
                    type: MaterialType.circle,
                    color: AppColors.gold,
                    elevation: 5,
                    shadowColor:
                        theme.colorScheme.primary.withValues(alpha: 0.24),
                    child: InkWell(
                      onTap: _scrollToTop,
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 30,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// The whole page scrolls as ONE list — with the date, last-read and
  /// search banners as its leading items. Fixed headers above the list
  /// left no room for the surah list at all on short (landscape)
  /// screens.
  Widget _buildScrollBody(SettingsService s, bool isDark, ThemeData theme) {
    final headers = <Widget>[
      // Date + last-read share one row (last-read left, date right);
      // without a last-read entry the date card takes the full width.
      // Stacked full-width cards: sharing one row squeezed both and
      // ellipsized their text ("…") on normal phone widths.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _buildHijriDate(isDark),
      ),
      if (s.hasLastRead)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _buildLastRead(s, isDark),
        ),
      _PrayerTimesWithTools(isDark: isDark),
      _buildSearch(isDark),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                  _ayahResults.isEmpty
                      ? '${L10n.of(context).number(_filtered.length)} ${L10n.of(context)('surahUnit')}'
                      : '${L10n.of(context).number(_filtered.length)} ${L10n.of(context)('surahUnit')} • ${L10n.of(context).number(_ayahResults.length)} ${L10n.of(context)('ayahUnit')}',
                  style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextSec
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontFamily: '.SF Pro Text')))),
    ];
    // Inline result layout: headers, then matching surahs, then — when
    // the query also hits ayah text — a section label + ayah results,
    // all in the SAME scrolling list right under the search field.
    final ayahSection = _ayahResults.isEmpty ? 0 : 1 + _ayahResults.length;
    return RefreshIndicator(
      color: theme.colorScheme.primary,
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: headers.length + _filtered.length + ayahSection,
        itemBuilder: (_, i) {
          if (i < headers.length) return headers[i];
          final si = i - headers.length;
          if (si < _filtered.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _tile(_filtered[si], isDark),
            );
          }
          final ai = si - _filtered.length;
          if (ai == 0) {
            return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(L10n.of(context)('ayahResults'),
                        style: TextStyle(
                            color: isDark
                                ? AppColors.darkPrimary
                                : AppColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: '.SF Pro Text'))));
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ayahTile(_ayahResults[ai - 1], isDark),
          );
        },
      ),
    );
  }

  /// An inline ayah-text search result; tapping opens the reader at
  /// that exact ayah.
  Widget _ayahTile(AyahSearchResult r, bool isDark) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border)),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          onTap: () {
            final surah = _all.firstWhere((s) => s.number == r.surahNumber,
                orElse: () => _all.first);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ReaderScreen(
                        surah: surah, targetAyah: r.numberInSurah)));
          },
          title: Text(r.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16,
                  height: 1.8,
                  fontFamily: '.SF Pro Text',
                  color: isDark ? AppColors.darkText : AppColors.textPrimary)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
                '${r.surahName} • ${L10n.of(context)('ayahWord')} ${L10n.of(context).number(r.numberInSurah)}',
                style: TextStyle(
                    color: isDark ? AppColors.darkPrimary : AppColors.primary,
                    fontFamily: 'QuranHafs',
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      );

  /// Today's date in the Hijri (Umm al-Qura) calendar, with the
  /// Gregorian date as a secondary line.
  Widget _buildHijriDate(bool isDark) {
    // Both calendars follow the app language — month and weekday names
    // as well as the digits.
    final l = L10n.of(context);
    final h = HijriCalendar.now();
    final g = DateTime.now();
    final hijriLine = '${l.weekday(g.weekday)} ${l.number(h.hDay)} '
        '${l.hijriMonth(h.hMonth)} ${l.number(h.hYear)} ${l.hijriEra}';
    final gregorianLine = '${l.number(g.day)} '
            '${l.gregorianMonth(g.month)} ${l.number(g.year)} ${l.gregorianEra}'
        .trimRight();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: isDark ? 0.16 : 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.4))),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.calendar_month_rounded,
                color: isDark ? AppColors.gold : const Color(0xFF8A6D00),
                size: 18)),
        const SizedBox(width: 8),
        Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(hijriLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color:
                          isDark ? AppColors.darkText : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: '.SF Pro Text')),
              Text(gregorianLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextSec
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontFamily: '.SF Pro Text')),
            ])),
      ]),
    );
  }

  Widget _buildLastRead(SettingsService s, bool isDark) => GestureDetector(
        onTap: () async {
          if (s.lastSurah != null) {
            final surah = _all.firstWhere((x) => x.number == s.lastSurah,
                orElse: () => _all.first);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        ReaderScreen(surah: surah, targetAyah: s.lastAyah)));
          } else if (s.lastPage != null) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => MushafSvgScreen(startPage: s.lastPage)));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.08),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.25))),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: (isDark ? AppColors.darkPrimary : AppColors.primary)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.auto_stories_rounded,
                    color: isDark ? AppColors.darkPrimary : AppColors.primary,
                    size: 18)),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(L10n.of(context)('lastRead'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isDark
                              ? AppColors.darkPrimary
                              : AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: '.SF Pro Text')),
                  if (s.lastSurah != null)
                    Text(
                        '${L10n.of(context)('surahNo')} ${L10n.of(context).number(s.lastSurah!)}${s.lastAyah != null ? ' · ${L10n.of(context)('ayahWord')} ${L10n.of(context).number(s.lastAyah!)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSec
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontFamily: '.SF Pro Text')),
                ])),
          ]),
        ),
      );

  Widget _buildSearch(bool isDark) => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border)),
        child: Row(children: [
          Icon(Icons.search_rounded, color: Colors.grey[400], size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(
                  controller: _search,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                      color:
                          isDark ? AppColors.darkText : AppColors.textPrimary,
                      fontFamily: '.SF Pro Text'),
                  decoration: InputDecoration(
                      hintText: L10n.of(context)('searchHint'),
                      hintStyle: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSec
                              : AppColors.textLight,
                          fontFamily: '.SF Pro Text',
                          fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14)),
                  onChanged: _filter)),
          if (_search.text.isNotEmpty)
            GestureDetector(
                onTap: () {
                  _search.clear();
                  _filter('');
                },
                child: Icon(Icons.close_rounded,
                    color: Colors.grey[400], size: 18)),
        ]),
      );

  Widget _tile(Surah surah, bool isDark) {
    final meccan = surah.revelationType == 'Meccan';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openOptions(surah),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                    width: 0.8)),
            child: Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      // Gold surah-number badge with a gold ring — the
                      // main pop of the app's accent colour on each card.
                      color: AppColors.gold
                          .withValues(alpha: isDark ? 0.22 : 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.gold
                              .withValues(alpha: isDark ? 0.55 : 0.5),
                          width: 1.2)),
                  child: Center(
                      child: Text(L10n.of(context).number(surah.number),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.gold
                                  : const Color(0xFF8A6D00),
                              fontFamily: '.SF Pro Text')))),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(surah.name,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'QuranHafs',
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                      Text(
                          '${L10n.of(context)('pageWord')} ${L10n.of(context).number(_surahPage[surah.number] ?? 1)}',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? AppColors.darkTextSec
                                  : AppColors.textLight)),
                      const SizedBox(width: 8),
                      Text(
                          '${L10n.of(context).number(surah.numberOfAyahs)} ${L10n.of(context)('ayahWord')}',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? AppColors.darkTextSec
                                  : AppColors.textSecondary)),
                      const SizedBox(width: 6),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: meccan
                                  ? const Color(0xFFE8F5E9)
                                  : const Color(0xFFF3E5F5),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(
                              L10n.of(context)(meccan ? 'meccan' : 'medinan'),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: meccan
                                      ? AppColors.primary
                                      : const Color(0xFF7B1FA2)))),
                    ]),
                  ])),
              const SizedBox(width: 8),
              Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: isDark ? AppColors.darkTextSec : AppColors.textLight,
                  size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: '.SF Pro Text',
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            label: const Text('إعادة المحاولة',
                style: TextStyle(
                    fontFamily: '.SF Pro Text', color: Colors.white))),
      ]));
}

/// Today's five prayer times for the configured city, with the next
/// upcoming prayer highlighted. Until a city is chosen it shows a
/// one-tap prompt that opens the settings screen.
class _PrayerTimesWithTools extends StatelessWidget {
  final bool isDark;
  const _PrayerTimesWithTools({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Stack(children: [
      _PrayerTimesBanner(isDark: isDark),
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: Center(
          child: Semantics(
            button: true,
            label: 'Prayer tools',
            child: Material(
              color: accent,
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(20)),
              clipBehavior: Clip.antiAlias,
              elevation: 2,
              child: InkWell(
                onTap: () => showPrayerTools(context),
                child: SizedBox(
                  width: 28,
                  height: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (_) => Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _PrayerTimesBanner extends StatefulWidget {
  final bool isDark;
  const _PrayerTimesBanner({required this.isDark});

  @override
  State<_PrayerTimesBanner> createState() => _PrayerTimesBannerState();
}

class _PrayerTimesBannerState extends State<_PrayerTimesBanner> {
  PrayerTimes? _times;
  String? _label;
  bool _loaded = false;
  String _lang = 'ar';

  @override
  void initState() {
    super.initState();
    LibraryEvents.prayer.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload when the app language changes (city names / GPS geocoding
    // are language-specific) or on the first build.
    final lang = context.read<SettingsService>().effectiveLanguage;
    if (lang != _lang || !_loaded) {
      _lang = lang;
      _load();
    }
  }

  @override
  void dispose() {
    LibraryEvents.prayer.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final label = await PrayerService.locationLabel(_lang);
      final times = label == null ? null : await PrayerService.getTodayTimes();
      if (!mounted) return;
      setState(() {
        _label = label;
        _times = times;
        _loaded = true;
      });
      if (times != null) {
        await AdhanNotificationService.syncToday(times, _lang);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true); // Offline — hide quietly.
    }
  }

  /// Localizes digits (Arabic-Indic for Arabic, Western otherwise).
  String _digits(String s) {
    if (_lang != 'ar') return s;
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return s
        .split('')
        .map((c) => int.tryParse(c) != null ? d[int.parse(c)] : c)
        .join();
  }

  String _prayerName(L10n l, int i) => [
        l('prayerFajr'),
        l('prayerDhuhr'),
        l('prayerAsr'),
        l('prayerMaghrib'),
        l('prayerIsha'),
      ][i];

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l = L10n.of(context); // also makes this rebuild on lang change
    if (!_loaded) return const SizedBox.shrink();

    // Not configured yet — a one-tap prompt.
    if (_label == null) {
      return GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: (isDark ? AppColors.darkPrimary : AppColors.primary)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (isDark ? AppColors.darkPrimary : AppColors.primary)
                      .withValues(alpha: 0.25))),
          child: Row(children: [
            Icon(Icons.mosque_rounded,
                size: 18,
                color: isDark ? AppColors.darkPrimary : AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(L10n.of(context)('chooseCity'),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 13,
                      color:
                          isDark ? AppColors.darkPrimary : AppColors.primary)),
            ),
          ]),
        ),
      );
    }

    final times = _times;
    if (times == null) return const SizedBox.shrink();
    final next = times.nextPrayerIndex(DateTime.now());
    final accent = isDark ? AppColors.darkPrimary : AppColors.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border)),
      child: Column(children: [
        Row(children: [
          Icon(Icons.mosque_rounded, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${L10n.of(context)('prayerTimes')} — $_label',
                textAlign: TextAlign.start,
                style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color:
                        isDark ? AppColors.darkText : AppColors.textPrimary)),
          ),
        ]),
        const SizedBox(height: 10),
        // Follows the app-language direction: in Arabic the row reads
        // right-to-left (Fajr on the right), in English/German left-to-
        // right (Fajr on the left). Each prayer shows its sun-status
        // icon, name and time.
        Row(
          children: [
            for (var i = 0; i < 5; i++)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                      color: i == next
                          ? accent.withValues(alpha: 0.14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: i == next
                          ? Border.all(color: accent.withValues(alpha: 0.35))
                          : null),
                  child: Column(children: [
                    Icon(PrayerVisuals.icons[i],
                        size: 20,
                        color: i == next
                            ? accent
                            : PrayerVisuals.colors[i]
                                .withValues(alpha: isDark ? 0.9 : 1)),
                    const SizedBox(height: 5),
                    Text(_prayerName(l, i),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 12.5,
                            fontWeight:
                                i == next ? FontWeight.bold : FontWeight.normal,
                            color: i == next
                                ? accent
                                : (isDark
                                    ? AppColors.darkTextSec
                                    : AppColors.textSecondary))),
                    const SizedBox(height: 2),
                    Text(_digits(times.all[i]),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                i == next ? FontWeight.bold : FontWeight.normal,
                            color: i == next
                                ? accent
                                : (isDark
                                    ? AppColors.darkText
                                    : AppColors.textPrimary))),
                  ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

class _ModeBtn extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  const _ModeBtn(
      {required this.icon,
      required this.label,
      required this.sub,
      required this.color,
      required this.isDark,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(children: [
          // The light theme's deep emerald/gold are too dark to read on
          // the dark sheet — swap to their bright dark-theme variants.
          Icon(icon,
              size: 36,
              color: isDark
                  ? (color == AppColors.primary
                      ? AppColors.darkPrimary
                      : AppColors.darkSecondary)
                  : color),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: '.SF Pro Text',
                  color: isDark
                      ? (color == AppColors.primary
                          ? AppColors.darkPrimary
                          : AppColors.darkSecondary)
                      : color)),
          Text(sub,
              style: TextStyle(
                  fontSize: 12,
                  color:
                      isDark ? AppColors.darkTextSec : AppColors.textSecondary,
                  fontFamily: '.SF Pro Text')),
        ]),
      ));
}

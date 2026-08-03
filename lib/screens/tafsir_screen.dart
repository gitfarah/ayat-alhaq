import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ayah_insight_service.dart';
import '../services/mutashabihat_service.dart';
import '../services/quran_service.dart';
import '../services/settings_service.dart';
import '../services/tafsir_service.dart';
import '../theme.dart';

/// The ayah study screen: tafsir plus the linguistic works — الإعراب،
/// التصريف، المعنى، القراءات — and the المتشابهات cross-references.
///
/// Every layer is available both for the ayah as a whole and word by
/// word: the ayah card's words are tappable, and each tab also lists
/// the whole ayah word by word.
class TafsirScreen extends StatefulWidget {
  final int surahNumber;
  final String surahName;
  final int ayahNumber;

  /// The ayah's Arabic text if the caller already has it (reader mode).
  /// Pass null when only the numbers are known (Mushaf mode) — the
  /// screen fetches the text itself.
  final String? ayahText;

  /// Tab to open on: 0 = التفسير, then the [InsightKind]s in order,
  /// 5 = المتشابهات.
  final int initialTab;

  const TafsirScreen({
    super.key,
    required this.surahNumber,
    required this.surahName,
    required this.ayahNumber,
    this.ayahText,
    this.initialTab = 0,
  });

  @override
  State<TafsirScreen> createState() => _TafsirScreenState();
}

class _TafsirScreenState extends State<TafsirScreen>
    with SingleTickerProviderStateMixin {
  // The editions (including Ibn Kathir, As-Saadi and At-Tabari, which
  // come from the tafsir CDN rather than alquran.cloud) live in
  // TafsirService — single source of truth shared with the settings
  // screen's offline-download manager.
  final List<TafsirEdition> _tafsirOptions = TafsirService.editions;

  late final TabController _tabs;

  late int _selectedTafsirId;
  String? _tafsirText;
  String? _ayahText;
  bool _isLoading = true;
  String? _error;

  /// Futures are held in state rather than built inside `build`, so
  /// switching tabs or rebuilding on a theme change doesn't restart a
  /// request and flash the spinner again.
  final Map<InsightKind, Future<_InsightData>> _insights = {};
  Future<List<String>>? _tokens;
  Future<List<_MutashabihaView>>? _similar;

  /// Al-qira'at records "no difference here" for most words; hiding
  /// those by default leaves the handful that actually differ.
  bool _qiraatVariantsOnly = true;

  // Convert number to Arabic numerals
  String _toArabicNumber(int number) {
    const arabicNumbers = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((d) => arabicNumbers[int.parse(d)])
        .join();
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 5),
    );
    _selectedTafsirId = _tafsirOptions.first.id;
    _ayahText = widget.ayahText;
    if (_ayahText == null) _loadAyahText();
    _loadSavedTafsir();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Mushaf mode only knows the surah/ayah NUMBERS — fetch the actual
  /// Arabic text so the ayah card isn't just a label.
  Future<void> _loadAyahText() async {
    try {
      final text = await QuranService.getAyahText(
          widget.surahNumber, widget.ayahNumber);
      if (!mounted) return;
      setState(() => _ayahText = text);
    } catch (_) {
      // Non-fatal — the card falls back to the surah/ayah label.
    }
  }

  Future<void> _loadSavedTafsir() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getInt('preferred_tafsir_id');
    if (savedId != null) {
      final exists = _tafsirOptions.any((t) => t.id == savedId);
      if (exists) {
        setState(() => _selectedTafsirId = savedId);
      }
    }
    _loadTafsir();
  }

  Future<void> _savePreferredTafsir(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('preferred_tafsir_id', id);
  }

  Future<void> _loadTafsir() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final text = await TafsirService.getTafsir(
        widget.surahNumber,
        widget.ayahNumber,
        tafsirId: _selectedTafsirId,
      );
      setState(() {
        _tafsirText = text;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'فشل تحميل التفسير: $e';
        _isLoading = false;
      });
    }
  }

  void _onTafsirChanged(int? newId) {
    if (newId == null || newId == _selectedTafsirId) return;
    setState(() => _selectedTafsirId = newId);
    _savePreferredTafsir(newId);
    _loadTafsir();
  }

  // ---------------------------------------------------------------
  // Insight loading
  // ---------------------------------------------------------------

  Future<_InsightData> _insight(InsightKind kind) =>
      _insights[kind] ??= _fetchInsight(kind);

  /// Runs [f] to completion and reports the outcome as a value/error
  /// pair. `Future.wait` cannot be used to fetch the two volumes
  /// together: when BOTH fail — every request does when the device is
  /// offline — it rejects with the first error and leaves the second
  /// unhandled, which surfaces as a crash-reported async exception.
  static Future<(T?, Object?)> _settle<T>(Future<T> f) async {
    try {
      return (await f, null);
    } catch (e) {
      return (null, e);
    }
  }

  Future<_InsightData> _fetchInsight(InsightKind kind) async {
    // The whole-ayah volume and the word-level volume are independent
    // books — start both, then collect them, rather than fetching one
    // after the other.
    final ayahPending = _settle(AyahInsightService.ayahText(
        kind, widget.surahNumber, widget.ayahNumber));
    final wordsPending = _settle(AyahInsightService.words(
        kind, widget.surahNumber, widget.ayahNumber));

    final (ayahText, _) = await ayahPending;
    final (words, wordsError) = await wordsPending;

    // The failure is carried as data rather than thrown: leaving the
    // screen while a request is in flight would otherwise drop the
    // FutureBuilder that was going to handle the rejection, and the
    // error would resurface as an unhandled async exception.
    return _InsightData(
      ayahText: ayahText,
      words: words ?? const [],
      // An ayah-level parse still reads well on its own, so only report
      // the failure when it left nothing at all to show.
      error: (wordsError != null && ayahText == null) ? wordsError : null,
    );
  }

  Future<List<String>> _wordTokens() => _tokens ??=
      AyahInsightService.wordTokens(widget.surahNumber, widget.ayahNumber);

  Future<List<_MutashabihaView>> _mutashabihat() =>
      _similar ??= _fetchMutashabihat();

  Future<List<_MutashabihaView>> _fetchMutashabihat() async {
    final global = await QuranService.globalAyahNumber(
        widget.surahNumber, widget.ayahNumber);
    if (global == 0) return const [];
    final entries = await MutashabihatService.forGlobalAyah(global);

    final out = <_MutashabihaView>[];
    for (final entry in entries) {
      final runs = <List<AyahSearchResult>>[];
      for (final run in entry.similar) {
        final resolved = <AyahSearchResult>[];
        for (final g in run) {
          final hit = await QuranService.locateGlobalAyah(g);
          if (hit != null) resolved.add(hit);
        }
        // The dataset flags pairs whose resemblance only shows with the
        // next ayah in view; append it when it stays inside the surah.
        if (entry.needsContext && resolved.isNotEmpty) {
          final next = await QuranService.locateGlobalAyah(run.last + 1);
          if (next != null && next.surahNumber == resolved.last.surahNumber) {
            resolved.add(next);
          }
        }
        if (resolved.isNotEmpty) runs.add(resolved);
      }
      if (runs.isNotEmpty) {
        out.add(_MutashabihaView(runs: runs, hasContext: entry.needsContext));
      }
    }
    return out;
  }

  void _retryInsight(InsightKind kind) =>
      setState(() => _insights.remove(kind));

  // ---------------------------------------------------------------
  // Word sheet
  // ---------------------------------------------------------------

  /// Everything the four books say about one word, opened by tapping a
  /// word in the ayah card or in any word list.
  void _showWord(int wordNumber, String word) {
    final isDark = context.read<SettingsService>().isDarkIn(context);
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;
    final accent = isDark ? AppColors.darkPrimary : const Color(0xFF2D6A4F);
    final bodyText = isDark ? AppColors.darkText : Colors.black87;
    final subText =
        isDark ? AppColors.darkTextSec : AppColors.textSecondary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SizedBox(
        height: MediaQuery.of(sheetCtx).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: subText.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              QuranService.fixForQuranFont(word),
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: 'QuranHafs',
                fontSize: 30,
                color: accent,
              ),
            ),
            Text(
              'الكلمة ${_toArabicNumber(wordNumber)} من '
              'سورة ${widget.surahName} — آية ${_toArabicNumber(widget.ayahNumber)}',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 12,
                color: subText,
              ),
            ),
            const SizedBox(height: 8),
            Divider(color: subText.withValues(alpha: 0.15), height: 1),
            Expanded(
              child: FutureBuilder<Map<InsightKind, String>>(
                future: AyahInsightService.forWord(
                    widget.surahNumber, widget.ayahNumber, wordNumber),
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Center(
                        child: CircularProgressIndicator(color: accent));
                  }
                  final data = snap.data ?? const {};
                  if (data.isEmpty) {
                    return _emptyNote(
                        'لا توجد بيانات لهذه الكلمة', subText);
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      for (final kind in InsightKind.values)
                        if (data[kind] != null)
                          _labelledBlock(
                            label: kind.title,
                            child: kind == InsightKind.qiraat
                                ? _qiraatBody(data[kind]!, bodyText, accent,
                                    subText)
                                : _proseText(
                                    AyahInsightService.stripWordPrefix(data[kind]!), bodyText),
                            accent: accent,
                            bodyText: bodyText,
                            isDark: isDark,
                          ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Text helpers
  // ---------------------------------------------------------------

  /// Wraps quoted segments in classed spans so the Html styles below
  /// can color them: «قرآن» quotes and "نقول" in the accent green,
  /// (إيضاحات) parenthetical remarks in gold. This breaks the tafsir's
  /// wall of text into visually distinct voices.
  String _decorateTafsir(String text) {
    var t = text;
    t = t.replaceAllMapped(
        RegExp('«[^»]*»'), (m) => '<span class="q">${m[0]}</span>');
    t = t.replaceAllMapped(
        RegExp('"[^"]*"'), (m) => '<span class="q">${m[0]}</span>');
    t = t.replaceAllMapped(
        RegExp(r'\([^)]*\)'), (m) => '<span class="r">${m[0]}</span>');
    return t;
  }

  // ---------------------------------------------------------------
  // Shared building blocks
  // ---------------------------------------------------------------

  Widget _proseText(String text, Color color, {double size = 16}) => Text(
        text,
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: size,
          height: 1.9,
          color: color,
        ),
      );

  Widget _qiraatBody(
      String content, Color bodyText, Color accent, Color subText) {
    final parts = AyahInsightService.qiraatSegments(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final part in parts) ...[
          if (part.label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  part.label!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
            ),
          _proseText(part.text, bodyText),
        ],
      ],
    );
  }

  /// A titled panel — used for the ayah-level sections and for each
  /// book inside the word sheet.
  Widget _labelledBlock({
    required String label,
    required Widget child,
    required Color accent,
    required Color bodyText,
    required bool isDark,
    String? footnote,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceAlt : const Color(0xFFFBF9F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              label,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          child,
          if (footnote != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                footnote,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 11,
                  color: (isDark ? AppColors.darkTextSec : AppColors.textLight),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// One word's entry in a tab's word list. Tapping it opens the sheet
  /// with all four books for that word.
  Widget _wordCard(WordInsight w, Color accent, Color bodyText, Color subText,
      bool isDark,
      {Widget? body}) {
    return InkWell(
      onTap: () => _showWord(w.wordNumber, w.word),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceAlt : const Color(0xFFFBF9F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _toArabicNumber(w.wordNumber),
                    style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 11,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    QuranService.fixForQuranFont(w.word),
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: 'QuranHafs',
                      fontSize: 22,
                      color: accent,
                    ),
                  ),
                ),
                Icon(Icons.more_horiz_rounded, size: 18, color: subText),
              ],
            ),
            const SizedBox(height: 8),
            body ?? _proseText(AyahInsightService.stripWordPrefix(w.content), bodyText),
          ],
        ),
      ),
    );
  }

  Widget _emptyNote(String message, Color subText) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 40, color: subText),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 14,
                color: subText,
              ),
            ),
          ],
        ),
      );

  Widget _errorNote(String message, VoidCallback onRetry, Color accent) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontFamily: '.SF Pro Text', fontSize: 14),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: '.SF Pro Text')),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------
  // Tabs
  // ---------------------------------------------------------------

  Widget _tafsirTab(
      Color cardBg, Color accent, Color bodyText, bool isDark) {
    return ListView(
      key: const PageStorageKey('tafsir'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedTafsirId,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down, color: accent),
              dropdownColor: cardBg,
              borderRadius: BorderRadius.circular(12),
              style: TextStyle(
                color: bodyText,
                fontSize: 15,
                fontFamily: '.SF Pro Text',
              ),
              items: _tafsirOptions.map((tafsir) {
                return DropdownMenuItem<int>(
                  value: tafsir.id,
                  child: Text(
                    tafsir.name,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                  ),
                );
              }).toList(),
              onChanged: _onTafsirChanged,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator(color: accent)),
          )
        else if (_error != null)
          _errorNote(_error!, _loadTafsir, accent)
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? Colors.black : Colors.grey)
                      .withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Html(
              data: _decorateTafsir(_tafsirText ?? 'لا يوجد تفسير'),
              style: {
                "body": Style(
                  fontSize: FontSize(17),
                  lineHeight: const LineHeight(2.0),
                  textAlign: TextAlign.right,
                  direction: TextDirection.rtl,
                  fontFamily: '.SF Pro Text',
                  color: bodyText,
                  margin: Margins.zero,
                ),
                "p": Style(
                  margin: Margins.only(bottom: 12),
                  textAlign: TextAlign.right,
                ),
                "h1": Style(
                  fontSize: FontSize(18),
                  fontWeight: FontWeight.bold,
                  color: accent,
                  margin: Margins.only(top: 16, bottom: 8),
                  textAlign: TextAlign.right,
                ),
                "h2": Style(
                  fontSize: FontSize(16),
                  fontWeight: FontWeight.bold,
                  color: accent,
                  margin: Margins.only(top: 12, bottom: 6),
                  textAlign: TextAlign.right,
                ),
                "span": Style(color: bodyText),
                // «Qur'anic quotes» and "cited sayings"
                ".q": Style(color: accent, fontWeight: FontWeight.bold),
                // (parenthetical remarks / glosses)
                ".r": Style(
                  color:
                      isDark ? AppColors.darkSecondary : AppColors.secondary,
                ),
              },
            ),
          ),
      ],
    );
  }

  Widget _insightTab(
      InsightKind kind, Color accent, Color bodyText, Color subText,
      bool isDark) {
    return FutureBuilder<_InsightData>(
      key: PageStorageKey('insight-${kind.name}'),
      future: _insight(kind),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: accent));
        }
        final data = snap.data!;
        if (data.error != null) {
          return ListView(children: [
            _errorNote('${data.error}'.replaceFirst('Exception: ', ''),
                () => _retryInsight(kind), accent)
          ]);
        }
        var words = data.words.where((w) => w.content.isNotEmpty).toList();
        final isQiraat = kind == InsightKind.qiraat;
        final hiddenAgreements = isQiraat && _qiraatVariantsOnly
            ? words.where((w) => !AyahInsightService.qiraatHasVariance(w.content)).length
            : 0;
        if (isQiraat && _qiraatVariantsOnly) {
          words = words.where((w) => AyahInsightService.qiraatHasVariance(w.content)).toList();
        }

        if (data.ayahText == null && words.isEmpty && hiddenAgreements == 0) {
          return ListView(children: [
            _emptyNote('لا تتوفر بيانات ${kind.title} لهذه الآية', subText)
          ]);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (data.ayahText != null)
              _labelledBlock(
                label: '${kind.title} — الآية كاملة',
                accent: accent,
                bodyText: bodyText,
                isDark: isDark,
                footnote: kind.source,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in AyahInsightService.eerabLines(data.ayahText!))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _proseText(line, bodyText),
                      ),
                  ],
                ),
              ),
            if (isQiraat)
              Align(
                alignment: Alignment.centerRight,
                child: FilterChip(
                  selected: _qiraatVariantsOnly,
                  showCheckmark: true,
                  label: const Text(
                    'مواضع الخلاف فقط',
                    textDirection: TextDirection.rtl,
                    style:
                        TextStyle(fontFamily: '.SF Pro Text', fontSize: 12),
                  ),
                  selectedColor: accent.withValues(alpha: 0.15),
                  checkmarkColor: accent,
                  onSelected: (v) =>
                      setState(() => _qiraatVariantsOnly = v),
                ),
              ),
            if (words.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${kind.title} كلمةً كلمة',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: subText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final w in words)
                _wordCard(w, accent, bodyText, subText, isDark,
                    body: isQiraat
                        ? _qiraatBody(w.content, bodyText, accent, subText)
                        : null),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'المصدر: ${kind.source}',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 11,
                    color: subText,
                  ),
                ),
              ),
            ] else if (isQiraat && hiddenAgreements > 0)
              _emptyNote(
                  'لا خلاف بين القراء في كلمات هذه الآية', subText),
          ],
        );
      },
    );
  }

  Widget _mutashabihatTab(
      Color accent, Color bodyText, Color subText, bool isDark) {
    return FutureBuilder<List<_MutashabihaView>>(
      key: const PageStorageKey('mutashabihat'),
      future: _mutashabihat(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: accent));
        }
        final views = snap.data ?? const <_MutashabihaView>[];
        if (views.isEmpty) {
          return ListView(children: [
            _emptyNote(
                'لا توجد مواضع متشابهة مسجَّلة لهذه الآية.\n'
                'الفهرس يجمع المواضع المشتبهة التي يكثر التباسها على الحفّاظ، '
                'لا كل تكرار في القرآن.',
                subText)
          ]);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            for (final view in views)
              for (final run in view.runs)
                _similarCard(run, view.hasContext, accent, bodyText, subText,
                    isDark),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'المصدر: فهرس المتشابهات — مبني على عمل القارئ إدريس العاصم',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 11,
                  color: subText,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _similarCard(List<AyahSearchResult> run, bool hasContext, Color accent,
      Color bodyText, Color subText, bool isDark) {
    final first = run.first;
    // Surah names from the bundled text already read «سُورَةُ ...», so
    // no "سورة" is prefixed here — that would say it twice.
    final label = run.length == 1
        ? '${first.surahName} — آية ${_toArabicNumber(first.numberInSurah)}'
        : '${first.surahName} — الآيات '
            '${_toArabicNumber(first.numberInSurah)}'
            '-${_toArabicNumber(run.last.numberInSurah)}';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      // Jumping to the match opens the same study screen on it, so the
      // reader can compare the two wordings side by side.
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TafsirScreen(
            surahNumber: first.surahNumber,
            surahName: first.surahName,
            ayahNumber: first.numberInSurah,
            initialTab: 5,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceAlt : const Color(0xFFFBF9F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: Text(
                    label,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                ),
                Icon(Icons.chevron_left_rounded, size: 20, color: subText),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < run.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  run[i].text,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: 'QuranHafs',
                    fontSize: 20,
                    height: 1.9,
                    // A context ayah is shown to make the resemblance
                    // legible, not as part of the match itself.
                    color: (hasContext && i == run.length - 1 && run.length > 1)
                        ? subText
                        : bodyText,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Ayah card
  // ---------------------------------------------------------------

  /// The ayah at the top of the screen. Once the word list has loaded
  /// each word becomes tappable; until then the plain text is shown, so
  /// the card never sits empty waiting on the network.
  Widget _ayahCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Same green the options-sheet header uses — a verse quoted
        // back to the reader looks the same wherever it appears.
        color: AppColors.ayahPanel,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          FutureBuilder<List<String>>(
            future: _wordTokens(),
            builder: (ctx, snap) {
              final tokens = snap.data;
              if (tokens == null || tokens.isEmpty) {
                return Text(
                  _ayahText ??
                      '${widget.surahName} ${_toArabicNumber(widget.ayahNumber)}',
                  textAlign:
                      _ayahText != null ? TextAlign.right : TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.8,
                    color: Colors.white,
                    fontFamily: 'QuranHafs',
                  ),
                );
              }
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    for (var i = 0; i < tokens.length; i++)
                      InkWell(
                        onTap: () => _showWord(i + 1, tokens[i]),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18)),
                          ),
                          child: Text(
                            QuranService.fixForQuranFont(tokens[i]),
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontSize: 22,
                              height: 1.8,
                              color: Colors.white,
                              fontFamily: 'QuranHafs',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'سورة ${widget.surahName} - آية ${_toArabicNumber(widget.ayahNumber)}',
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'QuranHafs',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'اضغط على أي كلمة لعرض إعرابها وتصريفها ومعناها وقراءاتها',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontFamily: '.SF Pro Text',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkIn(context);
    final bg = isDark ? AppColors.darkBg : const Color(0xFFF5F0EB);
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;
    final accent = isDark ? AppColors.darkPrimary : const Color(0xFF2D6A4F);
    final bodyText = isDark ? AppColors.darkText : Colors.black87;
    final subText = isDark ? AppColors.darkTextSec : AppColors.textSecondary;

    // Reading surfaces keep their original fixed layout (RTL content,
    // LTR-positioned chrome) regardless of the app's UI language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          leading: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceAlt : Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios, color: accent, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          title: Text(
            '${widget.surahName} - ${_toArabicNumber(widget.ayahNumber)}',
            style: TextStyle(
              color: bodyText,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              fontFamily: 'QuranHafs',
            ),
          ),
          centerTitle: true,
        ),
        // The ayah card scrolls away under a pinned tab bar: the longest
        // ayahs (e.g. 2:282) are taller than the screen on their own, so
        // it cannot be a fixed header.
        body: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [
            SliverToBoxAdapter(child: _ayahCard()),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarHeader(
                background: bg,
                child: TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.black,
                  indicatorColor: Colors.transparent,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  labelStyle: const TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 14,
                  ),
                  tabs: [
                    for (final label in const [
                      'التفسير',
                      'الإعراب',
                      'التصريف',
                      'المعنى',
                      'القراءات',
                      'المتشابهات',
                    ])
                      Tab(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(label),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabs,
            children: [
              _tafsirTab(cardBg, accent, bodyText, isDark),
              _insightTab(InsightKind.eerab, accent, bodyText, subText, isDark),
              _insightTab(
                  InsightKind.tasreef, accent, bodyText, subText, isDark),
              _insightTab(
                  InsightKind.meaning, accent, bodyText, subText, isDark),
              _insightTab(InsightKind.qiraat, accent, bodyText, subText, isDark),
              _mutashabihatTab(accent, bodyText, subText, isDark),
            ],
          ),
        ),
      ),
    );
  }
}

/// One book's answer for an ayah: the whole-ayah volume (where it
/// exists) plus the word-level entries.
class _InsightData {
  final String? ayahText;
  final List<WordInsight> words;

  /// Set when the fetch failed and left nothing to render, so the tab
  /// can offer a retry. See [_TafsirScreenState._fetchInsight] for why
  /// this is a field rather than a rejected future.
  final Object? error;

  const _InsightData({
    required this.ayahText,
    required this.words,
    this.error,
  });
}

/// A mutashabiha with its matching runs already resolved to text.
class _MutashabihaView {
  final List<List<AyahSearchResult>> runs;
  final bool hasContext;

  const _MutashabihaView({required this.runs, required this.hasContext});
}

/// Keeps the tab bar pinned below the scrolled-away ayah card.
class _TabBarHeader extends SliverPersistentHeaderDelegate {
  final TabBar child;
  final Color background;

  const _TabBarHeader({required this.child, required this.background});

  @override
  double get minExtent => child.preferredSize.height;

  @override
  double get maxExtent => child.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        color: background,
        // The screen's chrome stays LTR (see the ayah screen's own
        // note), but the tab labels are Arabic study terms — this
        // local RTL override puts التفسير first from the right, the
        // natural reading order, without touching the tab indices used
        // by TabBarView and initialTab elsewhere in this file.
        child: Directionality(textDirection: TextDirection.rtl, child: child),
      );

  @override
  bool shouldRebuild(_TabBarHeader old) =>
      old.child != child || old.background != background;
}

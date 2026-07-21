import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/quran_service.dart';
import '../services/settings_service.dart';
import '../services/tafsir_service.dart';
import '../theme.dart';

class TafsirScreen extends StatefulWidget {
  final int surahNumber;
  final String surahName;
  final int ayahNumber;

  /// The ayah's Arabic text if the caller already has it (reader mode).
  /// Pass null when only the numbers are known (Mushaf mode) — the
  /// screen fetches the text itself.
  final String? ayahText;

  const TafsirScreen({
    super.key,
    required this.surahNumber,
    required this.surahName,
    required this.ayahNumber,
    this.ayahText,
  });

  @override
  State<TafsirScreen> createState() => _TafsirScreenState();
}

class _TafsirScreenState extends State<TafsirScreen> {
  // The editions (including Ibn Kathir, As-Saadi and At-Tabari, which
  // come from the tafsir CDN rather than alquran.cloud) live in
  // TafsirService — single source of truth shared with the settings
  // screen's offline-download manager.
  final List<TafsirEdition> _tafsirOptions = TafsirService.editions;

  late int _selectedTafsirId;
  String? _tafsirText;
  String? _ayahText;
  bool _isLoading = true;
  String? _error;

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
    _selectedTafsirId = _tafsirOptions.first.id;
    _ayahText = widget.ayahText;
    if (_ayahText == null) _loadAyahText();
    _loadSavedTafsir();
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkIn(context);
    final bg = isDark ? AppColors.darkBg : const Color(0xFFF5F0EB);
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;
    final accent =
        isDark ? AppColors.darkPrimary : const Color(0xFF2D6A4F);
    final bodyText = isDark ? AppColors.darkText : Colors.black87;

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
            fontFamily: 'Amiri',
          ),
        ),
        centerTitle: true,
      ),
      // ONE scroll view for the whole page: the longest ayahs (e.g.
      // 2:282) are taller than the screen on their own, so a fixed
      // ayah card left no room for the tafsir at all.
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Ayah card at top
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F),
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
                Text(
                  _ayahText ??
                      '${widget.surahName} ${_toArabicNumber(widget.ayahNumber)}',
                  textAlign: _ayahText != null
                      ? TextAlign.right
                      : TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.8,
                    color: Colors.white,
                    fontFamily: 'Amiri',
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'سورة ${widget.surahName} - آية ${_toArabicNumber(widget.ayahNumber)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tafsir selector dropdown
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
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
                  fontFamily: 'Amiri',
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

          const SizedBox(height: 8),

          // Tafsir content — scrolls together with the ayah card above.
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: accent)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadTafsir,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          else
            Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
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
                        child: SingleChildScrollView(
                          child: Html(
                            data: _decorateTafsir(
                                _tafsirText ?? 'لا يوجد تفسير'),
                            style: {
                              "body": Style(
                                fontSize: FontSize(17),
                                lineHeight: const LineHeight(2.0),
                                textAlign: TextAlign.right,
                                direction: TextDirection.rtl,
                                fontFamily: 'Amiri',
                                color: bodyText,
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
                              "span": Style(
                                color: bodyText,
                              ),
                              // «Qur'anic quotes» and "cited sayings"
                              ".q": Style(
                                color: accent,
                                fontWeight: FontWeight.bold,
                              ),
                              // (parenthetical remarks / glosses)
                              ".r": Style(
                                color: isDark
                                    ? AppColors.darkSecondary
                                    : AppColors.secondary,
                              ),
                            },
                          ),
                        ),
                      ),
        ],
      ),
    ),
    );
  }
}

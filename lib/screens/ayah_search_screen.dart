import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/surah.dart';
import '../services/quran_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'mushaf_reader_screen.dart';

/// Full-text search across all ayahs and surah names — the WHOLE
/// Quran, every time. Used identically from the home screen, the
/// Mushaf and the reader, so a search means the same thing and reaches
/// the same results no matter which screen it was opened from.
///
/// By default tapping a result opens it in [MushafReaderScreen]. Pass
/// [returnResultToCaller] to instead pop the picked [AyahSearchResult]
/// back to the caller — what the Mushaf and the reader both do, so
/// picking a result can jump to it IN PLACE (the same page, the same
/// edition, the same open surah) instead of always leaving for the
/// reader.
class AyahSearchScreen extends StatefulWidget {
  final String initialQuery;
  final bool returnResultToCaller;
  const AyahSearchScreen({
    super.key,
    this.initialQuery = '',
    this.returnResultToCaller = false,
  });

  @override
  State<AyahSearchScreen> createState() => _AyahSearchScreenState();
}

class _AyahSearchScreenState extends State<AyahSearchScreen> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<AyahSearchResult> _results = [];
  List<Surah> _surahResults = [];
  bool _searching = false;
  bool _searchedOnce = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty) _search(widget.initialQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(q));
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _surahResults = [];
        _searchedOnce = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      // Surah-name matches surface FIRST — typing a surah's name should
      // find the surah itself, not just ayahs containing those words.
      final results = await Future.wait([
        QuranService.searchSurahs(q),
        QuranService.searchAyahs(q),
      ]);
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _surahResults = results[0] as List<Surah>;
        _results = results[1] as List<AyahSearchResult>;
        _searching = false;
        _searchedOnce = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchedOnce = true;
        _error = 'تعذّر البحث، تحقق من اتصالك بالإنترنت';
      });
    }
  }

  Future<void> _open(AyahSearchResult r) async {
    if (widget.returnResultToCaller) {
      Navigator.pop(context, r);
      return;
    }
    try {
      final surahs = await QuranService.getAllSurahs();
      final surah = surahs.firstWhere((s) => s.number == r.surahNumber);
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MushafReaderScreen(
                  targetSurah: surah.number, targetAyah: r.numberInSurah)));
    } catch (_) {}
  }

  String _ar(int n) {
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

  /// A matched surah — shown above ayah matches with a distinct accent
  /// so "typing a surah name" visibly finds the surah itself.
  Widget _surahTile(Surah s, bool isDark) {
    final primary = isDark ? AppColors.darkPrimary : AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      // Material, not a plain Container+BoxDecoration: ListTile paints
      // its background tint and tap ripple on the nearest Material
      // ancestor, so a colour sitting on a Container ABOVE it (as this
      // used to) makes both invisible — caught by Flutter's own debug
      // assertion once a widget test actually rendered this tile.
      child: Material(
        color: isDark ? AppColors.darkSurface : Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: primary.withValues(alpha: 0.55))),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          onTap: () {
            // Same contract as an ayah result: a caller that asked for
            // the result back (the Mushaf, the reader) gets it back —
            // opening the reader directly here would silently break
            // out of whichever mode the search was opened from. Ayah 1
            // stands in for "the surah itself", the same as tapping its
            // home-screen card would land on.
            if (widget.returnResultToCaller) {
              Navigator.pop(
                  context,
                  AyahSearchResult(
                      surahNumber: s.number,
                      surahName: s.name,
                      numberInSurah: 1,
                      text: ''));
              return;
            }
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => MushafReaderScreen(
                        targetSurah: s.number, targetAyah: 1)));
          },
          leading: Icon(Icons.menu_book_rounded, color: primary, size: 22),
          title: Text(s.name,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'QuranHafs',
                  color: isDark ? AppColors.darkText : AppColors.textPrimary)),
          subtitle: Text(
              '${s.revelationType == 'Meccan' ? 'مكية' : 'مدنية'} • ${_ar(s.numberOfAyahs)} آية',
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextSec
                      : AppColors.textSecondary)),
          trailing: Icon(Icons.chevron_left_rounded,
              color: isDark ? AppColors.darkTextSec : AppColors.textSecondary,
              size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkIn(context);
    final subColor = isDark ? AppColors.darkTextSec : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('البحث في الآيات')),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border)),
          child: Row(children: [
            _searching
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color:
                            isDark ? AppColors.darkPrimary : AppColors.primary))
                : Icon(Icons.search_rounded, color: Colors.grey[400], size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: _controller,
                    autofocus: widget.initialQuery.isEmpty,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color:
                            isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontFamily: '.SF Pro Text'),
                    decoration: InputDecoration(
                        hintText: 'اكتب كلمة أو جزءاً من آية...',
                        hintTextDirection: TextDirection.rtl,
                        hintStyle: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSec
                                : AppColors.textLight,
                            fontFamily: '.SF Pro Text',
                            fontSize: 14),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14)),
                    onChanged: _onChanged,
                    onSubmitted: _search)),
          ]),
        ),
        if (_searchedOnce && _error == null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                      '${_ar(_surahResults.length + _results.length)} نتيجة',
                      style: TextStyle(
                          color: subColor,
                          fontSize: 13,
                          fontFamily: '.SF Pro Text')))),
        Expanded(
          child: _error != null
              ? Center(
                  child: Text(_error!,
                      style: TextStyle(
                          color: subColor, fontFamily: '.SF Pro Text')))
              : (_searchedOnce &&
                      _results.isEmpty &&
                      _surahResults.isEmpty &&
                      !_searching)
                  ? Center(
                      child: Text('لا توجد نتائج',
                          style: TextStyle(
                              color: subColor,
                              fontSize: 16,
                              fontFamily: '.SF Pro Text')))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _surahResults.length + _results.length,
                      itemBuilder: (_, i) {
                        if (i < _surahResults.length) {
                          return _surahTile(_surahResults[i], isDark);
                        }
                        final r = _results[i - _surahResults.length];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          // Material, not Container+BoxDecoration — see
                          // the identical note on _surahTile above; the
                          // same bug was duplicated in this tile too.
                          child: Material(
                            color:
                                isDark ? AppColors.darkSurface : Colors.white,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                    color: isDark
                                        ? AppColors.darkBorder
                                        : AppColors.border)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              onTap: () => _open(r),
                              title: Text(r.text,
                                  textDirection: TextDirection.rtl,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 16,
                                      height: 1.8,
                                      fontFamily: 'QuranHafs',
                                      color: isDark
                                          ? AppColors.darkText
                                          : AppColors.textPrimary)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                    '${r.surahName} • الآية ${_ar(r.numberInSurah)}',
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                        color: isDark
                                            ? AppColors.darkPrimary
                                            : AppColors.primary,
                                        fontFamily: 'QuranHafs',
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ),
                              trailing: Icon(Icons.chevron_left_rounded,
                                  color: subColor, size: 18),
                            ),
                          ),
                        );
                      }),
        ),
      ]),
    );
  }
}

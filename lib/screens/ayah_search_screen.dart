import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/surah.dart';
import '../services/quran_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'reader_screen.dart';

/// Full-text search across all ayahs. Opened from the home screen's
/// search box; tapping a result jumps straight to that ayah in the
/// reader.
class AyahSearchScreen extends StatefulWidget {
  final String initialQuery;
  const AyahSearchScreen({super.key, this.initialQuery = ''});

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
    try {
      final surahs = await QuranService.getAllSurahs();
      final surah = surahs.firstWhere((s) => s.number == r.surahNumber);
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ReaderScreen(surah: surah, targetAyah: r.numberInSurah)));
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
      decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primary.withValues(alpha: 0.55))),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ReaderScreen(surah: s))),
        leading: Icon(Icons.menu_book_rounded, color: primary, size: 22),
        title: Text(s.name,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Almarai',
                color: isDark ? AppColors.darkText : AppColors.textPrimary)),
        subtitle: Text(
            '${s.revelationType == 'Meccan' ? 'مكية' : 'مدنية'} • ${_ar(s.numberOfAyahs)} آية',
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                fontFamily: 'Almarai',
                fontSize: 13,
                color:
                    isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
        trailing: Icon(Icons.chevron_left_rounded,
            color: isDark ? AppColors.darkTextSec : AppColors.textSecondary,
            size: 18),
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
                        color: isDark
                            ? AppColors.darkPrimary
                            : AppColors.primary))
                : Icon(Icons.search_rounded,
                    color: Colors.grey[400], size: 20),
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
                        fontFamily: 'Almarai'),
                    decoration: InputDecoration(
                        hintText: 'اكتب كلمة أو جزءاً من آية...',
                        hintTextDirection: TextDirection.rtl,
                        hintStyle: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSec
                                : AppColors.textLight,
                            fontFamily: 'Almarai',
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
                          fontFamily: 'Almarai')))),
        Expanded(
          child: _error != null
              ? Center(
                  child: Text(_error!,
                      style: TextStyle(color: subColor, fontFamily: 'Almarai')))
              : (_searchedOnce &&
                      _results.isEmpty &&
                      _surahResults.isEmpty &&
                      !_searching)
                  ? Center(
                      child: Text('لا توجد نتائج',
                          style: TextStyle(
                              color: subColor,
                              fontSize: 16,
                              fontFamily: 'Almarai')))
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
                          decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkSurface
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
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
                                      fontFamily: 'Almarai',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                            trailing: Icon(Icons.chevron_left_rounded,
                                color: subColor, size: 18),
                          ),
                        );
                      }),
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../services/bookmark_service.dart';
import '../services/library_events.dart';
import '../services/quran_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'mushaf_svg_screen.dart';
import 'reader_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});
  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Bookmark> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // This screen lives inside MainScreen's IndexedStack and is never
    // re-created on tab switches, so reload whenever a bookmark is
    // added/removed anywhere in the app (reader, mushaf, etc.).
    LibraryEvents.bookmarks.addListener(_load);
  }

  @override
  void dispose() {
    LibraryEvents.bookmarks.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final b = await BookmarkService.getAllBookmarks();
    if (!mounted) return;
    setState(() {
      _items = b;
      _loading = false;
    });
  }

  Future<void> _delete(Bookmark b) async {
    await BookmarkService.deleteBookmarkByAyah(b.surahNumber, b.ayahNumber);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L10n.of(context)('deletedBookmark'))));
    }
  }

  Future<void> _open(Bookmark b) async {
    try {
      // Return to the mode the mark was made in.
      if (b.isFromMushaf) {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MushafSvgScreen(startPage: b.page)));
        await _load();
        return;
      }
      final surahs = await QuranService.getAllSurahs();
      final s = surahs.firstWhere((x) => x.number == b.surahNumber);
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ReaderScreen(surah: s, targetAyah: b.ayahNumber)));
      await _load();
    } catch (_) {}
  }

  String _date(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year.toString().substring(2)}';

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkIn(context);
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l('tabBookmarks')),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
                onPressed: _confirmClear,
                child: Text(l('clearAll'),
                    style: const TextStyle(
                        color: Colors.red, fontFamily: 'ScheherazadeNew', fontSize: 13))),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _items.isEmpty
              ? _empty(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final b = _items[i];
                    return Dismissible(
                      key: Key('bm_${b.surahNumber}_${b.ayahNumber}'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _delete(b),
                      background: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                              color: Colors.red.shade400,
                              borderRadius: BorderRadius.circular(14)),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          child: const Icon(Icons.delete_rounded,
                              color: Colors.white)),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                            color:
                                isDark ? AppColors.darkSurface : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: isDark
                                    ? AppColors.darkBorder
                                    : AppColors.border)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          onTap: () => _open(b),
                          leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                  color: AppColors.highlight(b.color)
                                      .withValues(alpha: 0.18),
                                  shape: BoxShape.circle),
                              child: Icon(Icons.bookmark_rounded,
                                  color: AppColors.highlight(b.color),
                                  size: 24)),
                          title: Text(b.surahName,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'ScheherazadeNew',
                                  color: isDark
                                      ? AppColors.darkText
                                      : AppColors.textPrimary)),
                          subtitle: Text(
                              '${l('ayahWord')} ${l.number(b.ayahNumber)} • ${_date(b.createdAt)}',
                              textDirection: l.isArabic
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                              style: TextStyle(
                                  color: isDark
                                      ? AppColors.darkTextSec
                                      : AppColors.textSecondary,
                                  fontFamily: 'ScheherazadeNew',
                                  fontSize: 13)),
                          trailing: Icon(Icons.chevron_left_rounded,
                              color: isDark
                                  ? AppColors.darkTextSec
                                  : AppColors.textLight),
                        ),
                      ),
                    );
                  }),
    );
  }

  void _confirmClear() {
    final l = L10n.of(context);
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(l('clearBookmarksTitle')),
              content: Text(l('clearBookmarksBody')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l('cancel'))),
                ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () async {
                      Navigator.pop(context);
                      await BookmarkService.clearAll();
                      await _load();
                    },
                    child: Text(l('deleteAll'),
                        style: const TextStyle(color: Colors.white))),
              ],
            ));
  }

  Widget _empty(bool isDark) {
    final l = L10n.of(context);
    return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.bookmark_border_rounded,
            size: 72,
            color: isDark ? AppColors.darkTextSec : Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(l('noBookmarks'),
            style: TextStyle(
                fontSize: 18,
                fontFamily: 'ScheherazadeNew',
                color:
                    isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
        const SizedBox(height: 8),
        Text(l('noBookmarksHint'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isDark ? AppColors.darkTextSec : AppColors.textLight,
                fontFamily: 'ScheherazadeNew',
                fontSize: 13)),
      ]));
  }
}
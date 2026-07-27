import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../services/highlight_service.dart';
import '../services/library_events.dart';
import '../services/quran_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'mushaf_svg_screen.dart';
import 'reader_screen.dart';

class HighlightsScreen extends StatefulWidget {
  const HighlightsScreen({super.key});
  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  List<Highlight> _items = [];
  bool _loading = true;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
    // This screen lives inside MainScreen's IndexedStack and is never
    // re-created on tab switches, so reload whenever a highlight is
    // added/removed anywhere in the app (reader, mushaf, etc.).
    LibraryEvents.highlights.addListener(_load);
  }

  @override
  void dispose() {
    LibraryEvents.highlights.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final h = await HighlightService.getAllHighlights();
    if (!mounted) return;
    setState(() {
      _items = h;
      _loading = false;
    });
  }

  List<Highlight> get _shown => _filter == null
      ? _items
      : _items.where((h) => h.color == _filter).toList();

  Future<void> _open(Highlight h) async {
    try {
      // Return to the mode the mark was made in.
      if (h.isFromMushaf) {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MushafSvgScreen(startPage: h.page)));
        await _load();
        return;
      }
      final surahs = await QuranService.getAllSurahs();
      final s = surahs.firstWhere((x) => x.number == h.surahNumber);
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ReaderScreen(surah: s, targetAyah: h.ayahNumber)));
      await _load();
    } catch (_) {}
  }

  Future<void> _delete(Highlight h) async {
    await HighlightService.deleteHighlight(h.surahNumber, h.ayahNumber);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L10n.of(context)('deletedHighlight'))));
    }
  }

  static String _colorName(L10n l, String key) => switch (key) {
        'yellow' => l('colYellow'),
        'green' => l('colGreen'),
        'blue' => l('colBlue'),
        'pink' => l('colPink'),
        'purple' => l('colPurple'),
        _ => key,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkIn(context);
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l('tabHighlights'))),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                  color: isDark ? AppColors.darkPrimary : AppColors.primary))
          : Column(children: [
              if (_items.isNotEmpty) _filterBar(isDark, l),
              Expanded(
                  child: _shown.isEmpty
                      ? _empty(isDark)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _shown.length,
                          itemBuilder: (_, i) {
                            final h = _shown[i];
                            final hc = AppColors.highlight(h.color);
                            return Dismissible(
                              key: Key('hl_${h.surahNumber}_${h.ayahNumber}'),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => _delete(h),
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
                                      horizontal: 16, vertical: 8),
                                  onTap: () => _open(h),
                                  leading: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                          color: hc.withValues(alpha: 0.35),
                                          shape: BoxShape.circle,
                                          border:
                                              Border.all(color: hc, width: 2)),
                                      child: Icon(Icons.highlight_rounded,
                                          color: hc.withValues(alpha: 0.9),
                                          size: 22)),
                                  title: Text(h.surahName,
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'ScheherazadeNew',
                                          color: isDark
                                              ? AppColors.darkText
                                              : AppColors.textPrimary)),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                          '${l('ayahWord')} ${l.number(h.ayahNumber)} • ${_colorName(l, h.color)}',
                                          textDirection: l.isArabic
                                              ? TextDirection.rtl
                                              : TextDirection.ltr,
                                          style: TextStyle(
                                              color: isDark
                                                  ? AppColors.darkTextSec
                                                  : AppColors.textSecondary,
                                              fontFamily: 'ScheherazadeNew',
                                              fontSize: 13)),
                                      _AyahPreview(
                                          surahNumber: h.surahNumber,
                                          ayahNumber: h.ayahNumber,
                                          isDark: isDark),
                                    ],
                                  ),
                                  trailing: Icon(Icons.chevron_left_rounded,
                                      color: isDark
                                          ? AppColors.darkTextSec
                                          : AppColors.textLight),
                                ),
                              ),
                            );
                          })),
            ]),
    );
  }

  Widget _filterBar(bool isDark, L10n l) => SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _Chip(
              label: l('all'),
              color:
                  isDark ? AppColors.darkTextSec : AppColors.textSecondary,
              selected: _filter == null,
              onTap: () => setState(() => _filter = null)),
          ...AppColors.highlights.entries.map((e) => _Chip(
              label: _colorName(l, e.key),
              color: e.value,
              selected: _filter == e.key,
              onTap: () => setState(() => _filter = e.key))),
        ],
      ));

  Widget _empty(bool isDark) {
    final l = L10n.of(context);
    return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.highlight_outlined,
            size: 72,
            color: isDark ? AppColors.darkTextSec : Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(l('noHighlights'),
            style: TextStyle(
                fontSize: 18,
                fontFamily: 'ScheherazadeNew',
                color:
                    isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
        const SizedBox(height: 8),
        Text(l('noHighlightsHint'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isDark ? AppColors.darkTextSec : AppColors.textLight,
                fontFamily: 'ScheherazadeNew',
                fontSize: 13)),
      ]));
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.color,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
        onTap: onTap,
        child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected
                        ? color
                        : (isDark
                            ? AppColors.darkBorder
                            : Colors.grey.shade300))),
            child: Text(label,
                style: TextStyle(
                    color: selected
                        ? color
                        : (isDark
                            ? AppColors.darkTextSec
                            : AppColors.textSecondary),
                    fontFamily: 'ScheherazadeNew',
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal))));
  }
}

/// Shows the highlighted ayah's actual TEXT under the list entry so the
/// user recognizes it without opening the surah. Fetched lazily and
/// cached app-wide (highlights only store surah/ayah numbers).
class _AyahPreview extends StatelessWidget {
  final int surahNumber;
  final int ayahNumber;
  final bool isDark;
  const _AyahPreview(
      {required this.surahNumber,
      required this.ayahNumber,
      required this.isDark});

  static final Map<String, String> _cache = {};

  Future<String> _load() async {
    final key = '$surahNumber:$ayahNumber';
    final cached = _cache[key];
    if (cached != null) return cached;
    final text = await QuranService.getAyahText(surahNumber, ayahNumber);
    _cache[key] = text;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _load(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          // Loading or offline — the entry stays usable without it.
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            snap.data!,
            textAlign: TextAlign.start,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'ScheherazadeNew',
              fontSize: 15,
              height: 1.7,
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
            ),
          ),
        );
      },
    );
  }
}
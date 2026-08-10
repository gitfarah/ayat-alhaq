import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/ayah_share_service.dart';
import '../services/settings_service.dart';
import '../services/tafsir_service.dart';
import '../theme.dart';
import 'ayah_sheet_header.dart';

/// Lets the reader share an ayah as plain text or as a rendered card,
/// with the tafsir folded in or left out.
///
/// The tafsir is fetched only if it is actually wanted — opening this
/// sheet on a verse should not cost a network call the reader never
/// asked for.
Future<void> showAyahShareSheet(
  BuildContext context, {
  required int surahNumber,
  required String surahName,
  required int ayahNumber,
  required String ayahText,

  /// Pre-fetched tafsir, when the caller already has it on screen (the
  /// tafsir screen does). Null elsewhere — the sheet fetches on demand.
  String? tafsirText,
  String? tafsirName,
  int? tafsirId,
}) {
  final isDark = context.read<SettingsService>().isDarkIn(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _AyahShareSheet(
      surahNumber: surahNumber,
      surahName: surahName,
      ayahNumber: ayahNumber,
      ayahText: ayahText,
      tafsirText: tafsirText,
      tafsirName: tafsirName,
      tafsirId: tafsirId,
      isDark: isDark,
    ),
  );
}

class _AyahShareSheet extends StatefulWidget {
  final int surahNumber;
  final String surahName;
  final int ayahNumber;
  final String ayahText;
  final String? tafsirText;
  final String? tafsirName;
  final int? tafsirId;
  final bool isDark;

  const _AyahShareSheet({
    required this.surahNumber,
    required this.surahName,
    required this.ayahNumber,
    required this.ayahText,
    required this.tafsirText,
    required this.tafsirName,
    required this.tafsirId,
    required this.isDark,
  });

  @override
  State<_AyahShareSheet> createState() => _AyahShareSheetState();
}

class _AyahShareSheetState extends State<_AyahShareSheet> {
  bool _withTafsir = false;
  bool _busy = false;

  String? _fetchedTafsir;
  String? _fetchedTafsirName;

  String _ar(int n) {
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

  /// The tafsir to share, fetching it the first time it is wanted.
  /// Returns null when it could not be had — the caller then shares the
  /// verse alone rather than failing outright.
  Future<(String, String)?> _tafsir() async {
    if (widget.tafsirText?.trim().isNotEmpty ?? false) {
      return (widget.tafsirText!, widget.tafsirName ?? 'التفسير');
    }
    if (_fetchedTafsir != null) {
      return (_fetchedTafsir!, _fetchedTafsirName ?? 'التفسير');
    }
    try {
      final id = widget.tafsirId ?? TafsirService.editions.first.id;
      final edition =
          TafsirService.editionById(id) ?? TafsirService.editions.first;
      final text = await TafsirService.getTafsir(
          widget.surahNumber, widget.ayahNumber,
          tafsirId: edition.id);
      if (text.trim().isEmpty) return null;
      _fetchedTafsir = text;
      _fetchedTafsirName = edition.name;
      return (text, edition.name);
    } catch (_) {
      return null;
    }
  }

  Future<ShareableAyah> _payload() async {
    String? tafsirText;
    String? tafsirName;
    if (_withTafsir) {
      final t = await _tafsir();
      if (t != null) {
        tafsirText = t.$1;
        tafsirName = t.$2;
      }
    }
    return ShareableAyah(
      surahNumber: widget.surahNumber,
      surahName: widget.surahName,
      ayahNumber: widget.ayahNumber,
      ayahText: widget.ayahText,
      tafsirText: tafsirText,
      tafsirName: tafsirName,
    );
  }

  Future<void> _share({required bool asImage}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final payload = await _payload();
      if (asImage) {
        await AyahShareService.shareImage(payload);
      } else {
        await AyahShareService.shareText(payload);
      }
      if (mounted) navigator.pop();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(l('shareFailed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isDark = widget.isDark;
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;
    final accent = isDark ? AppColors.darkPrimary : AppColors.primary;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AyahSheetHeader(
              ayahText: widget.ayahText,
              label: '${widget.surahName} — آية ${_ar(widget.ayahNumber)}',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _withTafsir,
                    activeThumbColor: accent,
                    onChanged:
                        _busy ? null : (v) => setState(() => _withTafsir = v),
                    title: Text(l('shareIncludeTafsir'),
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                            fontFamily: '.SF Pro Text', color: textColor)),
                    secondary:
                        Icon(Icons.menu_book_rounded, color: accent),
                  ),
                  const SizedBox(height: 8),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: accent),
                          const SizedBox(height: 12),
                          Text(l('shareLoadingImage'),
                              style: TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontSize: 13,
                                  color: isDark
                                      ? AppColors.darkTextSec
                                      : AppColors.textSecondary)),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _ShareButton(
                            icon: Icons.text_fields_rounded,
                            label: l('shareAsText'),
                            filled: false,
                            isDark: isDark,
                            onTap: () => _share(asImage: false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ShareButton(
                            icon: Icons.image_rounded,
                            label: l('shareAsImage'),
                            filled: true,
                            isDark: isDark,
                            onTap: () => _share(asImage: true),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool isDark;
  final VoidCallback onTap;

  const _ShareButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.darkPrimary : AppColors.primary;
    final fg = filled ? Colors.white : accent;
    return Material(
      color: filled ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: accent.withValues(alpha: 0.5), width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

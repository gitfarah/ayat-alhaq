import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../services/highlight_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';

/// Note editor for a single marked ayah, shared by the Mushaf, the
/// responsive reader and the Highlights tab so a note reads and edits
/// the same everywhere.
///
/// Notes belong to the colour mark: writing one on an ayah that isn't
/// marked yet creates the mark (see [HighlightService.setNote]), so the
/// user never has to mark first and write second.
///
/// Returns true when the note was saved or cleared, false on cancel.
Future<bool> showAyahNoteSheet(
  BuildContext context, {
  required int surahNumber,
  required int ayahNumber,
  required String surahName,
  int? page,
  String? ayahText,
}) async {
  final existing =
      await HighlightService.getHighlight(surahNumber, ayahNumber);
  if (!context.mounted) return false;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NoteSheet(
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      surahName: surahName.isNotEmpty ? surahName : (existing?.surahName ?? ''),
      page: page ?? existing?.page,
      ayahText: ayahText,
      initialNote: existing?.note ?? '',
      color: existing?.color,
    ),
  );
  return saved ?? false;
}

/// The saved note rendered inline under an ayah — a tinted card in the
/// mark's own colour so it reads as a margin note on that mark.
class AyahNoteCard extends StatelessWidget {
  final String note;
  final Color color;
  final bool isDark;
  final bool isArabic;
  final VoidCallback? onTap;
  final int? maxLines;

  const AyahNoteCard({
    super.key,
    required this.note,
    required this.color,
    required this.isDark,
    required this.isArabic,
    this.onTap,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;
    return GestureDetector(
      onTap: onTap,
      child: Directionality(
        // Lays the colour spine on the side the note is read FROM.
        textDirection: dir,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.14 : 0.12),
            borderRadius: BorderRadius.circular(10),
            // Uniform: a per-side border cannot carry a radius. The
            // thicker spine is a child strip instead.
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.sticky_note_2_rounded,
                              size: 14,
                              color: isDark
                                  ? AppColors.darkTextSec
                                  : AppColors.textSecondary),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note,
                            textDirection: dir,
                            maxLines: maxLines,
                            overflow: maxLines == null
                                ? TextOverflow.clip
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: '.SF Pro Text',
                              fontSize: 13.5,
                              height: 1.5,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NoteSheet extends StatefulWidget {
  final int surahNumber;
  final int ayahNumber;
  final String surahName;
  final int? page;
  final String? ayahText;
  final String initialNote;
  final String? color;

  const _NoteSheet({
    required this.surahNumber,
    required this.ayahNumber,
    required this.surahName,
    required this.page,
    required this.ayahText,
    required this.initialNote,
    required this.color,
  });

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialNote);
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _hadNote => widget.initialNote.trim().isNotEmpty;

  Future<void> _save({bool clear = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    await HighlightService.setNote(
      widget.surahNumber,
      widget.ayahNumber,
      note: clear ? null : _ctrl.text,
      surahName: widget.surahName,
      page: widget.page,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkIn(context);
    final l = L10n.of(context);
    final accent = isDark ? AppColors.darkPrimary : AppColors.primary;
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;
    final markColor = AppColors.highlight(widget.color ?? 'yellow');

    return Padding(
      // Lift the sheet above the keyboard so the field stays visible.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: markColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: markColor.withValues(alpha: 0.7))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.surahName} • ${l('ayahWord')} ${l.number(widget.ayahNumber)}',
                      textDirection:
                          l.isArabic ? TextDirection.rtl : TextDirection.ltr,
                      style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textColor),
                    ),
                  ),
                ]),
                if (widget.ayahText != null &&
                    widget.ayahText!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    widget.ayahText!,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'QuranHafs',
                        fontSize: 17,
                        height: 1.8,
                        color: textColor),
                  ),
                ],
                const Divider(height: 24),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  maxLines: 6,
                  minLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  textDirection:
                      l.isArabic ? TextDirection.rtl : TextDirection.ltr,
                  style: TextStyle(
                      fontFamily: '.SF Pro Text', fontSize: 15, color: textColor),
                  decoration: InputDecoration(
                    hintText: l('noteHint'),
                    hintStyle: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 14,
                        color: isDark
                            ? AppColors.darkTextSec
                            : AppColors.textLight),
                    filled: true,
                    fillColor: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  if (_hadNote)
                    TextButton.icon(
                      onPressed: _saving ? null : () => _save(clear: true),
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 20, color: Colors.red.shade400),
                      label: Text(l('deleteNote'),
                          style: TextStyle(
                              fontFamily: '.SF Pro Text',
                              color: Colors.red.shade400)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    child: Text(l('cancel'),
                        style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            color: isDark
                                ? AppColors.darkTextSec
                                : AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(),
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    child: Text(l('save'),
                        style: const TextStyle(fontFamily: '.SF Pro Text')),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

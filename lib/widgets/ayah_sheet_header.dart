import 'package:flutter/material.dart';

import '../theme.dart';
import 'mushaf_verse_text.dart';

/// The green panel at the top of an ayah's options sheet: the ayah
/// itself, centred and in the Mushaf face, so the sheet opens on the
/// verse rather than on its number.
///
/// Uses the same green the tafsir screen presents an ayah on — a verse
/// quoted back to the reader looks the same wherever it appears.
///
/// Shared by both reading surfaces (the Mushaf page view and the
/// verse-by-verse reader) so the same tap gives the same panel.
class AyahSheetHeader extends StatelessWidget {
  /// The ayah's text. Null while it is still being fetched — the panel
  /// then shows [label] alone rather than flashing empty.
  final String? ayahText;

  /// Where the ayah sits, e.g. "النساء — آية ١".
  final String label;

  /// Optional: lets the panel quietly upgrade [ayahText] to the
  /// Mushaf's own printed glyphs once they load. Omit either (as every
  /// caller did before this existed) and the panel renders exactly as
  /// it always has, on [ayahText] alone.
  final int? surahNumber;
  final int? ayahNumber;

  // The panel is the same green in light and dark: it is a quoted
  // verse, not a piece of the surrounding surface.

  const AyahSheetHeader({
    super.key,
    required this.ayahText,
    required this.label,
    this.surahNumber,
    this.ayahNumber,
  });

  @override
  Widget build(BuildContext context) {
    final text = ayahText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.ayahPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          if (text != null && text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              // Ornate Quranic brackets (﴿ ... ﴾) around the quoted
              // verse — the convention printed Mushafs and tafsir pages
              // use to set an ayah off from surrounding text. The bidi
              // algorithm does not mirror these (they are already
              // direction-correct glyphs), so source order is display
              // order: written ﴿ first, ﴾ last, so that with RTL text
              // direction ﴿ (the OPENING bracket, despite its Unicode
              // name "ornate RIGHT parenthesis") lands on the right —
              // where Arabic reading starts — and ﴾ closes on the left.
              child: MushafVerseText(
                surahNumber: surahNumber,
                ayahNumbers: ayahNumber != null ? [ayahNumber!] : null,
                fallbackText: text,
                ornateBrackets: true,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                // A few ayahs run for a whole page; the sheet shows the
                // opening of one rather than growing to swallow it.
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'QuranHafs',
                  fontSize: 20,
                  height: 1.9,
                  color: Colors.white,
                ),
              ),
            ),
          Text(
            label,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: 'QuranHafs',
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

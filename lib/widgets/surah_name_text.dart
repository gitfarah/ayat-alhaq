import 'package:flutter/material.dart';

/// The calligraphic name of a surah, SET rather than typed.
///
/// [QUL_Surah_Name_V4] is a ligature font: the ASCII string "surah005"
/// becomes the single calligraphic "سُورَةُ المَائِدَة" a printed Mushaf
/// heads its pages with. It carries the 114 names and the page ornament
/// and nothing else — no ordinary letters — so it must never be used for
/// arbitrary text.
///
/// This is the same font and the same ligature the V4 Mushaf sets its
/// page headers in, which is the point: a surah is named identically
/// wherever the app names it — index, reader band, Mushaf page, share
/// card.
class SurahNameText extends StatelessWidget {
  /// 1-114.
  final int surahNumber;
  final double fontSize;
  final Color color;
  final TextAlign? textAlign;

  const SurahNameText({
    super.key,
    required this.surahNumber,
    required this.fontSize,
    required this.color,
    this.textAlign,
  });

  /// The ligature key for [surahNumber] — "surah001" … "surah114".
  static String glyph(int surahNumber) =>
      'surah${surahNumber.toString().padLeft(3, '0')}';

  @override
  Widget build(BuildContext context) => Text(
        glyph(surahNumber),
        textAlign: textAlign,
        // The ligature resolves to a right-to-left Arabic name, but the
        // KEY is ASCII: laid out RTL so it sits where the name belongs
        // in the surrounding Arabic layout.
        textDirection: TextDirection.rtl,
        maxLines: 1,
        style: TextStyle(
          fontFamily: 'QUL_Surah_Name_V4',
          fontSize: fontSize,
          color: color,
          // Without this the ASCII key can render as literal Latin
          // "surah001" instead of the name.
          fontFeatures: const [FontFeature.enable('liga')],
          // The names' ink sits well inside the em box; a text face's
          // default leading would print them adrift of their line.
          height: 1.0,
        ),
      );
}

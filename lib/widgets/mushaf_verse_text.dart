import 'package:flutter/material.dart';

import '../services/mushaf_glyph_service.dart';

/// Quotes one or more ayahs the way [AyahShareService]'s card does: in
/// the Mushaf's own printed glyphs when they can be had, falling back
/// to the app's reflowing body font (Amiri, family 'QuranHafs')
/// otherwise — and starting on that fallback immediately, never
/// blocking a sheet or a page on a font download.
///
/// [surahNumber]/[ayahNumbers] are OPTIONAL. Leave them null to render
/// [fallbackText] only and never attempt the upgrade — the caller may
/// not always know which ayah is on screen (a stale cache entry, a
/// reference that failed to resolve), and this must still show
/// something rather than nothing. When both are given, the widget
/// quietly swaps in the real glyphs if and when they arrive.
class MushafVerseText extends StatefulWidget {
  final int? surahNumber;

  /// In reading order. A single ayah is `[n]`. Null/empty means never
  /// attempt the upgrade, same as a null [surahNumber].
  final List<int>? ayahNumbers;

  /// The real Unicode text to show while the glyphs are unavailable —
  /// UNBRACKETED; pass [ornateBrackets] to have this widget add them,
  /// so the same convention applies to both the fallback and the
  /// upgraded rendering rather than only to one of them.
  final String fallbackText;

  /// Wraps the quote in ﴿ ﴾ — the convention a printed Mushaf/tafsir
  /// sets a verse off from surrounding text with — in [style]'s own
  /// font, on both the fallback text and the glyph run.
  final bool ornateBrackets;

  /// fontFamily is used for the fallback text and for the brackets;
  /// fontSize/height/color apply to the glyph run too.
  final TextStyle style;

  final TextAlign? textAlign;
  final TextDirection textDirection;
  final int? maxLines;
  final TextOverflow? overflow;

  const MushafVerseText({
    super.key,
    this.surahNumber,
    this.ayahNumbers,
    required this.fallbackText,
    this.ornateBrackets = false,
    required this.style,
    this.textAlign,
    this.textDirection = TextDirection.rtl,
    this.maxLines,
    this.overflow,
  });

  @override
  State<MushafVerseText> createState() => _MushafVerseTextState();
}

class _MushafVerseTextState extends State<MushafVerseText> {
  List<MushafGlyphRun>? _runs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MushafVerseText old) {
    super.didUpdateWidget(old);
    // A sheet is normally built fresh per ayah, but a screen that
    // reuses one instance while navigating between ayahs (the tafsir
    // screen's "next ayah" arrow, say) must not keep quoting the
    // PREVIOUS ayah's glyphs under the new fallback text.
    if (old.surahNumber != widget.surahNumber ||
        !_sameAyahs(old.ayahNumbers, widget.ayahNumbers)) {
      setState(() => _runs = null);
      _load();
    }
  }

  static bool _sameAyahs(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _load() {
    final surah = widget.surahNumber;
    final ayahs = widget.ayahNumbers;
    if (surah == null || ayahs == null || ayahs.isEmpty) return;
    MushafGlyphService.runsFor(surah, ayahs).then((runs) {
      if (mounted && runs != null && runs.isNotEmpty) {
        setState(() => _runs = runs);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final runs = _runs;
    final Widget child;
    if (runs == null) {
      final text = widget.ornateBrackets
          ? '﴿${widget.fallbackText}﴾'
          : widget.fallbackText;
      child = Text(
        text,
        key: const ValueKey('mushaf-verse-fallback'),
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        style: widget.style,
      );
    } else {
      child = Text.rich(
        TextSpan(
          style: widget.style,
          children: [
            if (widget.ornateBrackets) const TextSpan(text: '﴿'),
            for (final r in runs)
              TextSpan(
                text: r.glyphs,
                style: TextStyle(fontFamily: r.fontFamily),
              ),
            if (widget.ornateBrackets) const TextSpan(text: '﴾'),
          ],
        ),
        key: const ValueKey('mushaf-verse-glyphs'),
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }
    // A quiet upgrade, not a jump cut: the glyphs usually land a beat
    // after the sheet has already opened on the fallback text.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: child,
    );
  }
}

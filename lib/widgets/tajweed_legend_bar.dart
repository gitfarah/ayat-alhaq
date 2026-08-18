import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../services/tajweed_service.dart';
import '../theme.dart';

/// The dot + label naming every tajweed rule, wrapped across as many
/// lines as it takes to show ALL of them — not a scrolling strip that
/// only reveals a few at a time. Shared by Settings' own legend and the
/// on-page [TajweedLegendBar] below, so there is exactly one place that
/// knows the rule list and colours; a reader who has seen it in one
/// place recognises it in the other.
///
/// The colours here are this app's own, already-reviewed set. They are
/// NOT read back out of the KFGQPC V4 tajweed font's own palette: no
/// source at qul.tarteel.ai (font page, docs, or blog) publishes a
/// rule→colour key for that font's specific hues, checked by hand
/// before building this, and printed colour-coded Mushafs are well
/// known to vary their exact palette by publisher anyway. So on a V4
/// GLYPH page this legend is a general key to the same tajweed
/// categories the font is colouring — not a pixel-exact reading of
/// that particular font's palette — while on the reflowed page the
/// colours it names are the literal ones on screen.
class TajweedLegendChips extends StatelessWidget {
  final String lang;
  final Color textColor;
  final WrapAlignment alignment;

  const TajweedLegendChips({
    super.key,
    required this.lang,
    required this.textColor,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final names = TajweedService.ruleNames[lang] ?? TajweedService.ruleNames['ar']!;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: alignment,
      children: [
        for (final rule in TajweedService.legendOrder)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: TajweedService.ruleColors[rule],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              names[rule] ?? TajweedService.ruleNames['ar']![rule]!,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontFamily: '.SF Pro Text', fontSize: 13, color: textColor),
            ),
          ]),
      ],
    );
  }
}

/// The on-page version of [TajweedLegendChips]: collapsible, since the
/// full legend runs to several lines and a reader mid-verse may want
/// the space back rather than the key.
///
/// [expanded]/[onToggle] are owned by the CALLER rather than kept as
/// private state here: the ayah-by-ayah reader has to know whether this
/// is showing its full, multi-line height or just its collapsed header
/// row so it can reserve enough bottom padding in its scrolling list —
/// otherwise the last visible ayah ends up partly hidden behind this
/// bar rather than scrolled clear of it, which a purely-private
/// expand/collapse flag would leave no way to detect.
class TajweedLegendBar extends StatelessWidget {
  final bool isDark;
  final bool expanded;
  final VoidCallback onToggle;

  const TajweedLegendBar({
    super.key,
    required this.isDark,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().effectiveLanguage;
    final textColor = isDark ? AppColors.darkText : AppColors.textPrimary;
    final dim = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final ground = isDark ? AppColors.darkSurface : Colors.white;

    return Container(
      color: ground,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ألوان التجويد',
                    style: TextStyle(
                        fontFamily: '.SF Pro Text', fontSize: 12, color: dim)),
                Icon(
                    expanded
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    size: 18,
                    color: dim),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: TajweedLegendChips(
              lang: lang,
              textColor: textColor,
              alignment: WrapAlignment.center,
            ),
          ),
      ]),
    );
  }
}

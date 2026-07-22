import 'package:flutter/material.dart';
import '../services/quran_audio_service.dart';
import '../theme.dart';

/// Bottom-sheet reciter list. Returns true when a reciter was picked
/// (or was already chosen), false if the sheet was dismissed.
Future<bool> showReciterPicker(
    BuildContext context, QuranAudioService audio, bool isDark) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2))),
            Text('اختر القارئ',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontFamily: 'ScheherazadeNew',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkText : AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('يبقى هذا الاختيار محفوظاً حتى تغيّره',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontFamily: 'ScheherazadeNew',
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSec
                        : AppColors.textSecondary)),
            const SizedBox(height: 8),
            for (final e in QuranAudioService.reciters.entries)
              ListTile(
                dense: true,
                onTap: () => Navigator.pop(context, e.key),
                trailing: e.key == audio.reciter
                    ? Icon(Icons.check_circle_rounded,
                        color:
                            isDark ? AppColors.darkPrimary : AppColors.primary,
                        size: 20)
                    : null,
                title: Text(e.value,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontFamily: 'ScheherazadeNew',
                        fontSize: 16,
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.textPrimary)),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked != null) {
    await audio.setReciter(picked);
    return true;
  }
  return false;
}

/// Guarantees a reciter has been explicitly chosen before playback:
/// the picker appears only the very first time audio is used, then the
/// choice sticks until the user opens the picker again on purpose.
Future<bool> ensureReciterChosen(
    BuildContext context, QuranAudioService audio, bool isDark) async {
  if (audio.hasChosenReciter) return true;
  return showReciterPicker(context, audio, isDark);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';

/// The scrubber, the elapsed time and the word-by-word highlight all
/// read QuranAudioService.positionStream, which maps the player's
/// position through this. When clipping was introduced for the two QUL
/// reciters, the "no clip" case was folded into the same branch as
/// "before the clip starts" and returned zero — so position never
/// advanced for ANY reciter, on any device.
void main() {
  group('clipRelative', () {
    test('passes the position through when nothing is clipped', () {
      // The ordinary case on a phone: the file IS the ayah, and a
      // ClippingAudioSource already reports clip-relative positions.
      for (final ms in [0, 1, 250, 3000, 60000]) {
        final p = Duration(milliseconds: ms);
        expect(QuranAudioService.clipRelative(p, null), p);
      }
    });

    test('advances, rather than staying at zero, as playback runs', () {
      final positions = [
        for (var ms = 0; ms <= 5000; ms += 500)
          QuranAudioService.clipRelative(Duration(milliseconds: ms), null)
      ];
      expect(positions.last, const Duration(seconds: 5));
      expect(positions.toSet().length, positions.length,
          reason: 'every tick must differ — a frozen scrubber is the bug');
    });

    test('subtracts the clip start when a clip is set', () {
      const start = Duration(seconds: 10);
      expect(QuranAudioService.clipRelative(const Duration(seconds: 12), start),
          const Duration(seconds: 2));
      expect(QuranAudioService.clipRelative(const Duration(seconds: 10), start),
          Duration.zero);
    });

    test('clamps to zero before the clip starts', () {
      const start = Duration(seconds: 10);
      expect(QuranAudioService.clipRelative(const Duration(seconds: 4), start),
          Duration.zero);
      expect(QuranAudioService.clipRelative(Duration.zero, start),
          Duration.zero);
    });
  });
}

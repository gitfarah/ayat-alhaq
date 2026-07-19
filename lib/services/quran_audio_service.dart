import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plays per-ayah Quran recitation (Mishary Al-Afasy) from the
/// alquran.cloud CDN, with a secondary host as fallback if the primary
/// is unreachable. Ayah numbers here are always the GLOBAL sequential
/// number (1-6236, matching Ayah.number), not the per-surah number.
///
/// Works on web too: although cdn.islamic.network sends no CORS
/// headers, playback goes through an HTML `<audio>` element, and
/// browsers allow media elements to PLAY cross-origin sources without
/// CORS — CORS only blocks scripts from READING the audio bytes,
/// which we never do.
class QuranAudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  /// Verse-by-verse reciters available on cdn.islamic.network, verified
  /// against /edition?format=audio&type=versebyverse. Most editions
  /// exist at 128kbps; the few that don't are covered by the 64kbps
  /// fallback in [playAyah].
  static const Map<String, String> reciters = {
    'ar.alafasy': 'مشاري العفاسي',
    'ar.husary': 'محمود خليل الحصري',
    'ar.abdulsamad': 'عبدالباسط عبدالصمد',
    'ar.abdurrahmaansudais': 'عبدالرحمن السديس',
    'ar.mahermuaiqly': 'ماهر المعيقلي',
    'ar.saoodshuraym': 'سعود الشريم',
    'ar.hudhaify': 'علي الحذيفي',
    'ar.muhammadayyoub': 'محمد أيوب',
    'ar.shaatree': 'أبو بكر الشاطري',
    'ar.ahmedajamy': 'أحمد العجمي',
  };

  String _reciter = 'ar.alafasy';
  String get reciter => _reciter;
  String get reciterName => reciters[_reciter] ?? _reciter;

  Future<void> setReciter(String id) async {
    if (!reciters.containsKey(id) || id == _reciter) return;
    _reciter = id;
    (await SharedPreferences.getInstance()).setString('reciterEdition', id);
    // A currently-playing ayah keeps the old voice until it ends;
    // anything played after this uses the new reciter.
    notifyListeners();
  }

  int? _currentGlobalAyah;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _autoAdvance = true;
  String? _error;

  int? get currentGlobalAyah => _currentGlobalAyah;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get autoAdvance => _autoAdvance;
  String? get error => _error;
  bool get hasActiveTrack => _currentGlobalAyah != null;

  /// The UI (ReaderScreen) sets this so the service can figure out what
  /// "next ayah" means for auto-advance without hardcoding surah logic
  /// here. Given the currently-playing global ayah number, return the
  /// next global ayah number to play, or null to stop (e.g. end of surah).
  int? Function(int currentGlobalAyah)? nextAyahResolver;

  QuranAudioService() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) => _handleComplete());
    _loadReciter();
  }

  Future<void> _loadReciter() async {
    final saved = (await SharedPreferences.getInstance())
        .getString('reciterEdition');
    if (saved != null && reciters.containsKey(saved)) {
      _reciter = saved;
      notifyListeners();
    }
  }

  Future<void> playAyah(int globalAyahNumber) async {
    _isLoading = true;
    _error = null;
    _currentGlobalAyah = globalAyahNumber;
    notifyListeners();

    // 128kbps first; 64kbps covers editions the CDN only has at the
    // lower bitrate; the alquran.cloud media host is the last resort.
    final urls = [
      'https://cdn.islamic.network/quran/audio/128/$_reciter/$globalAyahNumber.mp3',
      'https://cdn.islamic.network/quran/audio/64/$_reciter/$globalAyahNumber.mp3',
      'https://cdn.alquran.cloud/media/audio/ayah/$_reciter/$globalAyahNumber',
    ];
    var played = false;
    for (final url in urls) {
      try {
        await _player.play(UrlSource(url));
        played = true;
        break;
      } catch (_) {
        // Try the next source.
      }
    }
    if (!played) {
      _isLoading = false;
      _currentGlobalAyah = null;
      _error = 'تعذّر تشغيل التلاوة، تحقق من اتصالك بالإنترنت';
      notifyListeners();
      return;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> togglePlayPause(int globalAyahNumber) async {
    if (_currentGlobalAyah == globalAyahNumber && _isPlaying) {
      await _player.pause();
    } else if (_currentGlobalAyah == globalAyahNumber && !_isPlaying) {
      await _player.resume();
    } else {
      await playAyah(globalAyahNumber);
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _currentGlobalAyah = null;
    _isPlaying = false;
    notifyListeners();
  }

  void toggleAutoAdvance() {
    _autoAdvance = !_autoAdvance;
    notifyListeners();
  }

  Future<void> _handleComplete() async {
    if (_autoAdvance &&
        nextAyahResolver != null &&
        _currentGlobalAyah != null) {
      final next = nextAyahResolver!(_currentGlobalAyah!);
      if (next != null) {
        await playAyah(next);
        return;
      }
    }
    _currentGlobalAyah = null;
    _isPlaying = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

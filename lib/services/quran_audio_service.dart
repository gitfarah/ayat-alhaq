import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quran_page_meta.dart';

/// Plays per-ayah Quran recitation from the alquran.cloud CDN.
/// Ayah numbers here are always the GLOBAL sequential number (1-6236,
/// matching Ayah.number), not the per-surah number.
///
/// Download-first playback (mobile/desktop): when an ayah is played,
/// its mp3 is downloaded to local storage and played from disk, and the
/// REST of that surah's ayahs are downloaded in the background — so
/// auto-advance to the next ayah is instant and keeps working even if
/// the connection drops mid-surah. On web there is no filesystem, so
/// ayahs stream directly (browsers allow cross-origin media playback).
class QuranAudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  /// Verse-by-verse reciters available on cdn.islamic.network, verified
  /// against /edition?format=audio&type=versebyverse. Most editions
  /// exist at 128kbps; the few that don't are covered by the 64kbps
  /// fallback.
  static const Map<String, String> reciters = {
    'ar.husary': 'محمود خليل الحصري',
    'ar.abdulsamad': 'عبدالباسط عبدالصمد',
    'ar.mahermuaiqly': 'ماهر المعيقلي',
    'ar.saoodshuraym': 'سعود الشريم',
    'ar.hudhaify': 'علي الحذيفي',
    'ar.muhammadayyoub': 'محمد أيوب',
    'ar.shaatree': 'أبو بكر الشاطري',
    'ar.ahmedajamy': 'أحمد العجمي',
  };

  static const String _defaultReciter = 'ar.husary';

  String _reciter = _defaultReciter;
  String get reciter => _reciter;
  String get reciterName => reciters[_reciter] ?? _reciter;

  /// Whether the user has ever explicitly picked a reciter. The UI
  /// shows the reciter list ONCE — on the first play — then sticks to
  /// the choice until the user opens the picker again on purpose.
  bool _reciterChosen = false;
  bool get hasChosenReciter => _reciterChosen;

  Future<void> setReciter(String id) async {
    if (!reciters.containsKey(id)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reciterEdition', id);
    await prefs.setBool('reciterChosen', true);
    _reciterChosen = true;
    if (id != _reciter) {
      _reciter = id;
      // Downloads in flight belong to the old reciter — stop them.
      _cancelSurahDownload();
      // A currently-playing ayah keeps the old voice until it ends;
      // anything played after this uses the new reciter.
    }
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

  /// Background surah-download progress for the UI: null when idle,
  /// otherwise (downloaded, total) for the surah being fetched.
  int? _dlSurah;
  int _dlDone = 0;
  int _dlTotal = 0;
  bool get isDownloadingSurah => _dlSurah != null;
  int get downloadDone => _dlDone;
  int get downloadTotal => _dlTotal;

  /// The UI (ReaderScreen) sets this so the service can figure out what
  /// "next ayah" means for auto-advance without hardcoding surah logic
  /// here. Given the currently-playing global ayah number, return the
  /// next global ayah number to play, or null to stop (e.g. end of surah).
  int? Function(int currentGlobalAyah)? nextAyahResolver;

  QuranAudioService() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      // The moment real playback starts, the track is no longer
      // "loading" — without this the UI could stay stuck on the
      // download label if play() resolved late or out of order.
      if (state == PlayerState.playing) _isLoading = false;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) => _handleComplete());
    _loadReciter();
  }

  Future<void> _loadReciter() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('reciterEdition');
    if (saved != null && reciters.containsKey(saved)) {
      _reciter = saved;
      _reciterChosen = prefs.getBool('reciterChosen') ?? false;
    } else {
      // No saved choice, or the saved reciter was removed from the
      // list — fall back to the default and ask again on next play.
      _reciter = _defaultReciter;
      _reciterChosen = false;
    }
    notifyListeners();
  }

  // ── Local audio files ────────────────────────────────────────────────

  Directory? _docsDir;

  Future<File> _localFile(String reciter, int globalAyah) async {
    _docsDir ??= await getApplicationDocumentsDirectory();
    return File(
        '${_docsDir!.path}${Platform.pathSeparator}audio${Platform.pathSeparator}$reciter${Platform.pathSeparator}$globalAyah.mp3');
  }

  List<String> _urlsFor(String reciter, int globalAyah) => [
        'https://cdn.islamic.network/quran/audio/128/$reciter/$globalAyah.mp3',
        'https://cdn.islamic.network/quran/audio/64/$reciter/$globalAyah.mp3',
        'https://cdn.alquran.cloud/media/audio/ayah/$reciter/$globalAyah',
      ];

  /// Downloads one ayah's mp3 to local storage if not already present.
  /// Returns the file when it exists/downloaded, null on failure.
  Future<File?> _ensureLocal(String reciter, int globalAyah) async {
    final file = await _localFile(reciter, globalAyah);
    if (await file.exists() && (await file.length()) > 0) return file;
    for (final url in _urlsFor(reciter, globalAyah)) {
      try {
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          await file.parent.create(recursive: true);
          // Write via temp file + rename so a torn download never
          // leaves a half-written mp3 that would "exist" next time.
          final tmp = File('${file.path}.part');
          await tmp.writeAsBytes(res.bodyBytes, flush: true);
          await tmp.rename(file.path);
          return file;
        }
      } catch (_) {
        // Try the next mirror.
      }
    }
    return null;
  }

  /// The surah a global ayah belongs to, plus that surah's full global
  /// range, derived from the fixed ayah counts.
  static (int surah, int first, int last) surahRangeOf(int globalAyah) {
    var start = 1;
    for (var s = 0; s < QuranPageMeta.ayahCounts.length; s++) {
      final end = start + QuranPageMeta.ayahCounts[s] - 1;
      if (globalAyah <= end) return (s + 1, start, end);
      start = end + 1;
    }
    return (114, 6231, 6236);
  }

  int _downloadGeneration = 0;

  void _cancelSurahDownload() {
    _downloadGeneration++;
    _dlSurah = null;
  }

  /// Fetches every missing ayah of [globalAyah]'s surah in the
  /// background, so continuous playback through the surah never has to
  /// wait on the network. Playing order first: current ayah to the end,
  /// then whatever was skipped at the start.
  Future<void> _downloadSurahAround(int globalAyah) async {
    if (kIsWeb) return;
    final (surah, first, last) = surahRangeOf(globalAyah);
    if (_dlSurah == surah) return; // already fetching this surah
    final generation = ++_downloadGeneration;
    final reciter = _reciter;

    final order = [
      for (var g = globalAyah; g <= last; g++) g,
      for (var g = first; g < globalAyah; g++) g,
    ];

    _dlSurah = surah;
    _dlTotal = order.length;
    _dlDone = 0;
    for (final g in order) {
      if (generation != _downloadGeneration) return; // cancelled
      final f = await _localFile(reciter, g);
      if (!(await f.exists() && (await f.length()) > 0)) {
        await _ensureLocal(reciter, g);
      }
      if (generation != _downloadGeneration) return;
      _dlDone++;
      // Notify sparsely — every few files is enough for a progress UI.
      if (_dlDone % 3 == 0 || _dlDone == _dlTotal) notifyListeners();
    }
    if (generation == _downloadGeneration) {
      _dlSurah = null;
      notifyListeners();
    }
  }

  // ── Playback ─────────────────────────────────────────────────────────

  Future<void> playAyah(int globalAyahNumber) async {
    _isLoading = true;
    _error = null;
    _currentGlobalAyah = globalAyahNumber;
    notifyListeners();

    final reciter = _reciter;
    var played = false;

    if (!kIsWeb) {
      // Prefer the local file; fetch just this ayah if missing.
      final file = await _ensureLocal(reciter, globalAyahNumber);
      if (file != null) {
        try {
          await _player.stop();
          await _player.play(DeviceFileSource(file.path));
          played = true;
        } catch (_) {
          played = false;
        }
      }
      // Whatever happened with THIS ayah, make sure the rest of the
      // surah gets pulled down for gapless continuation.
      unawaited(_downloadSurahAround(globalAyahNumber));
    }

    if (!played) {
      // Web, or local path failed — stream from the CDN mirrors.
      for (final url in _urlsFor(reciter, globalAyahNumber)) {
        try {
          await _player.stop();
          await _player.play(UrlSource(url));
          played = true;
          break;
        } catch (_) {
          // Try the next source.
        }
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
    _cancelSurahDownload();
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
    _cancelSurahDownload();
    _player.dispose();
    super.dispose();
  }
}

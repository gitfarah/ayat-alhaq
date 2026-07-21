import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quran_page_meta.dart';

/// Plays per-ayah Quran recitation from the alquran.cloud CDN, with
/// TRUE background playback and lock-screen / control-center media
/// controls (via just_audio_background — configured in main() with
/// JustAudioBackground.init). Ayah numbers here are always the GLOBAL
/// sequential number (1-6236, matching Ayah.number).
///
/// Download-first (mobile/desktop): a played ayah is downloaded to
/// local storage and played from disk, and the REST of that surah is
/// pulled down in the background — so auto-advance is gapless and
/// replays work offline. Playback continues when the screen locks or
/// the app is backgrounded, with a system now-playing control.
class QuranAudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

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
      _cancelSurahDownload();
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

  int? _dlSurah;
  int _dlDone = 0;
  int _dlTotal = 0;
  bool get isDownloadingSurah => _dlSurah != null;
  int get downloadDone => _dlDone;
  int get downloadTotal => _dlTotal;

  int? Function(int currentGlobalAyah)? nextAyahResolver;

  QuranAudioService() {
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      if (state.processingState == ProcessingState.ready) _isLoading = false;
      if (state.processingState == ProcessingState.completed) {
        _handleComplete();
      } else {
        notifyListeners();
      }
    });
    _loadReciter();
  }

  Future<void> _loadReciter() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('reciterEdition');
    if (saved != null && reciters.containsKey(saved)) {
      _reciter = saved;
      _reciterChosen = prefs.getBool('reciterChosen') ?? false;
    } else {
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

  Future<void> _downloadSurahAround(int globalAyah) async {
    if (kIsWeb) return;
    final (surah, first, last) = surahRangeOf(globalAyah);
    if (_dlSurah == surah) return;
    final generation = ++_downloadGeneration;
    final reciter = _reciter;

    final queue = [
      for (var g = globalAyah; g <= last; g++) g,
      for (var g = first; g < globalAyah; g++) g,
    ];

    _dlSurah = surah;
    _dlTotal = queue.length;
    _dlDone = 0;
    notifyListeners();

    Future<void> worker() async {
      while (queue.isNotEmpty && generation == _downloadGeneration) {
        final g = queue.removeAt(0);
        final f = await _localFile(reciter, g);
        if (!(await f.exists() && (await f.length()) > 0)) {
          await _ensureLocal(reciter, g);
        }
        if (generation != _downloadGeneration) return;
        _dlDone++;
        if (_dlDone % 3 == 0 || _dlDone == _dlTotal) notifyListeners();
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    if (generation == _downloadGeneration) {
      _dlSurah = null;
      notifyListeners();
    }
  }

  // ── Playback ─────────────────────────────────────────────────────────

  /// The app icon, copied out of assets to a real file once so it can
  /// be shown as the artwork on the lock screen / media notification
  /// (artUri needs a file/content URI, not an asset path).
  Uri? _artUri;
  Future<Uri?> _appArtUri() async {
    if (_artUri != null || kIsWeb) return _artUri;
    try {
      _docsDir ??= await getApplicationDocumentsDirectory();
      final f = File('${_docsDir!.path}${Platform.pathSeparator}media_art.png');
      if (!await f.exists()) {
        final bytes = await rootBundle.load('assets/icon/media_art.png');
        await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      }
      _artUri = Uri.file(f.path);
    } catch (_) {
      _artUri = null;
    }
    return _artUri;
  }

  /// Media metadata shown on the lock screen / control center for the
  /// currently playing ayah — including the app icon as artwork.
  MediaItem _mediaItemFor(int globalAyah, Uri? art) {
    final (surah, first, _) = surahRangeOf(globalAyah);
    final ayahInSurah = globalAyah - first + 1;
    return MediaItem(
      id: '$_reciter-$globalAyah',
      album: 'آيات الحق',
      title: 'سورة ${QuranPageMeta.surahName(surah)} — آية $ayahInSurah',
      artist: reciterName,
      artUri: art,
    );
  }

  Future<void> playAyah(int globalAyahNumber) async {
    _isLoading = true;
    _error = null;
    _currentGlobalAyah = globalAyahNumber;
    notifyListeners();

    final reciter = _reciter;
    final media = _mediaItemFor(globalAyahNumber, await _appArtUri());
    var started = false;

    if (!kIsWeb) {
      final file = await _ensureLocal(reciter, globalAyahNumber);
      if (file != null) {
        try {
          await _player.setAudioSource(
              AudioSource.uri(Uri.file(file.path), tag: media));
          _player.play();
          started = true;
        } catch (_) {
          started = false;
        }
      }
      unawaited(_downloadSurahAround(globalAyahNumber));
    }

    if (!started) {
      for (final url in _urlsFor(reciter, globalAyahNumber)) {
        try {
          await _player.setAudioSource(
              AudioSource.uri(Uri.parse(url), tag: media));
          _player.play();
          started = true;
          break;
        } catch (_) {
          // Try the next source.
        }
      }
    }

    if (!started) {
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
      _player.play();
    } else {
      await playAyah(globalAyahNumber);
    }
  }

  Future<void> stop() async {
    // Keep the surah download running — the user asked for the whole
    // surah, so let it finish for offline replays.
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

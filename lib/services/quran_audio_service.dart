import 'dart:async';
import 'dart:convert';
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
class _QulAyahClip {
  final String audioUrl;
  final Duration start;
  final Duration end;

  const _QulAyahClip({
    required this.audioUrl,
    required this.start,
    required this.end,
  });
}

class _QulSurahAudio {
  final String audioUrl;
  final Map<int, (int startMs, int endMs)> ayahs;

  const _QulSurahAudio({required this.audioUrl, required this.ayahs});
}

class QuranAudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  /// Set once in main() if JustAudioBackground.init() fails at launch.
  /// It runs before this service — indeed before any AudioPlayer — ever
  /// exists, so nothing else could report what went wrong. Every
  /// AudioPlayer created afterwards is silently unbacked by the
  /// background audio service when this is non-null, which can leave
  /// playback simply never starting with no exception of its own.
  static Object? backgroundInitFailure;

  static const Map<String, String> reciters = {
    'qul.mansouralsalimi': 'منصور السالمي',
    'qul.abdurrashidsufi.kisai': 'عبد الرشيد صوفي',
    'qul.abdulwadudhaneef': 'عبد الودود حنيف',
    'ar.mahermuaiqly': 'ماهر المعيقلي',
    'ar.husary': 'محمود خليل الحصري',
    'ar.abdulsamad': 'عبدالباسط عبدالصمد',
    'ar.saoodshuraym': 'سعود الشريم',
    'ar.hudhaify': 'علي الحذيفي',
    'ar.muhammadayyoub': 'محمد أيوب',
    'ar.shaatree': 'أبو بكر الشاطري',
    'ar.ahmedajamy': 'أحمد العجمي',
    'ar.minshawi': 'محمد صديق المنشاوي',
    'ar.mustafaismail': 'مصطفى إسماعيل',
    'ar.mahmoudalbanna': 'محمود البنا',
  };

  /// Reciters served only as whole-surah files everywhere they're
  /// archived (islamic.network, mp3quran.net, quran.com) have no
  /// per-ayah audio at all and can't support ayah-by-ayah playback:
  /// عبدالرشيد الصوفي and أحمد بن طالب (بن حميد) were requested but
  /// dropped for this reason — no per-ayah source exists to point at.
  ///
  /// Ayah-by-ayah audio for the reciters above that AREN'T on the
  /// islamic.network/alquran.cloud CDN comes from everyayah.com
  /// instead, which splits recordings into one file per ayah using a
  /// zero-padded "surah+ayah" name (e.g. 114006.mp3 for 114:6).
  static const Map<String, String> _everyayahFolder = {
    'ar.mustafaismail': 'Mustafa_Ismail_48kbps',
    'ar.mahmoudalbanna': 'mahmoud_ali_al_banna_32kbps',
  };

  static const String _mansourReciter = 'qul.mansouralsalimi';
  static const String _abdurRashidReciter = 'qul.abdurrashidsufi.kisai';
  static const String _abdulwadudReciter = 'qul.abdulwadudhaneef';
  static const String _defaultReciter = 'ar.mahermuaiqly';
  static final Map<int, Future<_QulSurahAudio?>> _mansourSurahFutures = {};
  static Future<(Map<String, dynamic>, Map<String, dynamic>)>?
      _mansourDataFuture;
  final Map<int, Future<File?>> _mansourDownloadFutures = {};
  static Future<Map<String, dynamic>>? _abdurRashidDataFuture;
  final Map<int, Future<File?>> _abdurRashidDownloadFutures = {};
  static Future<Map<String, dynamic>>? _abdulwadudDataFuture;
  final Map<int, Future<File?>> _abdulwadudDownloadFutures = {};

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

  /// Playback position of the current ayah, ticking while it plays.
  ///
  /// Exposed as a STREAM rather than as ChangeNotifier state on purpose:
  /// it fires many times a second, and only the word-highlight cares. A
  /// notifyListeners() at that rate would rebuild every reading screen.
  Duration? _manualClipStart;
  Duration? _manualClipEnd;
  StreamSubscription<Duration>? _manualClipSubscription;

  Stream<Duration> get positionStream =>
      _player.positionStream.map((p) => clipRelative(p, _manualClipStart));

  /// Playback position expressed relative to the ayah being recited.
  ///
  /// [clipStart] is set only for Mansour al-Salimi, on every platform:
  /// his ayahs are all slices of one whole-surah recording, clipped BY
  /// HAND rather than with a ClippingAudioSource. A ClippingAudioSource
  /// per ayah would do this for us automatically, but re-loading the
  /// SAME surah file into a fresh one for every ayah is what caused a
  /// little stutter-and-click between consecutive ayahs, so the surah
  /// loads once and every ayah after the first is reached with a seek
  /// instead — see [_setManualClip]. Every other reciter plays a file
  /// that is the ayah entire (or, for عبد الرشيد الصوفي, the whole
  /// surah played straight through as one track), so this stays null
  /// for them and the position passes straight through.
  ///
  /// Collapsing that null case together with "before the clip starts"
  /// into one `||` returned zero for BOTH — which pinned the scrubber,
  /// the elapsed time and the word-by-word highlight at zero for every
  /// reciter on every device, from the moment clipping was introduced
  /// for the two QUL reciters.
  @visibleForTesting
  static Duration clipRelative(Duration position, Duration? clipStart) {
    if (clipStart == null) return position;
    if (position <= clipStart) return Duration.zero;
    return position - clipStart;
  }

  /// Length of the current ayah's clip, once known.
  Duration? get trackDuration {
    final start = _manualClipStart;
    final end = _manualClipEnd;
    return start != null && end != null ? end - start : _player.duration;
  }

  Stream<Duration?> get durationStream =>
      _player.durationStream.map((duration) {
        final start = _manualClipStart;
        final end = _manualClipEnd;
        return start != null && end != null ? end - start : duration;
      });

  void _clearManualClip() {
    _manualClipSubscription?.cancel();
    _manualClipSubscription = null;
    _manualClipStart = null;
    _manualClipEnd = null;
  }

  /// Fires once playback crosses the armed clip's end. Tries first to
  /// just keep going: if the reader is auto-advancing straight into the
  /// very next ayah of the SAME surah recording already loaded, that
  /// ayah is reached by relabelling the clip boundaries in place —
  /// no [_player.seek], no [_player.pause]. A seek is a hard splice in
  /// the decoded audio and is what produced an audible click at every
  /// single ayah boundary even once reloads were eliminated: any seek
  /// at all, correct destination or not, clicks. Only a real jump —
  /// autoAdvance off, a non-sequential resolver, or the surah itself
  /// changing — falls back to pausing and handing off to
  /// [_handleComplete], which is the one place a seek is unavoidable.
  Future<void> _onManualClipEnded() async {
    final current = _currentGlobalAyah;
    if (current != null && _autoAdvance) {
      final next = nextAyahResolver?.call(current) ??
          (current < 6236 ? current + 1 : null);
      if (next != null && next == current + 1) {
        final (nextSurah, _, _) = surahRangeOf(next);
        if (nextSurah == _loadedMansourSurah) {
          final clip = await _mansourClip(next);
          if (clip != null) {
            _currentGlobalAyah = next;
            _manualClipStart = clip.start;
            _manualClipEnd = clip.end;
            _armManualClipBoundary(clip.end);
            notifyListeners();
            return;
          }
        }
      }
    }
    await _player.pause();
    await _handleComplete();
  }

  /// Watches [_player.positionStream] for playback crossing [end] and
  /// hands off to [_onManualClipEnded]. Guarded against firing twice for
  /// the same boundary if more than one position tick arrives before
  /// the subscription is torn down.
  void _armManualClipBoundary(Duration end) {
    _manualClipSubscription = _player.positionStream.listen((position) {
      if (position < end) return;
      final sub = _manualClipSubscription;
      if (sub == null) return;
      _manualClipSubscription = null;
      sub.cancel();
      unawaited(_onManualClipEnded());
    });
  }

  /// Points the player at one ayah's slice of a surah recording that is
  /// already loaded in full, without touching the audio source — just a
  /// seek, plus [_armManualClipBoundary] to stop (or chain onward) once
  /// playback crosses [end].
  Future<void> _setManualClip(Duration start, Duration end) async {
    _manualClipSubscription?.cancel();
    _manualClipStart = start;
    _manualClipEnd = end;
    await _player.seek(start);
    _armManualClipBoundary(end);
  }

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

  List<String> _urlsFor(String reciter, int globalAyah) {
    final everyayahFolder = _everyayahFolder[reciter];
    if (everyayahFolder != null) {
      final (surah, first, _) = surahRangeOf(globalAyah);
      final ayahInSurah = globalAyah - first + 1;
      final name =
          '${surah.toString().padLeft(3, '0')}${ayahInSurah.toString().padLeft(3, '0')}';
      return ['https://everyayah.com/data/$everyayahFolder/$name.mp3'];
    }
    return [
      'https://cdn.islamic.network/quran/audio/128/$reciter/$globalAyah.mp3',
      'https://cdn.islamic.network/quran/audio/64/$reciter/$globalAyah.mp3',
      'https://cdn.alquran.cloud/media/audio/ayah/$reciter/$globalAyah',
    ];
  }

  static Future<(Map<String, dynamic>, Map<String, dynamic>)>
      _loadMansourData() => _mansourDataFuture ??= Future.wait<String>([
            rootBundle.loadString('assets/quran/mansour_al_salimi_surahs.json'),
            rootBundle
                .loadString('assets/quran/mansour_al_salimi_segments.json'),
          ]).then((files) => (
                jsonDecode(files[0]) as Map<String, dynamic>,
                jsonDecode(files[1]) as Map<String, dynamic>,
              ));

  Future<_QulSurahAudio?> _loadMansourSurahFromApi(int surah) async {
    try {
      final ayahCount = QuranPageMeta.ayahCounts[surah - 1];
      String? audioUrl;
      final ayahs = <int, (int, int)>{};
      for (var from = 1; from <= ayahCount; from += 20) {
        final candidateEnd = from + 19;
        final to = candidateEnd < ayahCount ? candidateEnd : ayahCount;
        final uri = Uri.parse(
          'https://qul.tarteel.ai/api/v1/audio/surah_segments/179'
          '?surah=$surah&from=$from&to=$to',
        );
        final response =
            await http.get(uri).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) return null;
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final audio = json['audio'] as Map<String, dynamic>?;
        final segments = json['segments'] as Map<String, dynamic>?;
        audioUrl ??= audio?['url'] as String?;
        if (segments == null) return null;
        for (var ayah = from; ayah <= to; ayah++) {
          final data = segments['$surah:$ayah'] as Map<String, dynamic>?;
          final start = (data?['time_from'] as num?)?.round();
          final end = (data?['time_to'] as num?)?.round();
          if (start != null && end != null && end > start) {
            ayahs[ayah] = (start, end);
          }
        }
      }
      if (audioUrl == null || ayahs.length != ayahCount) return null;
      return _QulSurahAudio(audioUrl: audioUrl, ayahs: ayahs);
    } catch (_) {
      return null;
    }
  }

  Future<_QulSurahAudio?> _loadMansourSurah(int surah) =>
      _mansourSurahFutures[surah] ??= () async {
        try {
          final (surahs, segments) = await _loadMansourData();
          final surahData = surahs['$surah'] as Map<String, dynamic>?;
          final audioUrl = surahData?['audio_url'] as String?;
          if (audioUrl == null) throw const FormatException();
          final ayahs = <int, (int, int)>{};
          final ayahCount = QuranPageMeta.ayahCounts[surah - 1];
          for (var ayah = 1; ayah <= ayahCount; ayah++) {
            final data = segments['$surah:$ayah'] as Map<String, dynamic>?;
            final start = (data?['timestamp_from'] as num?)?.round();
            final end = (data?['timestamp_to'] as num?)?.round();
            if (start != null && end != null && end > start) {
              ayahs[ayah] = (start, end);
            }
          }
          if (ayahs.length != ayahCount) throw const FormatException();
          return _QulSurahAudio(audioUrl: audioUrl, ayahs: ayahs);
        } catch (_) {
          return _loadMansourSurahFromApi(surah);
        }
      }();
  Future<_QulAyahClip?> _mansourClip(int globalAyah) async {
    final (surah, first, _) = surahRangeOf(globalAyah);
    final audio = await _loadMansourSurah(surah);
    final times = audio?.ayahs[globalAyah - first + 1];
    if (audio == null || times == null) return null;
    return _QulAyahClip(
      audioUrl: audio.audioUrl,
      start: Duration(milliseconds: times.$1),
      end: Duration(milliseconds: times.$2),
    );
  }

  Future<File> _mansourSurahFile(int surah) async {
    _docsDir ??= await getApplicationDocumentsDirectory();
    return File(
      '${_docsDir!.path}${Platform.pathSeparator}audio'
      '${Platform.pathSeparator}$_mansourReciter'
      '${Platform.pathSeparator}surah_$surah.mp3',
    );
  }

  Future<File?> _ensureMansourSurahLocal(int surah, String audioUrl) {
    final pending = _mansourDownloadFutures[surah];
    if (pending != null) return pending;
    final download = _downloadMansourSurah(surah, audioUrl);
    _mansourDownloadFutures[surah] = download;
    download.whenComplete(() => _mansourDownloadFutures.remove(surah));
    return download;
  }

  Future<File?> _downloadMansourSurah(int surah, String audioUrl) async {
    final file = await _mansourSurahFile(surah);
    if (await file.exists() && (await file.length()) > 0) return file;
    try {
      final response = await http
          .get(Uri.parse(audioUrl))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      await tmp.rename(file.path);
      return file;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _loadAbdurRashidData() =>
      _abdurRashidDataFuture ??= rootBundle
          .loadString('assets/quran/abdur_rashid_sufi_surahs.json')
          .then((raw) => jsonDecode(raw) as Map<String, dynamic>);

  Future<String?> _abdurRashidSurahUrl(int surah) async {
    try {
      final data = await _loadAbdurRashidData();
      final surahData = data['$surah'] as Map<String, dynamic>?;
      final audioUrl = surahData?['audio_url'] as String?;
      if (audioUrl != null) return audioUrl;
    } catch (_) {
      // A running Flutter session may not have rebuilt its asset manifest yet.
    }
    final number = surah.toString().padLeft(3, '0');
    return 'https://download.quranicaudio.com/quran/'
        'abdurrashid_sufi_abi_al7arith/$number.mp3';
  }

  Future<File> _abdurRashidSurahFile(int surah) async {
    _docsDir ??= await getApplicationDocumentsDirectory();
    return File(
      '${_docsDir!.path}${Platform.pathSeparator}audio'
      '${Platform.pathSeparator}$_abdurRashidReciter'
      '${Platform.pathSeparator}surah_$surah.mp3',
    );
  }

  Future<File?> _ensureAbdurRashidSurahLocal(
    int surah,
    String audioUrl,
  ) {
    final pending = _abdurRashidDownloadFutures[surah];
    if (pending != null) return pending;
    final download = _downloadAbdurRashidSurah(surah, audioUrl);
    _abdurRashidDownloadFutures[surah] = download;
    download.whenComplete(() => _abdurRashidDownloadFutures.remove(surah));
    return download;
  }

  Future<File?> _downloadAbdurRashidSurah(
    int surah,
    String audioUrl,
  ) async {
    final file = await _abdurRashidSurahFile(surah);
    if (await file.exists() && (await file.length()) > 0) return file;
    try {
      final response = await http
          .get(Uri.parse(audioUrl))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      await tmp.rename(file.path);
      return file;
    } catch (_) {
      return null;
    }
  }

  // ── عبد الودود حنيف — the same shape as عبد الرشيد صوفي above: a
  // bundled per-surah audio_url map (this one supplied directly, not
  // fetched from an API) with NO segment timing at all — its own
  // segments.json came back `{}`. So it gets the identical treatment:
  // whole-surah playback only, with every one of the special cases
  // below (playAyah, togglePlayPause, playNextAyah, _handleComplete)
  // mirrored rather than shared, so nothing about the two EXISTING
  // reciters' behaviour can move by adding a third.
  static Future<Map<String, dynamic>> _loadAbdulwadudData() =>
      _abdulwadudDataFuture ??= rootBundle
          .loadString('assets/quran/abdulwadud_haneef_surahs.json')
          .then((raw) => jsonDecode(raw) as Map<String, dynamic>);

  Future<String?> _abdulwadudSurahUrl(int surah) async {
    try {
      final data = await _loadAbdulwadudData();
      final surahData = data['$surah'] as Map<String, dynamic>?;
      final audioUrl = surahData?['audio_url'] as String?;
      if (audioUrl != null) return audioUrl;
    } catch (_) {
      // A running Flutter session may not have rebuilt its asset manifest yet.
    }
    final number = surah.toString().padLeft(3, '0');
    return 'https://download.quranicaudio.com/quran/'
        'abdulwadood_haneef/$number.mp3';
  }

  Future<File> _abdulwadudSurahFile(int surah) async {
    _docsDir ??= await getApplicationDocumentsDirectory();
    return File(
      '${_docsDir!.path}${Platform.pathSeparator}audio'
      '${Platform.pathSeparator}$_abdulwadudReciter'
      '${Platform.pathSeparator}surah_$surah.mp3',
    );
  }

  Future<File?> _ensureAbdulwadudSurahLocal(
    int surah,
    String audioUrl,
  ) {
    final pending = _abdulwadudDownloadFutures[surah];
    if (pending != null) return pending;
    final download = _downloadAbdulwadudSurah(surah, audioUrl);
    _abdulwadudDownloadFutures[surah] = download;
    download.whenComplete(() => _abdulwadudDownloadFutures.remove(surah));
    return download;
  }

  Future<File?> _downloadAbdulwadudSurah(
    int surah,
    String audioUrl,
  ) async {
    final file = await _abdulwadudSurahFile(surah);
    if (await file.exists() && (await file.length()) > 0) return file;
    try {
      final response = await http
          .get(Uri.parse(audioUrl))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      await tmp.rename(file.path);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _ensureLocal(String reciter, int globalAyah) async {
    final file = await _localFile(reciter, globalAyah);
    if (await file.exists() && (await file.length()) > 0) return file;
    for (final url in _urlsFor(reciter, globalAyah)) {
      try {
        final res =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
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
      // Rewritten on every launch rather than only when missing. The
      // old code kept whatever it had copied out the first time, so a
      // device that had run an earlier build went on showing the icon
      // from that build on the lock screen no matter how often the
      // asset changed. This costs one small write per app start.
      final bytes = await rootBundle.load('assets/icon/media_art.png');
      await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
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

  /// The surah currently sitting in [_player] for the Mansour reciter,
  /// so consecutive ayahs of it can be reached with a seek rather than
  /// a full reload. Null whenever the loaded source is something else
  /// (a different reciter, or nothing yet) — see [playAyah].
  int? _loadedMansourSurah;

  Future<bool> _playMansourAyah(
    int globalAyah,
    MediaItem media,
  ) async {
    final clip = await _mansourClip(globalAyah);
    if (clip == null) return false;
    final (surah, _, _) = surahRangeOf(globalAyah);
    try {
      // One file holds the whole surah; every ayah in it is just a
      // slice of the SAME recording. Setting a fresh ClippingAudioSource
      // for every single ayah — as this used to do — tore down and
      // rebuilt the player's decode pipeline each time, which is what
      // produced the little stutter-and-click heard between consecutive
      // ayahs. Loading only happens when the surah itself changes;
      // moving between its ayahs is a plain seek (see _setManualClip).
      if (_loadedMansourSurah != surah) {
        Uri audioUri = Uri.parse(clip.audioUrl);
        if (!kIsWeb) {
          final file = await _mansourSurahFile(surah);
          if (await file.exists() && (await file.length()) > 0) {
            audioUri = Uri.file(file.path);
          } else {
            unawaited(_ensureMansourSurahLocal(surah, clip.audioUrl));
          }
        }
        await _player.setAudioSource(AudioSource.uri(audioUri, tag: media));
        _loadedMansourSurah = surah;
      }
      await _setManualClip(clip.start, clip.end);
      _player.play();
      return true;
    } catch (_) {
      _loadedMansourSurah = null;
      return false;
    }
  }

  Future<bool> _playAbdurRashidSurah(
    int globalAyah,
    MediaItem media,
  ) async {
    final (surah, _, _) = surahRangeOf(globalAyah);
    final audioUrl = await _abdurRashidSurahUrl(surah);
    if (audioUrl == null) return false;
    try {
      Uri audioUri = Uri.parse(audioUrl);
      if (!kIsWeb) {
        final file = await _abdurRashidSurahFile(surah);
        if (await file.exists() && (await file.length()) > 0) {
          audioUri = Uri.file(file.path);
        } else {
          unawaited(_ensureAbdurRashidSurahLocal(surah, audioUrl));
        }
      }
      await _player.setAudioSource(AudioSource.uri(audioUri, tag: media));
      _player.play();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _playAbdulwadudSurah(
    int globalAyah,
    MediaItem media,
  ) async {
    final (surah, _, _) = surahRangeOf(globalAyah);
    final audioUrl = await _abdulwadudSurahUrl(surah);
    if (audioUrl == null) return false;
    try {
      Uri audioUri = Uri.parse(audioUrl);
      if (!kIsWeb) {
        final file = await _abdulwadudSurahFile(surah);
        if (await file.exists() && (await file.length()) > 0) {
          audioUri = Uri.file(file.path);
        } else {
          unawaited(_ensureAbdulwadudSurahLocal(surah, audioUrl));
        }
      }
      await _player.setAudioSource(AudioSource.uri(audioUri, tag: media));
      _player.play();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> playAyah(int globalAyahNumber) async {
    _clearManualClip();
    if (_reciter == _abdurRashidReciter || _reciter == _abdulwadudReciter) {
      final (_, first, _) = surahRangeOf(globalAyahNumber);
      globalAyahNumber = first;
    }
    _isLoading = true;
    _error = null;
    _currentGlobalAyah = globalAyahNumber;
    notifyListeners();

    final reciter = _reciter;
    // Whatever gets loaded below for a non-Mansour reciter replaces the
    // player's audio source, so the surah cached for Mansour's gapless
    // seeking (see _playMansourAyah) is no longer what's actually
    // loaded — forget it, or switching back later would seek a source
    // that isn't there instead of reloading it.
    if (reciter != _mansourReciter) _loadedMansourSurah = null;
    final media = _mediaItemFor(globalAyahNumber, await _appArtUri());
    var started = false;
    // Kept so a failure can say what actually went wrong. Reporting every
    // failure as a connection problem once cost a long hunt: the audio was
    // downloading fine and the PLAYER was the thing that was broken.
    Object? failure;
    var gotAudio = false;

    if (reciter == _mansourReciter) {
      started = await _playMansourAyah(globalAyahNumber, media);
    } else if (reciter == _abdurRashidReciter) {
      started = await _playAbdurRashidSurah(globalAyahNumber, media);
    } else if (reciter == _abdulwadudReciter) {
      started = await _playAbdulwadudSurah(globalAyahNumber, media);
    }

    if (!started &&
        reciter != _mansourReciter &&
        reciter != _abdurRashidReciter &&
        reciter != _abdulwadudReciter &&
        !kIsWeb) {
      final file = await _ensureLocal(reciter, globalAyahNumber);
      if (file != null) {
        // The clip is on disk: whatever fails now is not the network.
        gotAudio = true;
        try {
          // Bounded rather than a bare await: a broken binding between
          // the player and the background-audio service can leave this
          // call simply never resolving — no exception, no timeout of
          // its own — which used to leave the bar reading "جارٍ
          // التحميل..." forever instead of ever reporting a problem.
          await _player
              .setAudioSource(AudioSource.uri(Uri.file(file.path), tag: media))
              .timeout(const Duration(seconds: 20));
          _player.play();
          started = true;
        } catch (e) {
          failure ??= e;
          started = false;
        }
      }
      unawaited(_downloadSurahAround(globalAyahNumber));
    }

    if (!started &&
        reciter != _mansourReciter &&
        reciter != _abdurRashidReciter &&
        reciter != _abdulwadudReciter) {
      for (final url in _urlsFor(reciter, globalAyahNumber)) {
        try {
          await _player
              .setAudioSource(AudioSource.uri(Uri.parse(url), tag: media))
              .timeout(const Duration(seconds: 20));
          _player.play();
          started = true;
          break;
        } catch (e) {
          failure ??= e; // Try the next source.
        }
      }
    }

    if (!started) {
      _isLoading = false;
      _currentGlobalAyah = null;
      // A failed background-audio-service init is checked FIRST: it is
      // the most useful thing to report when it happened, because it
      // explains a failure the other two messages would otherwise blame
      // on the wrong thing entirely.
      final bgFailure = backgroundInitFailure;
      // Only blame the connection when the audio never arrived. If it
      // downloaded and still would not play, say so — that is a different
      // problem, and the old message sent the reader to the wrong place.
      _error = bgFailure != null
          ? 'تعذّر إعداد خدمة الصوت: $bgFailure'
          : (gotAudio && failure != null
              ? 'تعذّر تشغيل التلاوة: $failure'
              : 'تعذّر تشغيل التلاوة، تحقق من اتصالك بالإنترنت');
      notifyListeners();
      return;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> togglePlayPause(int globalAyahNumber) async {
    if (_reciter == _abdurRashidReciter || _reciter == _abdulwadudReciter) {
      final (_, first, _) = surahRangeOf(globalAyahNumber);
      globalAyahNumber = first;
    }
    if (_currentGlobalAyah == globalAyahNumber && _isPlaying) {
      await _player.pause();
    } else if (_currentGlobalAyah == globalAyahNumber && !_isPlaying) {
      _player.play();
    } else {
      await playAyah(globalAyahNumber);
    }
  }

  /// Seeks within the CURRENT ayah's clip (the player bar's scrubber) —
  /// this never crosses into a neighbouring ayah's file.
  Future<void> seek(Duration position) {
    final start = _manualClipStart;
    return _player.seek(start == null ? position : start + position);
  }

  double _speed = 1.0;
  double get speed => _speed;

  /// Cycles through a fixed set of speeds, like the "1x" button on most
  /// recitation players — simpler than a slider for a value nobody sets
  /// to something oddly specific like 1.35x.
  static const List<double> speedSteps = [1.0, 1.25, 1.5, 1.75, 2.0, 0.75];

  Future<void> cycleSpeed() async {
    final i = speedSteps.indexOf(_speed);
    _speed = speedSteps[(i + 1) % speedSteps.length];
    await _player.setSpeed(_speed);
    notifyListeners();
  }

  /// Steps to the ayah right after/before the one playing, the same
  /// +1/-1 global-ayah stepping [nextAyahResolver] uses for auto-advance
  /// — the player bar's rewind/forward buttons move by whole ayahs, not
  /// by seconds, since that's the unit a reciter's clip comes in.
  Future<void> playPreviousAyah() async {
    final current = _currentGlobalAyah;
    if (current == null || current <= 1) return;
    await playAyah(current - 1);
  }

  Future<void> playNextAyah() async {
    final current = _currentGlobalAyah;
    if (current == null) return;
    if (_reciter == _abdurRashidReciter || _reciter == _abdulwadudReciter) {
      final (_, _, last) = surahRangeOf(current);
      if (last < 6236) await playAyah(last + 1);
      return;
    }
    final next = nextAyahResolver?.call(current) ??
        (current < 6236 ? current + 1 : null);
    if (next != null) await playAyah(next);
  }

  Future<void> stop() async {
    _clearManualClip();
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
        (_reciter == _abdurRashidReciter ||
            _reciter == _abdulwadudReciter) &&
        _currentGlobalAyah != null) {
      final (_, _, last) = surahRangeOf(_currentGlobalAyah!);
      if (last < 6236) {
        await playAyah(last + 1);
        return;
      }
    }
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
    _clearManualClip();
    _cancelSurahDownload();
    _player.dispose();
    super.dispose();
  }
}

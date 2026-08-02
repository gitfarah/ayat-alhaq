import 'dart:async';

import 'package:flutter/material.dart';

import '../services/quran_audio_service.dart';
import '../services/word_timing.dart';
import '../theme.dart';

/// One run of ayah text drawn in a single colour — a tajweed rule's
/// span, or the whole ayah when tajweed colouring is off.
class AyahRun {
  final String text;
  final Color? color;
  const AyahRun(this.text, [this.color]);
}

/// Ayah text that lights up word by word as the reciter says it.
///
/// Follows [QuranAudioService.positionStream] and re-colours the word
/// the recitation has reached, so the reader can see the pronunciation
/// move through the ayah. Timing comes from [WordTiming], which
/// estimates each word's share of the clip — see that file for why the
/// timing is derived rather than fetched.
///
/// Only ever mounted for the ayah currently playing; every other ayah
/// keeps rendering as ordinary static text, so nothing else on the page
/// rebuilds while audio runs.
class RecitingAyahText extends StatefulWidget {
  /// The ayah's coloured runs. Concatenated, they must be exactly the
  /// ayah text the timings are computed from.
  final List<AyahRun> runs;

  /// Spans appended after the text (the ayah-number badge).
  final List<InlineSpan> trailing;

  final TextStyle baseStyle;
  final bool isDark;

  /// Where playback currently is, and how long the clip is. Passed as
  /// plain streams rather than as the service so this widget can be
  /// driven — and tested — without an audio player.
  final Stream<Duration> positionStream;
  final Stream<Duration?> durationStream;
  final Duration? initialDuration;

  const RecitingAyahText({
    super.key,
    required this.runs,
    required this.baseStyle,
    required this.isDark,
    required this.positionStream,
    required this.durationStream,
    this.initialDuration,
    this.trailing = const [],
  });

  /// Convenience constructor for the app's own audio service.
  factory RecitingAyahText.forAudio({
    Key? key,
    required List<AyahRun> runs,
    required TextStyle baseStyle,
    required bool isDark,
    required QuranAudioService audio,
    List<InlineSpan> trailing = const [],
  }) =>
      RecitingAyahText(
        key: key,
        runs: runs,
        baseStyle: baseStyle,
        isDark: isDark,
        trailing: trailing,
        positionStream: audio.positionStream,
        durationStream: audio.durationStream,
        initialDuration: audio.trackDuration,
      );

  @override
  State<RecitingAyahText> createState() => _RecitingAyahTextState();
}

class _RecitingAyahTextState extends State<RecitingAyahText> {
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  List<WordSpanTiming> _timings = const [];
  Duration? _duration;
  Duration _position = Duration.zero;
  int _active = -1;

  String get _text => widget.runs.map((r) => r.text).join();

  @override
  void initState() {
    super.initState();
    _duration = widget.initialDuration;
    _rebuildTimings(_duration);
    _durSub = widget.durationStream.listen(_rebuildTimings);
    _posSub = widget.positionStream.listen(_onPosition);
  }

  @override
  void didUpdateWidget(RecitingAyahText old) {
    super.didUpdateWidget(old);
    // A different ayah (or edited runs) means the old word ranges no
    // longer point anywhere meaningful.
    if (old.runs.map((r) => r.text).join() != _text) {
      _active = -1;
      _rebuildTimings(_duration);
    }
  }

  void _rebuildTimings(Duration? duration) {
    if (!mounted) return;
    _duration = duration;
    final next = duration == null
        ? const <WordSpanTiming>[]
        : WordTiming.forAyah(_text, duration);
    setState(() {
      _timings = next;
      _active = WordTiming.indexAt(next, _position);
    });
  }

  void _onPosition(Duration p) {
    _position = p;
    if (_timings.isEmpty) return;
    final i = WordTiming.indexAt(_timings, p, _active < 0 ? 0 : _active);
    // Repaint only when the highlight actually moves to another word,
    // not on every position tick.
    if (i != _active && mounted) setState(() => _active = i);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    super.dispose();
  }

  /// Splits [widget.runs] so the active word's characters carry the
  /// highlight, keeping every run's own tajweed colour.
  List<InlineSpan> _spans() {
    final highlight = _active >= 0 && _active < _timings.length
        ? _timings[_active]
        : null;
    final background = widget.isDark
        ? AppColors.darkSecondary.withValues(alpha: 0.30)
        : AppColors.gold.withValues(alpha: 0.38);
    final wordColor =
        widget.isDark ? AppColors.darkSecondary : AppColors.primary;

    final out = <InlineSpan>[];
    var offset = 0;
    for (final run in widget.runs) {
      final runStart = offset;
      final runEnd = offset + run.text.length;
      offset = runEnd;

      TextStyle? plain() =>
          run.color == null ? null : TextStyle(color: run.color);

      if (highlight == null ||
          highlight.end <= runStart ||
          highlight.start >= runEnd) {
        out.add(TextSpan(text: run.text, style: plain()));
        continue;
      }

      final cutStart = highlight.start.clamp(runStart, runEnd);
      final cutEnd = highlight.end.clamp(runStart, runEnd);
      if (cutStart > runStart) {
        out.add(TextSpan(
            text: run.text.substring(0, cutStart - runStart), style: plain()));
      }
      out.add(TextSpan(
        text: run.text.substring(cutStart - runStart, cutEnd - runStart),
        style: TextStyle(
          // A tajweed rule already carries meaning — keep its colour and
          // mark the word with the background alone.
          color: run.color ?? wordColor,
          backgroundColor: background,
          fontWeight: FontWeight.bold,
        ),
      ));
      if (cutEnd < runEnd) {
        out.add(TextSpan(
            text: run.text.substring(cutEnd - runStart), style: plain()));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      text: TextSpan(
        style: widget.baseStyle,
        children: [..._spans(), ...widget.trailing],
      ),
    );
  }
}

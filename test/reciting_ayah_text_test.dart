import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/word_timing.dart';
import 'package:quran_app_v1/widgets/reciting_ayah_text.dart';

void main() {
  const ayah = 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ';
  const clip = Duration(seconds: 6);
  final timings = WordTiming.forAyah(ayah, clip);

  late StreamController<Duration> position;

  setUp(() => position = StreamController<Duration>.broadcast());
  tearDown(() => position.close());

  /// The words that are currently drawn with the highlight background.
  List<String> highlighted(WidgetTester tester) {
    final text = tester.widget<RichText>(find.byType(RichText)).text;
    final out = <String>[];
    text.visitChildren((span) {
      if (span is TextSpan &&
          span.text != null &&
          span.style?.backgroundColor != null) {
        out.add(span.text!);
      }
      return true;
    });
    return out;
  }

  Future<void> pump(WidgetTester tester, {List<AyahRun>? runs}) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: RecitingAyahText(
          runs: runs ?? const [AyahRun(ayah)],
          baseStyle: const TextStyle(fontSize: 24),
          isDark: false,
          positionStream: position.stream,
          durationStream: Stream<Duration?>.value(clip),
          initialDuration: clip,
        ),
      ),
    ));
    await tester.pump();
  }

  /// Emits a playback position and lets the widget settle: the stream
  /// event lands in a microtask, so the repaint is the frame AFTER.
  Future<void> seek(WidgetTester tester, Duration at) async {
    position.add(at);
    await tester.pump();
    await tester.pump();
  }

  Duration midOf(int i) =>
      timings[i].from +
      Duration(
          microseconds:
              (timings[i].to - timings[i].from).inMicroseconds ~/ 2);

  testWidgets('nothing is highlighted before the first word', (tester) async {
    await pump(tester);
    await seek(tester, Duration.zero);
    expect(highlighted(tester), isEmpty);
  });

  testWidgets('the highlight walks word by word through the ayah',
      (tester) async {
    await pump(tester);
    for (var i = 0; i < timings.length; i++) {
      await seek(tester, midOf(i));
      expect(highlighted(tester).join(),
          ayah.substring(timings[i].start, timings[i].end));
    }
  });

  testWidgets('a tajweed-coloured word keeps its rule colour when lit',
      (tester) async {
    // Runs split the second word across two colours.
    const runs = [
      AyahRun('ٱلْحَمْدُ لِلَّ'),
      AyahRun('هِ', Color(0xFF169200)),
      AyahRun(' رَبِّ ٱلْعَٰلَمِينَ'),
    ];
    await pump(tester, runs: runs);
    await seek(tester, midOf(1));

    final text = tester.widget<RichText>(find.byType(RichText)).text;
    final lit = <TextSpan>[];
    text.visitChildren((s) {
      if (s is TextSpan && s.style?.backgroundColor != null) lit.add(s);
      return true;
    });
    // The whole word is lit, in two spans, and the rule colour survives.
    expect(lit.map((s) => s.text).join(), 'لِلَّهِ');
    expect(lit.last.style!.color, const Color(0xFF169200));
  });

  testWidgets('the full ayah text is still rendered while highlighting',
      (tester) async {
    await pump(tester);
    await seek(tester, midOf(2));
    final buf = StringBuffer();
    tester.widget<RichText>(find.byType(RichText)).text.visitChildren((s) {
      if (s is TextSpan && s.text != null) buf.write(s.text);
      return true;
    });
    expect(buf.toString(), ayah);
  });

  testWidgets('without a known duration nothing is highlighted',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: RecitingAyahText(
          runs: const [AyahRun(ayah)],
          baseStyle: const TextStyle(fontSize: 24),
          isDark: false,
          positionStream: position.stream,
          durationStream: const Stream<Duration?>.empty(),
        ),
      ),
    ));
    await seek(tester, const Duration(seconds: 2));
    expect(highlighted(tester), isEmpty);
  });
}

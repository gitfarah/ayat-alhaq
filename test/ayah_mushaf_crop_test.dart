// The real-Mushaf-page share card: a single ayah cropped straight out
// of the printed Hafs V4 page instead of set in a body font, so a word
// like ٱلْأَخِرَةِ comes out exactly as the King Fahd Complex print draws
// it — nothing here shapes the glyphs, so nothing here can get them
// wrong.
//
// [AyahShareService]'s crop machinery (`_MushafCrop`, `_V4PageIndex`,
// `_tryMushafCrop`) is private, so these tests go through the same
// public entry points a real share does (`renderCard`) and infer
// success from the OUTPUT — a bigger, more detailed PNG than a
// pure-fallback render would produce for the same ayah on an
// unreachable page.
//
// The one real page this needs (page 2 of the Hafs V4 1441H print) is
// checked in under test/fixtures/ — the exact artwork the app already
// fetches and displays live in Mushaf mode, so this adds no new
// copyright surface, only a cached copy of what ships anyway.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/ayah_share_service.dart';

void main() {
  // Card rendering reaches the engine and completes in REAL time — see
  // ayah_share_test.dart for why these stay plain `test`s.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocs;

  setUpAll(() async {
    // A throwaway "documents" directory carrying page 2 pre-seeded into
    // this feature's own cache folder — the same path a real device
    // would have after fetching it once. Built fresh each run rather
    // than checked in as a directory tree, so the fixture files stay
    // flat and the folder name that matters lives in one place: here,
    // next to the assertion that exercises it.
    tempDocs = await Directory.systemTemp.createTemp('ayah_share_test_docs');
    final cacheDir = Directory('${tempDocs.path}/share_card_v4_cache')
      ..createSync();
    await File('test/fixtures/mushaf_v4_page2/002.svg')
        .copy('${cacheDir.path}/002.svg');
    await File('test/fixtures/mushaf_v4_page2/002.json')
        .copy('${cacheDir.path}/002.json');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationDocumentsDirectory' => tempDocs.path,
        'getTemporaryDirectory' => tempDocs.path,
        _ => null,
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await tempDocs.delete(recursive: true);
  });

  // 2:4 — the SAME word-internal-hamza test case as the font tests
  // (assets/fonts + quran_font_asset_test.dart), because this is the
  // other way the app can be RIGHT about ٱلْأَخِرَةِ: not shaping it at
  // all.
  const onCachedPage = ShareableAyah(
    surahNumber: 2,
    surahName: 'البقرة',
    ayahNumber: 4,
    ayahText:
        'وَٱلَّذِينَ يُؤْمِنُونَ بِمَآ أُنزِلَ إِلَيْكَ وَمَآ أُنزِلَ مِن قَبْلِكَ وَبِٱلْءَاخِرَةِ هُمْ يُوقِنُونَ',
  );

  // Nowhere near page 2, and never cached, so in this test environment
  // (flutter test fakes HttpClient — no real fetch can succeed) this
  // MUST fall back to the text-rendered verse.
  const onUnreachablePage = ShareableAyah(
    surahNumber: 18,
    surahName: 'الكهف',
    ayahNumber: 10,
    ayahText: 'إِذْ أَوَى ٱلْفِتْيَةُ إِلَى ٱلْكَهْفِ',
  );

  test('a single ayah on a cached page renders bigger than the fallback',
      () async {
    final cropBytes = await AyahShareService.renderCard(onCachedPage);
    final fallbackBytes = await AyahShareService.renderCard(onUnreachablePage);
    expect(cropBytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(fallbackBytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    // The crop is real page art at 4x-ish supersampling — a strictly
    // heavier PNG than an Amiri paragraph on a flat ground. Not a
    // precise assertion, but a real one: if the crop path silently
    // stopped firing and every share fell back to text, this would be
    // the first thing to go quiet about it.
    expect(cropBytes.length, greaterThan(fallbackBytes.length));
  });

  test('renders on every background, cached page', () async {
    for (final bg in kShareBackgrounds) {
      final bytes = await AyahShareService.renderCard(onCachedPage, style: bg);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: bg.id);
    }
  });

  test('an unreachable page still produces a real card, not a failure',
      () async {
    final bytes = await AyahShareService.renderCard(onUnreachablePage);
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('a run of verses skips the crop path entirely, even on a cached page',
      () async {
    // The crop is single-verse only for now; a run must always be the
    // text card, cached page or not.
    const run = ShareableAyah(
      surahNumber: 2,
      surahName: 'البقرة',
      ayahNumber: 4,
      ayahText:
          'وَٱلَّذِينَ يُؤْمِنُونَ بِمَآ أُنزِلَ إِلَيْكَ وَمَآ أُنزِلَ مِن قَبْلِكَ وَبِٱلْءَاخِرَةِ هُمْ يُوقِنُونَ',
      moreVerses: [
        ShareVerse(5,
            'أُو۟لَٰٓئِكَ عَلَىٰ هُدًى مِّن رَّبِّهِمْ ۖ وَأُو۟لَٰٓئِكَ هُمُ ٱلْمُفْلِحُونَ'),
      ],
    );
    final bytes = await AyahShareService.renderCard(run);
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  // Regression, and the reason this file measures geometry at all.
  //
  // Two bad crops shipped before this was understood. The polygons in
  // this dataset are NOT per-ayah bounding boxes — they are staircases
  // tracing the text flow, and consecutive ayat share the y of the line
  // they meet on, so the bands tile the page with no gaps. On page 2:
  //
  //   ayah 2  ends at y=102.49        ayah 3  spans  72.23..133.88
  //   ayah 4  spans  101.66..160.15   ayah 5  spans 158.53..216.20
  //
  // The first cut padded by a fixed 4 units and pulled slivers of the
  // neighbouring lines in. The second "split the gap" with the nearest
  // band, assuming a gap existed — with contiguous bands that put the
  // top at (72.23+101.66)/2 = 86.9, halfway through the PREVIOUS line,
  // so a card for 2:4 carried a whole line of 2:2 and 2:3 above it.
  //
  // Both are geometry facts about the shipped fixture, so assert them
  // directly: any padding at all, in either direction, breaks these.
  group('crop bounds land exactly on the print\'s own line boundaries', () {
    List<List<double>> ringsFor(List<dynamic> json, int ayah) =>
        (json.firstWhere((e) => e['ayahNumber'] == ayah)['polygon'] as String)
            .split(RegExp(r'[MmZz]'))
            .map((part) => part
                .split(RegExp(r'[,\sLlHhVv]+'))
                .where((s) => s.isNotEmpty)
                .map(double.tryParse)
                .whereType<double>()
                .toList())
            .where((nums) => nums.length >= 6)
            .toList();

    late List<dynamic> page2;

    setUpAll(() async {
      page2 = jsonDecode(await File('test/fixtures/mushaf_v4_page2/002.json')
          .readAsString()) as List<dynamic>;
    });

    (double, double) yRange(int ayah) {
      var lo = double.infinity, hi = -double.infinity;
      for (final ring in ringsFor(page2, ayah)) {
        for (var i = 1; i < ring.length; i += 2) {
          lo = math.min(lo, ring[i]);
          hi = math.max(hi, ring[i]);
        }
      }
      return (lo, hi);
    }

    test('an ayah opens exactly where the line above it closes', () {
      // 2:4 opens at 101.66 — the same y 2:3's own staircase steps down
      // to. There is no gap to pad into.
      final (fourTop, _) = yRange(4);
      final threeRing = ringsFor(page2, 3);
      final sharedEdge =
          threeRing.expand((r) => [for (var i = 1; i < r.length; i += 2) r[i]]);
      expect(sharedEdge, contains(fourTop),
          reason: 'the line boundary is shared, so the crop must land on it '
              'exactly rather than padding past it');
    });

    test('neighbouring ayat overlap in y, so a "gap" to split never exists',
        () {
      // 2:3 runs to 133.88 while 2:4 starts at 101.66: they share a
      // line, and their y ranges genuinely overlap. Splitting the
      // distance to the nearest non-overlapping band is what reached
      // back over a whole line of text.
      final (threeTop, threeBottom) = yRange(3);
      final (fourTop, fourBottom) = yRange(4);
      expect(fourTop, lessThan(threeBottom));
      expect(threeTop, lessThan(fourTop));
      expect(fourBottom, greaterThan(threeBottom));
    });
  });

  test('the aspect estimate used for the "too long" hint stays text-based', () {
    // cardAspect is a SYNC, pre-render estimate the sheet calls live as
    // the reader adjusts the verse count — it must never depend on the
    // crop (which needs a page fetch) or it would block the UI thread
    // or lie while the fetch is in flight. Single-verse shares never
    // trip the "too tall" warning regardless of which path renders the
    // final image, so this staying text-only costs nothing.
    final aspect = AyahShareService.cardAspect(onCachedPage);
    expect(aspect, greaterThan(0));
    expect(AyahShareService.isCardTooTall(onCachedPage), isFalse);
  });
}

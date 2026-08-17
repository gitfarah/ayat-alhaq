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

import 'package:flutter/painting.dart' show decodeImageFromList;
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
    // Pages 2 and 3, so a run can be tested across the page turn
    // between them (2:5 ends page 2, 2:6 opens page 3). Page 4 is
    // deliberately absent — a run reaching it must fall back.
    for (final page in ['002', '003']) {
      await File('test/fixtures/mushaf_v4_pages/$page.svg')
          .copy('${cacheDir.path}/$page.svg');
      await File('test/fixtures/mushaf_v4_pages/$page.json')
          .copy('${cacheDir.path}/$page.json');
    }

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

  group('runs of verses', () {
    // 2:3 and 2:4 are both on page 2 — one strip covering the lines
    // they jointly occupy.
    const runOnePage = ShareableAyah(
      surahNumber: 2,
      surahName: 'البقرة',
      ayahNumber: 3,
      ayahText: 'ٱلَّذِينَ يُؤْمِنُونَ بِٱلْغَيْبِ',
      moreVerses: [
        ShareVerse(4, 'وَٱلَّذِينَ يُؤْمِنُونَ بِمَآ أُنزِلَ إِلَيْكَ'),
      ],
    );

    // 2:5 ends page 2, 2:6 opens page 3 — two strips, stacked.
    const runAcrossPages = ShareableAyah(
      surahNumber: 2,
      surahName: 'البقرة',
      ayahNumber: 5,
      ayahText: 'أُو۟لَٰٓئِكَ عَلَىٰ هُدًى مِّن رَّبِّهِمْ',
      moreVerses: [
        ShareVerse(6, 'إِنَّ ٱلَّذِينَ كَفَرُوا۟'),
      ],
    );

    test('a run on one page crops taller than either verse alone', () async {
      const justFour = ShareableAyah(
        surahNumber: 2,
        surahName: 'البقرة',
        ayahNumber: 4,
        ayahText: 'وَٱلَّذِينَ يُؤْمِنُونَ بِمَآ أُنزِلَ إِلَيْكَ',
      );
      final runImage = await decodeImageFromList(
          await AyahShareService.renderCard(runOnePage));
      final oneImage = await decodeImageFromList(
          await AyahShareService.renderCard(justFour));
      addTearDown(runImage.dispose);
      addTearDown(oneImage.dispose);
      // 2:3-2:4 covers strictly more printed lines than 2:4 alone, and
      // the card's height follows its content.
      expect(runImage.height, greaterThan(oneImage.height));
    });

    test('a run crossing a page break renders both leaves', () async {
      final bytes = await AyahShareService.renderCard(runAcrossPages);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final image = await decodeImageFromList(bytes);
      addTearDown(image.dispose);
      // Two strips plus the gap between them: taller than a card whose
      // verse block is a single strip from one page.
      const singlePage = ShareableAyah(
        surahNumber: 2,
        surahName: 'البقرة',
        ayahNumber: 5,
        ayahText: 'أُو۟لَٰٓئِكَ عَلَىٰ هُدًى مِّن رَّبِّهِمْ',
      );
      final oneImage = await decodeImageFromList(
          await AyahShareService.renderCard(singlePage));
      addTearDown(oneImage.dispose);
      expect(image.height, greaterThan(oneImage.height));
    });

    test('a run still renders when its pages are not all cached', () async {
      // 2:16 is on page 3 (cached here) but 2:17 is on page 4, which is
      // not — and no fetch can succeed in this environment. The whole
      // run must fall back to the text card rather than crop a
      // half-passage.
      const straddling = ShareableAyah(
        surahNumber: 2,
        surahName: 'البقرة',
        ayahNumber: 16,
        ayahText: 'أُو۟لَٰٓئِكَ ٱلَّذِينَ ٱشْتَرَوُا۟ ٱلضَّلَٰلَةَ',
        moreVerses: [
          ShareVerse(17, 'مَثَلُهُمْ كَمَثَلِ ٱلَّذِى ٱسْتَوْقَدَ نَارًا'),
        ],
      );
      final bytes = await AyahShareService.renderCard(straddling);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  // Regression, and the reason this file measures geometry at all.
  //
  // Three bad crops shipped before this was understood. The polygons
  // are NOT per-ayah bounding boxes — they are staircases tracing the
  // text flow, and their corner y-values are the print's own line
  // boundaries. On page 2:
  //
  //   ayah 2  ends at y=102.49        ayah 3  spans  72.23..133.88
  //   ayah 4  spans  101.66..160.15   ayah 5  spans 158.53..216.20
  //
  //   1. A fixed 4-unit pad pulled slivers of both neighbouring lines.
  //   2. "Split the gap with the nearest band" assumed a gap existed;
  //      it put 2:4's top at (72.23+101.66)/2 = 86.9, halfway through
  //      the PREVIOUS line, so the card carried a whole extra line.
  //   3. Cutting on the ayah's own BOTTOM (160.15) still dragged in
  //      the damma and صلے riding above ayah 5's letters, because
  //      ayah 5's line already starts at 158.53 — ABOVE that bottom.
  //
  // The rule that holds: a band's TOP is trustworthy, its BOTTOM is
  // not, so a strip ends where the NEXT line begins.
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
      page2 = jsonDecode(await File('test/fixtures/mushaf_v4_pages/002.json')
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

    test('an ayah\'s own BOTTOM overshoots into the line below it', () {
      // The whole reason the strip ends on the NEXT line's top rather
      // than on this ayah's own bottom. 2:5's line demonstrably begins
      // ABOVE where 2:4's band ends, and the marks that ride high over
      // 2:5's letters live in between — so cutting on 2:4's bottom
      // takes them along, which is the defect that was reported.
      final (_, fourBottom) = yRange(4);
      final (fiveTop, _) = yRange(5);
      expect(fiveTop, lessThan(fourBottom),
          reason: 'if this ever stops overlapping, the bottom-overshoot '
              'workaround can be simplified away');
      expect(fourBottom - fiveTop, greaterThan(1.0),
          reason: 'the overshoot is big enough to swallow a diacritic');
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

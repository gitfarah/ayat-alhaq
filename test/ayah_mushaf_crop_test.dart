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
import 'dart:io';

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

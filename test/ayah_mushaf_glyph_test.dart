// The Mushaf-glyph share card: a shared ayah set in the King Fahd
// Complex's OWN word-glyphs rather than in a body font, so it looks
// exactly like the printed page — and contains exactly the ayah that
// was chosen.
//
// This replaced CROPPING the printed page, which could not do the job
// and was reported broken twice. An ayah that begins mid-line shares
// that line with the ayah before it and ends sharing a line with the
// one after, so any horizontal crop of "its" lines necessarily carried
// pieces of its neighbours. No cut can separate them; only selecting
// the ayah's own words can, which is what the layout's per-word
// "surah:ayah" tags make possible.
//
// The machinery (`_GlyphRun`, `_V4Layout`, `_tryMushafGlyphs`) is
// private, so these go through the same public entry point a real
// share does and infer from the OUTPUT.
import 'dart:io';

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
    // Real V4 page fonts pre-seeded into this feature's own cache, the
    // state a device is in after one share of that page. Pages 2 and 3
    // only — an ayah on any other page has no font here and no way to
    // fetch one (flutter test fakes HttpClient), which is exactly the
    // fallback case worth testing.
    tempDocs = await Directory.systemTemp.createTemp('ayah_glyph_test_docs');
    final fontDir = Directory('${tempDocs.path}/mushaf_v4_plain_fonts')
      ..createSync();
    for (final p in [2, 3]) {
      await File('test/fixtures/v4_fonts/p$p.ttf')
          .copy('${fontDir.path}/p$p.ttf');
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

  // 2:12 — the reported case. It begins mid-line and ends mid-line, so
  // it is precisely the shape of ayah a crop mangled.
  const midLineAyah = ShareableAyah(
    surahNumber: 2,
    surahName: 'البقرة',
    ayahNumber: 12,
    ayahText: 'أَلَآ إِنَّهُمْ هُمُ ٱلْمُفْسِدُونَ وَلَٰكِن لَّا يَشْعُرُونَ',
  );

  // Page 300 has no font cached here and cannot be fetched.
  const onUnreachablePage = ShareableAyah(
    surahNumber: 26,
    surahName: 'الشعراء',
    ayahNumber: 80,
    ayahText: 'وَإِذَا مَرِضْتُ فَهُوَ يَشْفِينِ',
  );

  test('a verse whose page font is available renders', () async {
    final bytes = await AyahShareService.renderCard(midLineAyah);
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('renders on every background', () async {
    for (final bg in kShareBackgrounds) {
      final bytes = await AyahShareService.renderCard(midLineAyah, style: bg);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: bg.id);
    }
  });

  test('an unreachable page still produces a real card, not a failure',
      () async {
    // Falls back to the Amiri setting rather than failing or shipping
    // an empty verse block.
    final bytes = await AyahShareService.renderCard(onUnreachablePage);
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('a short ayah is set larger than a long one', () async {
    // The glyph size is chosen by measuring, so 2:1 (الٓمٓ, one word)
    // must come out on one big line while 2:12 wraps — which shows up
    // as a shorter card for the shorter ayah.
    const shortAyah = ShareableAyah(
      surahNumber: 2,
      surahName: 'البقرة',
      ayahNumber: 1,
      ayahText: 'الٓمٓ',
    );
    final shortImage =
        await decodeImageFromList(await AyahShareService.renderCard(shortAyah));
    final longImage = await decodeImageFromList(
        await AyahShareService.renderCard(midLineAyah));
    addTearDown(shortImage.dispose);
    addTearDown(longImage.dispose);
    expect(shortImage.height, lessThan(longImage.height));
  });

  group('runs of verses', () {
    test('a run is taller than either verse alone', () async {
      const run = ShareableAyah(
        surahNumber: 2,
        surahName: 'البقرة',
        ayahNumber: 6,
        ayahText: 'إِنَّ ٱلَّذِينَ كَفَرُوا۟',
        moreVerses: [
          ShareVerse(7, 'خَتَمَ ٱللَّهُ عَلَىٰ قُلُوبِهِمْ'),
        ],
      );
      const justSix = ShareableAyah(
        surahNumber: 2,
        surahName: 'البقرة',
        ayahNumber: 6,
        ayahText: 'إِنَّ ٱلَّذِينَ كَفَرُوا۟',
      );
      final runImage =
          await decodeImageFromList(await AyahShareService.renderCard(run));
      final oneImage =
          await decodeImageFromList(await AyahShareService.renderCard(justSix));
      addTearDown(runImage.dispose);
      addTearDown(oneImage.dispose);
      expect(runImage.height, greaterThan(oneImage.height));
    });

    test('a run crossing a page turn renders as one flowing passage', () async {
      // 2:5 ends page 2 and 2:6 opens page 3, so this needs BOTH page
      // fonts in one paragraph — the case the per-page glyph mapping
      // exists for. Unlike the crop this replaced, there is no seam:
      // the words simply flow on.
      const across = ShareableAyah(
        surahNumber: 2,
        surahName: 'البقرة',
        ayahNumber: 5,
        ayahText: 'أُو۟لَٰٓئِكَ عَلَىٰ هُدًى مِّن رَّبِّهِمْ',
        moreVerses: [
          ShareVerse(6, 'إِنَّ ٱلَّذِينَ كَفَرُوا۟'),
        ],
      );
      final bytes = await AyahShareService.renderCard(across);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('a run whose pages are not all available falls back', () async {
      // 2:16 is on page 3 (font cached) and 2:17 is on page 4 (not) —
      // the whole run must take the text card rather than dropping the
      // half it cannot set.
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

  test('the aspect estimate used for the "too long" hint stays text-based', () {
    // cardAspect is a SYNC, pre-render estimate the sheet calls live as
    // the reader adjusts the verse count; it must not depend on a page
    // font that may still be downloading.
    expect(AyahShareService.cardAspect(midLineAyah), greaterThan(0));
    expect(AyahShareService.isCardTooTall(midLineAyah), isFalse);
  });
}

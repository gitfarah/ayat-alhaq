import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/ayah_share_service.dart';

void main() {
  // Card rendering reaches the engine (Paragraph layout, Picture.toImage)
  // and completes in REAL time, so these stay plain `test`s with the
  // binding brought up by hand. Inside `testWidgets` the fake-async zone
  // never advances real time and the await hangs forever.
  TestWidgetsFlutterBinding.ensureInitialized();

  const verse = 'ٱلَّذِينَ يُقِيمُونَ ٱلصَّلَوٰةَ';

  const ayahOnly = ShareableAyah(
    surahNumber: 8,
    surahName: 'الأنفال',
    ayahNumber: 3,
    ayahText: verse,
  );

  final withTafsir = ShareableAyah(
    surahNumber: ayahOnly.surahNumber,
    surahName: ayahOnly.surahName,
    ayahNumber: ayahOnly.ayahNumber,
    ayahText: verse,
    tafsirText: 'الذين يداومون على أداء الصلوات المفروضة في أوقاتها.',
    tafsirName: 'التفسير الميسر',
  );

  group('shared text', () {
    test('quotes the verse in ornate brackets with its reference', () {
      final text = AyahShareService.buildText(ayahOnly);
      expect(text, contains('﴿$verse﴾'));
      // Arabic-Indic digits, as the app shows ayah numbers everywhere.
      expect(text, contains('[الأنفال — ٣]'));
    });

    test('names the app so a forwarded verse says where it came from', () {
      expect(AyahShareService.buildText(ayahOnly), contains('آيات الحق'));
    });

    test('leaves tafsir out unless one was supplied', () {
      expect(ayahOnly.hasTafsir, isFalse);
      expect(AyahShareService.buildText(ayahOnly), isNot(contains('الميسر')));
    });

    test('includes the tafsir and its edition name when asked', () {
      final text = AyahShareService.buildText(withTafsir);
      expect(withTafsir.hasTafsir, isTrue);
      expect(text, contains('التفسير الميسر:'));
      expect(text, contains('الذين يداومون'));
      // The verse still leads — the tafsir follows it, not the reverse.
      expect(text.indexOf(verse), lessThan(text.indexOf('الذين يداومون')));
    });

    test('whitespace-only tafsir counts as no tafsir', () {
      const blank = ShareableAyah(
        surahNumber: 1,
        surahName: 'الفاتحة',
        ayahNumber: 1,
        ayahText: verse,
        tafsirText: '   ',
        tafsirName: 'التفسير الميسر',
      );
      expect(blank.hasTafsir, isFalse);
    });
  });

  // Regression: the first cut passed no origin rect at all, and iOS
  // validates it on iPhone as well as iPad — the share sheet then never
  // appeared and the plugin call returned as though it had worked, so
  // both share buttons looked like they did nothing.
  group('share-sheet origin', () {
    test('a real button rect is passed through untouched', () {
      const rect = Rect.fromLTWH(20, 640, 160, 48);
      expect(AyahShareService.safeOrigin(rect), rect);
    });

    test('a missing rect falls back to a non-zero one', () {
      final origin = AyahShareService.safeOrigin(null);
      expect(origin.width, greaterThan(0));
      expect(origin.height, greaterThan(0));
    });

    test('a zero-sized rect is never handed to the platform', () {
      final origin = AyahShareService.safeOrigin(Rect.zero);
      expect(origin.isEmpty, isFalse);
    });
  });

  // The surah-name font is a LIGATURE font: it carries the 114 names
  // and no ordinary letters, so the wrong lookup string renders as
  // nothing at all rather than as wrong-looking text. "005" alone draws
  // an empty band; only "surah005" resolves.
  group('surah-name lookup string', () {
    test('is the zero-padded surah number behind a "surah" prefix', () {
      expect(AyahShareService.surahNameGlyph(5), 'surah005');
      expect(AyahShareService.surahNameGlyph(1), 'surah001');
      expect(AyahShareService.surahNameGlyph(114), 'surah114');
    });
  });

  group('shared card', () {
    test('renders a PNG for a verse on its own', () async {
      final bytes = await AyahShareService.renderCard(ayahOnly);
      expect(bytes, isNotEmpty);
      // PNG magic number — proof this is a real encoded image, not an
      // empty buffer that happens to have length.
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('a tafsir makes the card taller, never truncated', () async {
      final short = await AyahShareService.renderCard(ayahOnly);
      final tall = await AyahShareService.renderCard(withTafsir);
      // Same width, more content — so the file must grow.
      expect(tall.length, greaterThan(short.length));
    });

    // The first cut laid the card out at on-page reading sizes, which
    // came out unreadable once the image was scaled down into a chat.
    test('type is sized for a card, not a page', () async {
      final bytes = await AyahShareService.renderCard(ayahOnly);
      final image = await decodeImageFromList(bytes);
      addTearDown(image.dispose);
      expect(image.width, 1080);
      // A short verse with a banner, reference and footer still needs
      // real vertical room at these sizes; a collapsed card means the
      // paragraphs laid out far smaller than intended.
      expect(image.height, greaterThan(600));
    });
  });
}

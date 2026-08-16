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

    test('every background renders a real PNG', () async {
      for (final bg in kShareBackgrounds) {
        final bytes = await AyahShareService.renderCard(ayahOnly, style: bg);
        expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47],
            reason: 'background ${bg.id}');
      }
    });
  });

  group('card backgrounds', () {
    test('black is actually black, not a dark grey', () {
      // The point of the option: on an OLED screen the card should have
      // no visible edges at all.
      final black = shareBackgroundById('black');
      expect(black.top, const Color(0xFF000000));
      expect(black.bottom, const Color(0xFF000000));
    });

    test('every ground carries ink that can be read on it', () {
      // The card is looked at in someone else's chat, so a ground and
      // an ink that drift toward each other cannot be caught by looking
      // at the app.
      for (final bg in kShareBackgrounds) {
        double lum(Color c) => c.computeLuminance();
        final contrast = (lum(bg.ink) > lum(bg.top))
            ? (lum(bg.ink) + 0.05) / (lum(bg.top) + 0.05)
            : (lum(bg.top) + 0.05) / (lum(bg.ink) + 0.05);
        expect(contrast, greaterThan(7.0), reason: 'ink on ${bg.id}');
      }
    });

    test('ids are unique and the default leads', () {
      final ids = kShareBackgrounds.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(kShareBackgrounds.first.id, 'emerald',
          reason: 'the ground every card was drawn on before there was '
              'a choice must stay the default');
    });

    test('an unknown or missing saved id falls back rather than throwing', () {
      // A card must still render for someone whose saved preference
      // names a background a later build removed.
      expect(shareBackgroundById(null).id, 'emerald');
      expect(shareBackgroundById('sepia-from-2019').id, 'emerald');
    });

    test('the bands behind the surah name stay part of the ground', () {
      // The cartouche is a panel ON the card, not a plate stuck to it:
      // if its fill drifts far from the ground the band stops reading
      // as part of the page it is heading.
      for (final bg in kShareBackgrounds) {
        final d =
            (bg.bandFill.computeLuminance() - bg.top.computeLuminance()).abs();
        expect(d, lessThan(0.12), reason: 'band on ${bg.id}');
      }
    });
  });

  group('sharing a run of verses', () {
    const run = ShareableAyah(
      surahNumber: 2,
      surahName: 'البقرة',
      ayahNumber: 2,
      ayahText: 'ذَٰلِكَ ٱلْكِتَٰبُ لَا رَيْبَ',
      moreVerses: [
        ShareVerse(3, 'ٱلَّذِينَ يُؤْمِنُونَ بِٱلْغَيْبِ'),
        ShareVerse(4, 'وَٱلَّذِينَ يُؤْمِنُونَ بِمَآ أُنزِلَ إِلَيْكَ'),
      ],
    );

    test('a lone verse still reports itself as one', () {
      expect(ayahOnly.verseCount, 1);
      expect(ayahOnly.lastAyahNumber, ayahOnly.ayahNumber);
      expect(ayahOnly.referenceLabel, 'الآية ٣');
    });

    test('a run knows its span', () {
      expect(run.verseCount, 3);
      expect(run.lastAyahNumber, 4);
      expect(run.referenceLabel, 'الآيات ٢ - ٤');
    });

    test('the text form numbers each verse inside one quotation', () {
      final text = AyahShareService.buildText(run);
      // One pair of outer brackets around the whole passage, as the
      // Mushaf sets it — not three separately quoted lines.
      expect('﴿'.allMatches(text).length, 4); // outer + one per verse
      expect(text, contains('﴿٣﴾'));
      expect(text, contains('[البقرة — ٢-٤]'));
    });

    test('every verse of the run actually reaches the text', () {
      final text = AyahShareService.buildText(run);
      for (final v in run.verses) {
        expect(text, contains(v.text));
      }
    });

    test('a run makes a taller card than the verse it started from', () {
      final one = AyahShareService.cardAspect(ayahOnly);
      expect(AyahShareService.cardAspect(run), greaterThan(one));
    });

    test('a run renders as a real PNG', () async {
      final bytes = await AyahShareService.renderCard(run);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  group('translation', () {
    const translated = ShareableAyah(
      surahNumber: 8,
      surahName: 'الأنفال',
      ayahNumber: 3,
      ayahText: verse,
      translationText: 'Those who establish prayer.',
      translationName: 'English',
    );

    test('a verse with no translation asked for carries none', () {
      expect(ayahOnly.hasTranslation, isFalse);
      expect(AyahShareService.buildText(ayahOnly),
          isNot(contains('Those who establish')));
    });

    test('the text form puts the translation under the Arabic', () {
      final text = AyahShareService.buildText(translated);
      expect(text, contains('English:'));
      expect(text, contains('Those who establish prayer.'));
      // The Arabic leads; the translation follows it.
      expect(text.indexOf(verse), lessThan(text.indexOf('Those who')));
    });

    test('the translation sits above the tafsir, not below it', () {
      // They are different things: one is the verse in another
      // language, the other is commentary ON it.
      const both = ShareableAyah(
        surahNumber: 8,
        surahName: 'الأنفال',
        ayahNumber: 3,
        ayahText: verse,
        translationText: 'Those who establish prayer.',
        translationName: 'English',
        tafsirText: 'الذين يداومون على أداء الصلوات.',
        tafsirName: 'التفسير الميسر',
      );
      final text = AyahShareService.buildText(both);
      expect(
          text.indexOf('Those who'), lessThan(text.indexOf('الذين يداومون')));
    });

    test('a run is translated verse by verse, each one numbered', () {
      const run = ShareableAyah(
        surahNumber: 2,
        surahName: 'البقرة',
        ayahNumber: 2,
        ayahText: 'ذَٰلِكَ ٱلْكِتَٰبُ',
        translationText: 'This is the Book.',
        translationName: 'English',
        moreVerses: [
          ShareVerse(3, 'ٱلَّذِينَ يُؤْمِنُونَ',
              translation: 'Who believe in the unseen.'),
        ],
      );
      final text = AyahShareService.buildText(run);
      expect(text, contains('(2) This is the Book.'));
      expect(text, contains('(3) Who believe in the unseen.'));
    });

    test('a run only partly covered by the edition still works', () {
      // alquran.cloud editions do occasionally miss a verse; that must
      // cost the reader that line, not the whole share.
      const partial = ShareableAyah(
        surahNumber: 2,
        surahName: 'البقرة',
        ayahNumber: 2,
        ayahText: 'ذَٰلِكَ ٱلْكِتَٰبُ',
        translationName: 'English',
        moreVerses: [
          ShareVerse(3, 'ٱلَّذِينَ يُؤْمِنُونَ', translation: 'Who believe.'),
        ],
      );
      expect(partial.hasTranslation, isTrue);
      expect(AyahShareService.buildText(partial), contains('(3) Who believe.'));
    });

    test('a translation makes the card taller', () {
      expect(AyahShareService.cardAspect(translated),
          greaterThan(AyahShareService.cardAspect(ayahOnly)));
    });

    test('a translated card renders on every ground', () async {
      for (final bg in kShareBackgrounds) {
        final bytes = await AyahShareService.renderCard(translated, style: bg);
        expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: bg.id);
      }
    });

    test('a right-to-left translation renders too', () async {
      const urdu = ShareableAyah(
        surahNumber: 8,
        surahName: 'الأنفال',
        ayahNumber: 3,
        ayahText: verse,
        translationText: 'جو نماز قائم کرتے ہیں۔',
        translationName: 'اردو',
        translationRtl: true,
      );
      final bytes = await AyahShareService.renderCard(urdu);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  group('warning that a card has grown too tall', () {
    // The hint exists because a messenger scales an image to the bubble
    // WIDTH: past a point, adding verses shrinks all of them rather
    // than making the card longer.
    ShareableAyah runOf(int n) => ShareableAyah(
          surahNumber: 2,
          surahName: 'البقرة',
          ayahNumber: 1,
          ayahText:
              'وَٱلَّذِينَ يُؤْمِنُونَ بِمَآ أُنزِلَ إِلَيْكَ وَمَآ أُنزِلَ مِن قَبْلِكَ',
          moreVerses: [
            for (var i = 2; i <= n; i++)
              ShareVerse(
                  i,
                  'وَٱلَّذِينَ يُؤْمِنُونَ بِمَآ أُنزِلَ إِلَيْكَ وَمَآ أُنزِلَ مِن '
                  'قَبْلِكَ وَبِٱلْءَاخِرَةِ هُمْ يُوقِنُونَ'),
          ],
        );

    test('an ordinary single verse never trips it', () {
      expect(AyahShareService.isCardTooTall(ayahOnly), isFalse);
      expect(AyahShareService.isCardTooTall(withTafsir), isFalse);
    });

    test('a long enough run does trip it', () {
      expect(AyahShareService.isCardTooTall(runOf(30)), isTrue);
    });

    test('the measure grows with the passage, monotonically', () {
      // Measured from the real layout rather than guessed from a verse
      // COUNT — one ayah of Al-Baqarah runs longer than twenty short
      // ones, so a count-based rule would warn on the wrong passages.
      var last = 0.0;
      for (final n in [1, 5, 10, 20]) {
        final aspect = AyahShareService.cardAspect(runOf(n));
        expect(aspect, greaterThan(last), reason: '$n verses');
        last = aspect;
      }
    });
  });
}

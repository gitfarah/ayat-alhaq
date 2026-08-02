import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/ayah_insight_service.dart';

void main() {
  group('stripWordPrefix', () {
    test('drops the repeated {word}: heading the works open with', () {
      // Verbatim from word-tasreef for 2:255 word 1.
      expect(
        AyahInsightService.stripWordPrefix(
            '{اللَّهُ}: اسْمٌ، مُذَكَّرٌ، مُفْرَدٌ، جَامِدٌ.'),
        'اسْمٌ، مُذَكَّرٌ، مُفْرَدٌ، جَامِدٌ.',
      );
    });

    test('also handles the ornate ﴿﴾ brackets', () {
      expect(AyahInsightService.stripWordPrefix('﴿قَالَ﴾ : فِعْلٌ مَاضٍ'),
          'فِعْلٌ مَاضٍ');
    });

    test('leaves entries that carry no heading untouched', () {
      const plain = 'اسْمُ الْجَلَالَةِ مُبْتَدَأٌ مَرْفُوعٌ.';
      expect(AyahInsightService.stripWordPrefix(plain), plain);
    });

    test('does not eat a brace that is not a heading', () {
      // No colon after the closing brace, so this is body text.
      const t = '{اللَّهُ} مبتدأ';
      expect(AyahInsightService.stripWordPrefix(t), t);
    });
  });

  group('eerabLines', () {
    // Shape taken from eerab-aya for 2:255.
    const sample = '{اللَّهُ لَا إِلَهَ إِلَّا هُوَ (255)}\r\n'
        'اللَّهُ: لفظ الجلالة مبتدأ مرفوع بالضمّة الظاهرة.\r\n'
        'لَا: النافية للجنس حرف مبنيّ على السكون.\r\n';

    test('drops the braced ayah header and keeps one line per word', () {
      final lines = AyahInsightService.eerabLines(sample);
      expect(lines.length, 2);
      expect(lines.first, startsWith('اللَّهُ:'));
      expect(lines.last, startsWith('لَا:'));
    });

    test('keeps the first line when it is not the ayah header', () {
      expect(AyahInsightService.eerabLines('أول\nثان').length, 2);
    });

    test('blank lines are discarded', () {
      expect(AyahInsightService.eerabLines('\n\nأول\n\n\nثان\n\n'),
          ['أول', 'ثان']);
    });
  });

  group('qiraatSegments', () {
    // Verbatim shape from word-qeraat.
    const agreed = 'لا خلاف بين القراء في هذا الموضع\n'
        '---{عند الوصل}---\n'
        'لا خلاف بين القراء في هذا الموضع';

    test('splits on the ---{label}--- marker', () {
      final parts = AyahInsightService.qiraatSegments(agreed);
      expect(parts.length, 2);
      // The opening slice is unlabelled; the label belongs to what
      // FOLLOWS the marker, not what precedes it.
      expect(parts.first.label, isNull);
      expect(parts.first.text, 'لا خلاف بين القراء في هذا الموضع');
      expect(parts.last.label, 'عند الوصل');
    });

    test('an entry with no marker is a single unlabelled segment', () {
      final parts = AyahInsightService.qiraatSegments('قرأ ابن كثير بالتشديد');
      expect(parts.length, 1);
      expect(parts.single.label, isNull);
      expect(parts.single.text, 'قرأ ابن كثير بالتشديد');
    });

    test('a marker with nothing after it adds no empty segment', () {
      final parts =
          AyahInsightService.qiraatSegments('نص\n---{عند الوصل}---\n   ');
      expect(parts.length, 1);
      expect(parts.single.text, 'نص');
    });
  });

  group('qiraatHasVariance', () {
    test('is false when every reading is "no difference"', () {
      expect(
        AyahInsightService.qiraatHasVariance(
            'لا خلاف بين القراء في هذا الموضع\n'
            '---{عند الوصل}---\n'
            'لا خلاف بين القراء في هذا الموضع'),
        isFalse,
      );
    });

    test('is true when any single reading differs', () {
      // The pausal reading agrees but the connected one does not — the
      // word still belongs in the filtered list.
      expect(
        AyahInsightService.qiraatHasVariance(
            'لا خلاف بين القراء في هذا الموضع\n'
            '---{عند الوصل}---\n'
            'قرأ حمزة بإسكان الهاء'),
        isTrue,
      );
    });

    test('is false for an empty entry', () {
      expect(AyahInsightService.qiraatHasVariance('   \n  '), isFalse);
    });
  });

  group('WordInsight.fromJson', () {
    test('reads the API shape and trims', () {
      final w = WordInsight.fromJson(const {
        'sura_number': 2,
        'aya_number': 255,
        'word_number': 3,
        'word': ' إِلَهَ ',
        'content': ' اسْمُ لا مبنيّ على الفتح ',
      });
      expect(w.wordNumber, 3);
      expect(w.word, 'إِلَهَ');
      expect(w.content, 'اسْمُ لا مبنيّ على الفتح');
    });

    test('a missing content field becomes empty, not null', () {
      final w = WordInsight.fromJson(const {'word_number': 1, 'word': 'ا'});
      expect(w.content, isEmpty);
    });
  });

  group('InsightKind metadata', () {
    test('every kind names a tab and cites a source', () {
      for (final kind in InsightKind.values) {
        expect(kind.title, isNotEmpty);
        expect(kind.source, isNotEmpty);
      }
    });
  });
}

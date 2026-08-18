// The default tafsir edition is whichever one sits first in the list —
// the tafsir screen and the ayah share sheet both fall back to
// `editions.first`, so ordering here IS the default-edition setting.

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/tafsir_service.dart';

void main() {
  group('default edition', () {
    test('Al-Mukhtasar is first, matching defaultEditionId', () {
      expect(TafsirService.editions.first.id,
          TafsirService.defaultEditionId);
      expect(TafsirService.editions.first.name,
          'المختصر في تفسير القرآن الكريم');
      expect(TafsirService.editions.first.cdnSlug, 'ar-tafsir-al-mukhtasar');
    });

    test('editionById resolves the default id', () {
      final edition =
          TafsirService.editionById(TafsirService.defaultEditionId);
      expect(edition, isNotNull);
      expect(edition, same(TafsirService.editions.first));
    });
  });

  group('editions list integrity', () {
    test('every id is unique — a collision would silently merge two '
        'editions\' downloads/preferences', () {
      final ids = TafsirService.editions.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every cdnSlug is unique and non-empty', () {
      final slugs = TafsirService.editions.map((e) => e.cdnSlug).toList();
      expect(slugs.toSet().length, slugs.length);
      expect(slugs, everyElement(isNotEmpty));
    });

    test('every name is unique and non-empty — the picker lists them '
        'by name', () {
      final names = TafsirService.editions.map((e) => e.name).toList();
      expect(names.toSet().length, names.length);
      expect(names, everyElement(isNotEmpty));
    });

    test('unknown id resolves to nothing, not a guess', () {
      expect(TafsirService.editionById(-1), isNull);
    });
  });
}
